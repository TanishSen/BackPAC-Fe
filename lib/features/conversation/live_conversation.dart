/// A real conversation with the BackPAC agent, over a LiveKit voice call.
///
/// What this class actually does is translate between two different shapes of
/// the same conversation:
///
///   the call  — a continuous audio stream, plus a data channel dribbling
///               transcript fragments and result cards,
///   the chat  — an ordered list of finished messages the screen can render.
///
/// The translation that matters is **the streaming agent turn**. The agent
/// speaks as it thinks, so its words arrive a fragment at a time. Rather than
/// litter the thread with fragments, the first fragment opens one assistant
/// message and every later fragment rewrites it, until `speech_final` closes
/// the turn. On screen that reads as an answer being typed out, which is also
/// roughly when it is being said aloud.
///
/// Cards attach to the open turn, so "here are two trains" and the list of
/// trains stay together.
///
/// A call is **always on**: the agent hears the room continuously and decides
/// for itself when you have finished speaking. So the mic button is a mute
/// toggle here, not push-to-talk.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/app_config.dart';
import '../chat/model/chat_message.dart';
import '../chat/model/trip_card.dart';
import '../realtime/backend_client.dart';
import '../realtime/voice_session.dart';
import '../voice/voice_controller.dart' show VoiceState;
import 'conversation.dart';

class LiveConversation extends ChangeNotifier implements Conversation {
  LiveConversation({
    BackendClient? backend,
    VoiceSession? session,
    String? opener,
    this.resumeSessionId,
    this.agentId = AppConfig.agentId,
        // ignore: prefer_initializing_formals — a named parameter cannot
        // start with an underscore, so `this._opener` is not expressible.
  })  : _opener = opener,
        _backend = backend ?? BackendClient(baseUrl: AppConfig.backendUrl) {
    _session = session ?? VoiceSession(_backend);
    // Show the opener straight away, before the call is even up. Someone who
    // tapped "Flights" on the home screen should see what they asked for while
    // it connects — and should still see it if connecting fails, rather than
    // arriving at a blank screen that has quietly eaten their request.
    final String? opener = _opener?.trim();
    if (opener != null && opener.isNotEmpty && resumeSessionId == null) {
      _append(ChatAuthor.user, opener);
    }
  }

  final BackendClient _backend;
  final String agentId;

  /// The line that opened the conversation from the home screen, sent once the
  /// call is up so the agent answers it instead of just greeting.
  final String? _opener;

  /// When set, this call continues that earlier conversation instead of
  /// starting a new one: same room, same LangGraph thread, and the transcript
  /// so far painted into the view before the first word.
  ///
  /// A resume never sends an opener. It used to — the history tile handed over
  /// its preview line — and because the preview is the *last* thing said,
  /// which is usually the agent, the app opened by saying the agent's own
  /// words back to it as if the user had. The agent then answered the way
  /// anyone would if a stranger repeated their last sentence at them: "I am
  /// the front desk routing assistant, not a search tool."
  final String? resumeSessionId;

  bool get _isResume => resumeSessionId != null;

  late final VoiceSession _session;

  final List<ChatMessage> _messages = <ChatMessage>[];
  final List<StreamSubscription<Object>> _subs = <StreamSubscription<Object>>[];

  int _seq = 0;

  /// The assistant message currently being streamed into, if a turn is open.
  int? _openTurn;

  ConversationStatus _status = ConversationStatus.idle;
  String? _statusMessage;

