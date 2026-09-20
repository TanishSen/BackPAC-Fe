/// A live voice call with the BackPAC agent, over LiveKit.
///
/// This is the real counterpart to the demo's `SimulatedSpeechService`. Instead
/// of faking speech, the app joins the LiveKit room the backend minted, and:
///
///   - publishes the phone's microphone (the agent's server-side STT hears it),
///   - plays the agent's voice automatically (LiveKit plays remote audio tracks),
///   - receives the live transcript + result cards over the data channel, which
///     the agent's WordInterceptor / CardDispatcher publish,
///   - reports who is talking and how loudly, so the orb can react.
///
/// The UI binds to the streams below; it never touches LiveKit directly.
///
/// ## Data-channel contract — must match the agent side exactly
///
/// Transcript, on topic `"transcription"` (agent: WordInterceptor):
/// ```json
/// {"role": "user"|"agent", "text": "…", "speech_final": true|false}
/// ```
/// Agent text arrives as a stream of fragments with `speech_final: false`,
/// then one empty fragment with `speech_final: true` meaning "that turn is
/// finished". User text arrives as a single final line.
///
/// Cards, on the default topic (agent: CardDispatcher → Pipecat's RTVI layer).
/// Pipecat wraps every server message in an RTVI envelope, so the payload is
/// one level down — reading `type` off the outer object finds
/// `"server-message"`, never `"agent-card"`:
/// ```json
/// {"label":"rtvi-ai","type":"server-message",
///  "data":{"type":"agent-card","cardType":"search_trains","payload":[…]}}
/// ```
///
/// Typed input, outbound, on topic `"user-text"` (agent: text_input.py):
/// ```json
/// {"type": "user-text", "text": "trains to jaipur on friday"}
/// ```
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import 'backend_client.dart';

/// One fragment of the running transcript.
class TranscriptLine {
  const TranscriptLine({
    required this.role,
    required this.text,
    required this.isFinal,
  });

  final String role; // "user" | "agent"
  final String text;

  /// For the agent, true marks the end of a turn (and `text` is empty).
  /// For the user, a line is always final.
  final bool isFinal;

  bool get isAgent => role == 'agent';
}

/// A result card the agent emitted (a train/flight/stay list).
class AgentCard {
  const AgentCard({required this.cardType, required this.payload});

  final String cardType; // e.g. "search_trains"
  final dynamic payload; // already-decoded JSON: a list of rows
}

enum CallState { idle, connecting, live, ended, error }

/// Who is making noise right now. The orb reads this.
enum Talker { nobody, user, agent }

class VoiceSession {
  VoiceSession(this._backend);

  final BackendClient _backend;
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  Timer? _levelPoll;

  // --- streams the UI listens to -------------------------------------------
  final _transcript = StreamController<TranscriptLine>.broadcast();
  final _cards = StreamController<AgentCard>.broadcast();
  final _state = StreamController<CallState>.broadcast();

  Stream<TranscriptLine> get transcript => _transcript.stream;
  Stream<AgentCard> get cards => _cards.stream;
  Stream<CallState> get state => _state.stream;

  /// Loudness, 0..1, refreshed ~16 times a second. A notifier rather than a
  /// stream because it changes far too often to rebuild a page — only the
  /// painters that care should listen.
  final ValueNotifier<double> level = ValueNotifier<double>(0);

  /// Who that loudness belongs to.
  final ValueNotifier<Talker> talker = ValueNotifier<Talker>(Talker.nobody);

  /// Whether the microphone is actually live, as LiveKit sees it.
  ///
  /// Deliberately not a boolean we flip ourselves. Muting stops the capture
  /// device and unmuting re-acquires it, both asynchronously and both through
  /// LiveKit's own serialising queue — so a local "is it on?" flag drifts out
  /// of step with reality the moment a tap lands while the previous one is
  /// still settling, and the button starts lying about whether it is muted.
  /// This is refreshed from [LocalParticipant.isMicrophoneEnabled] after every
  /// change, including ones we did not make.
  final ValueNotifier<bool> micEnabled = ValueNotifier<bool>(false);

  /// True when the platform refused the microphone — permission denied, or no
  /// usable capture device.
  ///
  /// Kept separate from a general failure because the remedy is completely
  /// different: nothing about retrying or checking your connection helps, the
  /// user has to grant the permission. The call itself carries on without it.
  final ValueNotifier<bool> micBlocked = ValueNotifier<bool>(false);

  /// True while a mute/unmute is in flight.
  bool _micBusy = false;

  /// Does this failure look like the user (or the OS) saying no?
  ///
  /// Matched on the message rather than the type: LiveKit wraps the platform
  /// error in a TrackCreateException, and the useful distinction — refused
  /// versus broken — only survives in the text underneath.
  static bool _isPermissionDenial(Object error) {
    final String text = error.toString().toLowerCase();
    return text.contains('notallowed') ||
        text.contains('not allowed') ||
        text.contains('permission') ||
        text.contains('denied') ||
        text.contains('notfound');
  }

