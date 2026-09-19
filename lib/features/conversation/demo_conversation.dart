/// The offline conversation: a scripted agent and a simulated microphone.
///
/// It needs no backend, no keys and no network, which makes it the right thing
/// to show when live voice is switched off (`--dart-define=LIVE_VOICE=false`)
/// and the right thing to fall back to when a real call cannot be started. The
/// screen cannot tell the difference — that is the point of [Conversation].
///
/// This wraps the two controllers the demo already had ([ChatController] and
/// [VoiceController]) rather than reimplementing them.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../chat/chat_controller.dart';
import '../chat/data/agent_service.dart';
import '../chat/model/chat_message.dart';
import '../voice/speech_service.dart';
import '../voice/voice_controller.dart';
import 'conversation.dart';

class DemoConversation extends ChangeNotifier implements Conversation {
  DemoConversation({AgentService? agent, SpeechService? speech, String? opener})
      : _chat = ChatController(service: agent ?? ScriptedAgent(), opener: opener),
        _voice = VoiceController(service: speech ?? SimulatedSpeechService()) {
    _chat.addListener(_onChatChanged);
    _voice.addListener(notifyListeners);
  }

  final ChatController _chat;
  final VoiceController _voice;

  /// How many messages the dock has already reacted to, so one arriving reply
  /// is spoken once and not again on every rebuild.
  int _spokenUpTo = 0;

  @override
  List<ChatMessage> get messages => _chat.messages;

  @override
  bool get isTyping => _chat.isTyping;

  @override
  VoiceState get voiceState => _voice.state;

  @override
  ValueListenable<double> get level => _voice.level;

  @override
  String get partial => _voice.partial;

  @override
  ConversationStatus get status => ConversationStatus.ready;

  @override
  String? get statusMessage => null;

  @override
  bool get canType => true;

  @override
  Future<void> start() async {}

  /// Keeps the dock in step with the thread: thinking while the reply is being
  /// written, speaking once it lands.
  void _onChatChanged() {
    if (_chat.isTyping) {
      _voice.think();
    } else {
      final List<ChatMessage> all = _chat.messages;
      if (all.length > _spokenUpTo) {
        _spokenUpTo = all.length;
        final ChatMessage last = all.last;
        if (!last.isUser) {
          _voice.speak(last.text);
        } else {
          _voice.settle();
        }
      } else {
        _voice.settle();
      }
    }
    notifyListeners();
  }

  /// One button, four meanings — whatever is happening, tapping the mic does
  /// the obvious next thing.
  @override
  Future<void> onMicTap() async {
    switch (_voice.state) {
      case VoiceState.idle:
        await _voice.startListening();
      case VoiceState.listening:
        // Speech-to-text is the input method: what comes back is just a
        // message, indistinguishable from a typed one.
        final String? said = await _voice.stopListening();
        if (said == null) return;
        await _chat.send(said);
      case VoiceState.speaking:
        _voice.stopSpeaking();
      case VoiceState.thinking:
        break; // let it finish
    }
  }

  @override
  Future<void> send(String text) => _chat.send(text);

  @override
  Future<void> end() async {}

  @override
  void dispose() {
    _chat.removeListener(_onChatChanged);
    _voice.removeListener(notifyListeners);
    _chat.dispose();
    _voice.dispose();
    super.dispose();
  }
}