  // --- Conversation ---------------------------------------------------------
  @override
  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);

  @override
  ConversationStatus get status => _status;

  @override
  String? get statusMessage => _statusMessage;

  @override
  ValueListenable<double> get level => _session.level;

  /// Nothing to show: on a live call the words appear in the thread as the
  /// agent says them, so a separate "partial" caption would just duplicate it.
  @override
  String get partial => '';

  /// True between the user finishing and the agent's first word arriving.
  @override
  bool get isTyping =>
      _openTurn == null &&
      _messages.isNotEmpty &&
      _messages.last.isUser &&
      _status == ConversationStatus.ready;

  /// Maps the call onto the four states the mic dock knows how to draw.
  @override
  VoiceState get voiceState {
    if (_status == ConversationStatus.connecting) return VoiceState.thinking;
    if (_status != ConversationStatus.ready) return VoiceState.idle;
    if (_session.talker.value == Talker.agent) return VoiceState.speaking;
    // Muted is muted, whatever else is going on. Read from LiveKit rather than
    // from a flag of our own, so the button can never show the opposite of
    // what the microphone is doing.
    if (!_session.micEnabled.value) return VoiceState.idle;
    if (_session.talker.value == Talker.user) return VoiceState.listening;
    return isTyping ? VoiceState.thinking : VoiceState.listening;
  }

  @override
  bool get canType => _status == ConversationStatus.ready;

  /// Resuming already knows the id; a new call learns it from the backend's
  /// reply when the session starts.
  @override
  String? get sessionId => resumeSessionId ?? _session.info?.sessionId;

  @override
  Future<void> start() async {
    _setStatus(ConversationStatus.connecting, 'Starting a session…');

    _subs.add(_session.transcript.listen(_onTranscript));
    _subs.add(_session.cards.listen(_onCard));
    _subs.add(_session.state.listen(_onCallState));
    // Both of these decide what the dock draws and says, so a change in
    // either has to rebuild it.
    _session.talker.addListener(notifyListeners);
    _session.micEnabled.addListener(notifyListeners);
    _session.micBlocked.addListener(notifyListeners);

    try {
      await _session.start(agentId: agentId, resumeSessionId: resumeSessionId);

      // Paint what was said last time, before waiting for the agent. Someone
      // reopening a conversation should see it immediately — the thread is
      // already there, and making them watch a blank screen for the ten
      // seconds the agent takes to join loses the thing they tapped for.
      _replayHistory();

      // Being in the room is not the same as having someone to talk to. The
      // backend asks the agent to join before it answers us, but the agent
      // joins asynchronously and takes about ten seconds to negotiate its own
      // LiveKit connection. Calling this ready at that point is what made the
      // app sit there saying "Listening…" to an empty room.
      _setStatus(ConversationStatus.connecting, 'Waiting for your assistant…');
      final bool agentThere =
          await _session.waitForAgent(timeout: const Duration(seconds: 45));
      if (!agentThere) {
        _setStatus(
          ConversationStatus.failed,
          "Your assistant didn't pick up. Try again in a moment.",
        );
        return;
      }

      _setStatus(
        ConversationStatus.ready,
        _session.micBlocked.value ? _micBlockedMessage : null,
      );

      // Now deliver the opener that is already on screen. Sent directly rather
      // than through send(), which would add a second copy of it. It is safe
      // now: a packet sent into a room the agent has not joined is dropped,
      // and we have just waited for exactly that.
      // A resume has nothing to open with: the agent already knows the
      // conversation, and anything sent here would arrive as a new thing the
      // user just said.
      final String? opener = _opener?.trim();
      if (!_isResume && opener != null && opener.isNotEmpty) {
        await _session.sendUserText(opener);
      }
    } catch (e) {
      _setStatus(ConversationStatus.failed, _friendlyError(e));
    }
  }

  /// Put the earlier transcript into the thread, oldest first.
  ///
  /// Only ever runs once, and only for a resume: the messages already on
  /// screen would otherwise be duplicated by a reconnect.
  void _replayHistory() {
    if (_replayed) return;
    _replayed = true;
    final List<PastMessage> past =
        _session.info?.previousMessages ?? const <PastMessage>[];
    if (past.isEmpty) return;
    for (final PastMessage m in past) {
      _append(m.isUser ? ChatAuthor.user : ChatAuthor.assistant, m.content);
    }
    notifyListeners();
  }

  bool _replayed = false;

  /// Mute and unmute. Ending the call is the back button's job, not the mic's —
  /// a tap that silently hung up would be a nasty surprise.
  ///
  /// A call opens muted, so the first tap here is how someone starts talking.
  @override
  Future<void> onMicTap() async {
    if (_status != ConversationStatus.ready) return;
    await _session.toggleMic();
    // Tapping is also how someone retries after granting the permission, so
    // the message clears itself the moment the microphone actually opens.
    _setStatus(
      ConversationStatus.ready,
      _session.micBlocked.value ? _micBlockedMessage : null,
    );
  }

  /// Actionable, because "try again" is not: nothing the app does will change
  /// a denied permission.
  static const String _micBlockedMessage =
      'Microphone blocked. Allow it in Settings, then tap the mic — '
      'or type instead.';

  /// Typed input. It reaches the agent over the data channel and starts exactly
  /// the same turn a spoken sentence would — see the agent's text_input.py.
  @override
  Future<void> send(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || _status != ConversationStatus.ready) return;
    _append(ChatAuthor.user, trimmed);
    await _session.sendUserText(trimmed);
  }

  @override
  Future<void> end() async {
    await _session.end();
    _setStatus(ConversationStatus.ended, null);
  }

  // --- incoming from the call ----------------------------------------------
  void _onTranscript(TranscriptLine line) {
    if (!line.isAgent) {
      // A spoken user turn — or the agent echoing back something we typed.
      //
      // Comparing against the *last* message is not enough: the opener is put
      // on screen before the call is even up, the agent greets, and only then
      // does the echo arrive, by which point the greeting sits in between. So
      // check the recent user messages instead, which is why the opener showed
      // up twice.
      final bool isEcho = _messages.reversed
          .take(4)
          .any((ChatMessage m) => m.isUser && m.text == line.text);
      if (isEcho) return;
      _closeTurn();
      _append(ChatAuthor.user, line.text);
      return;
    }

    if (line.isFinal) {
      // A final packet normally closes a turn and carries no text. Handle the
      // case where it carries both, so a whole line sent in one go is never
      // thrown away.
      if (line.text.isNotEmpty) _appendToOpenTurn(line.text);
      _closeTurn();
      notifyListeners();
      return;
    }
    if (line.text.isEmpty) return;

    // Open a turn on the first fragment, then keep rewriting it.
    _appendToOpenTurn(line.text);
    notifyListeners();
  }

  /// Adds text to the assistant turn in progress, starting one if needed.
  void _appendToOpenTurn(String text) {
    final int index = _openTurn ?? _append(ChatAuthor.assistant, '');
    _openTurn = index;
    _messages[index] =
        _messages[index].copyWith(text: _messages[index].text + text);
  }

  void _onCard(AgentCard card) {
    final TripCard? parsed = TripCard.fromPayload(card.cardType, card.payload);
    if (parsed == null) return;

    // Attach to the turn being spoken, or open one if the card somehow beat the
    // first word out (searches can finish before the sentence describing them).
    final int index = _openTurn ?? _append(ChatAuthor.assistant, '');
    _openTurn = index;
    _messages[index] = _messages[index].copyWith(card: parsed);
    notifyListeners();
  }

  void _onCallState(CallState state) {
    switch (state) {
      case CallState.live:
        // We are in the room. start() decides when it is actually usable —
        // see the note there about the agent taking its time to arrive.
        break;
      case CallState.ended:
        _closeTurn();
        _setStatus(ConversationStatus.ended, 'Call ended.');
      case CallState.error:
        _setStatus(
          ConversationStatus.failed,
          _friendlyError(_session.lastError ?? 'the call dropped'),
        );
      case CallState.connecting:
        _setStatus(ConversationStatus.connecting, 'Starting a session…');
      case CallState.idle:
        break;
    }
  }

  // --- helpers --------------------------------------------------------------
  /// Appends a message and returns its index.
  int _append(ChatAuthor author, String text) {
    _messages.add(ChatMessage(
      id: 'm${_seq++}',
      author: author,
      text: text,
      at: DateTime.now(),
    ));
    notifyListeners();
    return _messages.length - 1;
  }

  void _closeTurn() {
    if (_openTurn == null) return;
    // A turn that produced a card but no words (or nothing at all) would sit in
    // the thread as an empty bubble. Drop it if there is genuinely nothing.
    final ChatMessage m = _messages[_openTurn!];
    if (m.text.trim().isEmpty && m.card == null) {
      _messages.removeAt(_openTurn!);
    }
    _openTurn = null;
  }

  void _setStatus(ConversationStatus status, String? message) {
    _status = status;
    _statusMessage = message;
    notifyListeners();
  }

  /// Turn an exception into something worth showing a traveller. The detail is
  /// still in the console for whoever is debugging.
  static String _friendlyError(Object error) {
    final String text = error.toString();
    if (text.contains('503')) {
      return 'The assistant is not configured yet. Check the server keys.';
    }
    if (text.contains('502')) {
      return "The voice agent isn't running. Start BackPAC-Agent and try again.";
    }
    return "Couldn't reach the assistant. Check your connection and try again.";
  }

  @override
  void dispose() {
    for (final StreamSubscription<Object> s in _subs) {
      s.cancel();
    }
    _session.talker.removeListener(notifyListeners);
    _session.micEnabled.removeListener(notifyListeners);
    _session.micBlocked.removeListener(notifyListeners);
    _session.dispose();
    _backend.dispose();
    super.dispose();
  }
}