  /// What the last tap asked for, if it arrived while one was in flight.
  ///
  /// Muting stops the capture device and unmuting re-acquires it, which takes
  /// long enough that a second tap regularly lands mid-change. Dropping that
  /// tap is what makes the button feel unreliable — you press it and nothing
  /// happens. Remembering it and applying it afterwards means the microphone
  /// always ends up where the last tap asked for, however fast the tapping.
  bool? _micWanted;

  String? lastError;

  /// Completes once a remote participant — the agent — is in the room.
  ///
  /// Needed because joining is a race. The backend asks the agent to join
  /// *before* it answers the app, but the agent joins asynchronously, so the
  /// app frequently connects first. A data packet sent in that window reaches
  /// nobody: LiveKit does not hold messages for participants who have not
  /// arrived. Anything the app wants to *say* on connect has to wait for this.
  final Completer<bool> _agentPresent = Completer<bool>();

  /// Start a call: ask the backend for a room, join it, publish the mic.
  ///
  /// Throws if the backend is down, LiveKit is unconfigured, or the agent
  /// refused — the caller decides what to show. Anything thrown here means no
  /// call is in progress.
  Future<void> start({required String agentId, String? participantName}) async {
    lastError = null;
    _state.add(CallState.connecting);
    try {
      final info = await _backend.startSession(
        agentId: agentId,
        participantName: participantName,
      );

      final room = Room();
      _listener = room.createListener();
      _wireEvents(_listener!);

      await room.connect(info.livekitUrl, info.token);

      // Publish the mic, then mute it, so a call opens muted.
      //
      // Publishing first is what triggers the OS permission prompt, and asking
      // once here is kinder than ambushing someone the moment they want to
      // speak. Opening muted is the point though: the greeting plays out of the
      // speaker, and an open mic hears it, which is how the assistant ends up
      // transcribing itself.
      final LocalParticipant? me = room.localParticipant;
      try {
        await me?.setMicrophoneEnabled(true);
        await me?.setMicrophoneEnabled(false);
        micBlocked.value = false;
      } catch (e) {
        // Deliberately not fatal. Refusing the microphone should cost you the
        // microphone, not the conversation: the agent still joins and greets,
        // the transcript still arrives, and the keyboard still works. Failing
        // the whole call here reported it as "couldn't reach the assistant",
        // which is both wrong and unactionable.
        micBlocked.value = true;
        lastError = e.toString();
        debugPrint('[backPAC] microphone unavailable, continuing muted: $e');
      }

      _room = room;
      micEnabled.value = false; // muted, whether by us or by the refusal
      // The agent may already have been in the room when we connected, in
      // which case no event is coming and we would wait forever.
      if (room.remoteParticipants.isNotEmpty) _markAgentPresent(true);
      _startLevelPolling();
      _state.add(CallState.live);
    } catch (e) {
      lastError = e.toString();
      _state.add(CallState.error);
      await _teardown();
      rethrow;
    }
  }

  void _wireEvents(EventsListener<RoomEvent> listener) {
    listener
      ..on<DataReceivedEvent>(_onData)
      ..on<ParticipantConnectedEvent>((_) => _markAgentPresent(true))
      // Mutes we did not ask for — a track ending, another tab taking the
      // device — must still be reflected on the button.
      ..on<TrackMutedEvent>((TrackMutedEvent e) =>
          _onMuteChanged(e.participant, true))
      ..on<TrackUnmutedEvent>((TrackUnmutedEvent e) =>
          _onMuteChanged(e.participant, false))
      ..on<RoomDisconnectedEvent>((_) {
        _stopLevelPolling();
        _state.add(CallState.ended);
      });
  }

  void _markAgentPresent(bool present) {
    if (!_agentPresent.isCompleted) _agentPresent.complete(present);
  }

  /// Waits for the agent to join. Returns false if it never showed up, so the
  /// caller can decide whether to send anyway or tell the user.
  Future<bool> waitForAgent({
    Duration timeout = const Duration(seconds: 15),
  }) {
    if (_agentPresent.isCompleted) return _agentPresent.future;
    return _agentPresent.future.timeout(timeout, onTimeout: () => false);
  }

  /// Decode a data-channel packet into a transcript line or a card.
  void _onData(DataReceivedEvent e) {
    try {
      final decoded = jsonDecode(utf8.decode(e.data));
      if (decoded is! Map<String, dynamic>) return;

      if (e.topic == 'transcription') {
        _transcript.add(TranscriptLine(
          role: decoded['role'] as String? ?? 'agent',
          text: decoded['text'] as String? ?? '',
          isFinal: decoded['speech_final'] as bool? ?? false,
        ));
        return;
      }

      // Cards travel inside an RTVI envelope — see the contract above.
      final body = decoded['type'] == 'server-message'
          ? decoded['data']
          : decoded;
      if (body is Map<String, dynamic> && body['type'] == 'agent-card') {
        _cards.add(AgentCard(
          cardType: body['cardType'] as String? ?? 'unknown',
          payload: body['payload'],
        ));
      }
    } catch (_) {
      // A malformed packet must never kill a call in progress — drop it.
    }
  }

