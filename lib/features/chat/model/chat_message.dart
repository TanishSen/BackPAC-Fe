import 'package:flutter/foundation.dart';

enum ChatAuthor { user, assistant }

/// What a message carries.
///
/// Spoken turns are transcribed before they get here — speech-to-text is the
/// input method, not a kind of message — so everything in the thread is text.
/// A set of [replies] renders as tappable chips under the bubble.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.author,
    required this.text,
    required this.at,
    this.replies = const <String>[],
  });

  final String id;
  final ChatAuthor author;
  final String text;
  final DateTime at;

  /// Suggested answers offered under an assistant message.
  final List<String> replies;

  bool get isUser => author == ChatAuthor.user;
}

