import 'package:flutter/foundation.dart';

import 'trip_card.dart';

enum ChatAuthor { user, assistant }

/// What a message carries.
///
/// Spoken turns are transcribed before they get here — speech-to-text is the
/// input method, not a kind of message — so everything in the thread is text.
/// A set of [replies] renders as tappable chips under the bubble, and a [card]
/// renders the rows behind what the assistant just said.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.author,
    required this.text,
    required this.at,
    this.replies = const <String>[],
    this.card,
  });

  final String id;
  final ChatAuthor author;
  final String text;
  final DateTime at;

  /// Suggested answers offered under an assistant message.
  final List<String> replies;

  /// Search results the assistant produced for this turn, if any. The voice
  /// summarises two or three; this shows the whole list.
  final TripCard? card;

  bool get isUser => author == ChatAuthor.user;

  /// A copy with different text — used while an assistant reply streams in
  /// word by word, and to attach a card to the turn it belongs to.
  ChatMessage copyWith({String? text, TripCard? card}) => ChatMessage(
        id: id,
        author: author,
        text: text ?? this.text,
        at: at,
        replies: replies,
        card: card ?? this.card,
      );
}