  // --- who is talking, and how loudly --------------------------------------
  /// LiveKit only fires an event when the *set* of active speakers changes,
  /// which is far too coarse for an animation. Polling `audioLevel` gives the
  /// continuous signal the orb needs.
  void _startLevelPolling() {
    _levelPoll?.cancel();
    _levelPoll = Timer.periodic(const Duration(milliseconds: 60), (_) {
      final room = _room;
      if (room == null) return;

      final local = room.localParticipant;
      final double userLevel =
          (local != null && local.isSpeaking) ? local.audioLevel : 0;

      double agentLevel = 0;
      for (final p in room.remoteParticipants.values) {
        if (p.isSpeaking && p.audioLevel > agentLevel) agentLevel = p.audioLevel;
      }

      // The agent wins ties: while it is speaking the orb should show its
      // voice, not the echo of it coming back through the mic.
      if (agentLevel > 0.01) {
        talker.value = Talker.agent;
        level.value = agentLevel.clamp(0.0, 1.0);
      } else if (userLevel > 0.01) {
        talker.value = Talker.user;
        level.value = userLevel.clamp(0.0, 1.0);
      } else {
        talker.value = Talker.nobody;
        level.value = 0;
      }
    });
  }

  void _stopLevelPolling() {
    _levelPoll?.cancel();
    _levelPoll = null;
    level.value = 0;
    talker.value = Talker.nobody;
  }

  /// Send typed text to the agent over the data channel.
  ///
  /// The agent treats it exactly like something said out loud (see its
  /// `text_input.py`), so the keyboard and the microphone feed one
  /// conversation rather than two.
  Future<void> sendUserText(String text) async {
    final local = _room?.localParticipant;
    if (local == null) return;
    await local.publishData(
      utf8.encode(jsonEncode({'type': 'user-text', 'text': text})),
      reliable: true,
      topic: 'user-text',
    );
  }

  /// Mute or unmute. Muting does not end the call — the agent simply stops
  /// hearing anything.
  ///
  /// Whatever happens, [micEnabled] ends up matching what LiveKit actually did,
  /// including when the request fails outright (a revoked permission, a device
  /// that has gone away). Reporting success and leaving the button showing the
  /// opposite of the truth is the worst of the available outcomes.
  Future<void> setMicEnabled(bool enabled) async {
    final LocalParticipant? me = _room?.localParticipant;
    if (me == null) return;
    if (_micBusy) {
      // Settle this once the change already running finishes.
      _micWanted = enabled;
      return;
    }
    _micBusy = true;
    try {
      await me.setMicrophoneEnabled(enabled);
      // The call returned without throwing, so this is what the microphone is
      // doing. `isMicrophoneEnabled()` is deliberately not read back here: it
      // reports whether a publication exists and is unmuted, which after a
      // publish-then-mute came back disagreeing with what the server had, and
      // a button that contradicts the server is worse than no button.
      // TrackMuted/TrackUnmuted below are the authority and will correct this.
      micEnabled.value = enabled;
      micBlocked.value = false;
    } catch (e) {
      lastError = e.toString();
      if (_isPermissionDenial(e)) micBlocked.value = true;
    } finally {
      _micBusy = false;
    }

    // Apply whatever was asked for while we were busy. Only the newest matters:
    // a flurry of taps should leave the microphone where the last one wanted
    // it, not replay every intermediate state.
    final bool? pending = _micWanted;
    _micWanted = null;
    if (pending != null && pending != micEnabled.value) {
      await setMicEnabled(pending);
    }
  }

  /// Flip it.
  ///
  /// Flips whatever was asked for most recently rather than what has settled,
  /// so two quick taps are an on and then an off — not two identical requests
  /// computed from a state that has not caught up yet.
  Future<void> toggleMic() =>
      setMicEnabled(!(_micWanted ?? micEnabled.value));

  bool get isMicEnabled => micEnabled.value;

  /// Read the truth back out of LiveKit.
  /// Correct [micEnabled] from a mute/unmute event.
  ///
  /// Only for the local participant: the agent's track mutes too, and that says
  /// nothing about whether *our* microphone is open.
  void _onMuteChanged(Participant participant, bool muted) {
    if (participant.sid != _room?.localParticipant?.sid) return;
    micEnabled.value = !muted;
  }

  Future<void> end() async {
    await _teardown();
    _state.add(CallState.ended);
  }

  Future<void> _teardown() async {
    _markAgentPresent(false); // release anyone waiting on a call that is over
    _stopLevelPolling();
    micEnabled.value = false;
    await _room?.disconnect();
    await _listener?.dispose();
    _room = null;
    _listener = null;
  }

  void dispose() {
    _stopLevelPolling();
    _listener?.dispose();
    _room?.dispose();
    level.dispose();
    talker.dispose();
    micEnabled.dispose();
    micBlocked.dispose();
    _transcript.close();
    _cards.close();
    _state.close();
  }
}
