/// The seam between the chat screen and whatever is actually talking.
///
/// [ChatPage] renders a `Conversation` and knows nothing else — not LiveKit,
/// not the backend, not the scripted demo. Two implementations exist:
///
///   - [LiveConversation] — a real voice call with the agent.
///   - [DemoConversation]  — the offline scripted demo, used when live voice is
///     switched off and as the fallback when a call cannot be started.
///
/// Both are `ChangeNotifier`s: the page listens once and rebuilds. Loudness is
/// deliberately *not* part of that — it changes ~16 times a second and lives on
/// its own [ValueListenable] so it repaints the orb without rebuilding the page.
library;

import 'package:flutter/foundation.dart';

import '../chat/model/chat_message.dart';
import '../voice/voice_controller.dart' show VoiceState;

/// How the conversation is doing, as far as the user needs to know.
enum ConversationStatus {
  /// Ready, nothing happening.
  idle,

  /// Setting up (starting a session, joining the room).
  connecting,

  /// Ready to talk.
  ready,

  /// Over — the agent hung up or the network went.
  ended,

  /// Failed. [Conversation.statusMessage] says what to tell the user.
  failed,
}

abstract class Conversation extends ChangeNotifier {
  /// The thread, oldest first.
  List<ChatMessage> get messages;

  /// The assistant is working but has not produced words yet.
  bool get isTyping;

  /// What the mic dock should show.
  VoiceState get voiceState;

  /// Loudness, 0..1.
  ValueListenable<double> get level;

  /// Words heard so far this turn, shown under the mic while listening.
  String get partial;

  ConversationStatus get status;

  /// A short line to show the user when something needs explaining
  /// (connecting, or why it failed). Null when there is nothing to say.
  String? get statusMessage;

  /// True when typing is possible. Always true here; it exists so a future
  /// transport that genuinely cannot accept text can say so.
  bool get canType => true;

  /// Open the conversation. Safe to call once, from initState.
  Future<void> start();

  /// The mic was tapped. Each implementation decides what that means — push to
  /// talk in the demo, mute/unmute on a live call.
  Future<void> onMicTap();

  /// Send typed text.
  Future<void> send(String text);

  /// Close it down. `dispose` also does this; this is for ending early.
  Future<void> end();
}
