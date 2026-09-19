import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/agent_service.dart';
import 'model/chat_message.dart';

/// Owns one conversation.
///
/// The widgets read this and nothing else, so replacing [ScriptedAgent] with a
/// real backend changes no UI code. Everything here is local and synchronous
/// apart from [AgentService.respondTo].
class ChatController extends ChangeNotifier {
  ChatController({required AgentService service, String? opener})
    : _agent = service {
    if (opener != null && opener.trim().isNotEmpty) {
      // The home screen hands us the line that started the conversation.
      _messages.add(_message(ChatAuthor.user, opener.trim()));
      _askAgent(opener.trim());
    }
  }

  final AgentService _agent;
  final List<ChatMessage> _messages = <ChatMessage>[];

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);

  bool _typing = false;
  bool get isTyping => _typing;

  bool _disposed = false;

  int _seq = 0;
  ChatMessage _message(
    ChatAuthor author,
    String text, {
    List<String> replies = const <String>[],
  }) => ChatMessage(
    id: 'm${_seq++}',
    author: author,
    text: text,
    at: DateTime.now(),
    replies: replies,
  );

  /// Send a message — typed, or transcribed from speech. By the time it gets
  /// here there is no difference between the two.
  Future<void> send(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || _typing) return;
    _messages.add(_message(ChatAuthor.user, trimmed));
    notifyListeners();
    await _askAgent(trimmed);
  }

  Timer? _thinking;

  Future<void> _askAgent(String prompt) async {
    _typing = true;
    notifyListeners();
    final AgentReply reply = await _agent.respondTo(prompt, messages);
    if (_disposed) return;

    // Hold the typing indicator for a beat so replies do not snap in — and
    // hold it in a timer this object owns, so closing the screen cancels it.
    _thinking?.cancel();
    _thinking = Timer(_agent.thinkingTime, () {
      if (_disposed) return;
      _typing = false;
      _messages.add(
        _message(ChatAuthor.assistant, reply.text, replies: reply.replies),
      );
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _thinking?.cancel();
    super.dispose();
  }
}
