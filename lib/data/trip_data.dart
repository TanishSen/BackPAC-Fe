import 'package:flutter/material.dart';

import '../app/app_theme.dart';

/// How someone wants to travel. Drives the cards on the home screen and the
/// opening line of the conversation when one is tapped.
enum TravelMode { trains, flights, bus, hotels }

extension TravelModeInfo on TravelMode {
  String get label => switch (this) {
        TravelMode.trains => 'Trains',
        TravelMode.flights => 'Flights',
        TravelMode.bus => 'Bus',
        TravelMode.hotels => 'Hotels',
      };

  IconData get icon => switch (this) {
        TravelMode.trains => Icons.train_rounded,
        TravelMode.flights => Icons.flight_takeoff_rounded,
        TravelMode.bus => Icons.directions_bus_filled_rounded,
        TravelMode.hotels => Icons.bed_rounded,
      };

  /// Tile tint. Indigo for the two rail/air modes, warm for road and stays, so
  /// the row reads as two pairs rather than four unrelated colours.
  Color get tint => switch (this) {
        TravelMode.trains => AppColors.brand,
        TravelMode.flights => const Color(0xFF7C6BF5),
        TravelMode.bus => const Color(0xFFE79B63),
        TravelMode.hotels => const Color(0xFFDE7EA8),
      };

  /// What the assistant hears when this card is tapped.
  String get prompt => switch (this) {
        TravelMode.trains => 'Find me trains for my next trip',
        TravelMode.flights => 'Find me flights for my next trip',
        TravelMode.bus => 'Find me a bus for my next trip',
        TravelMode.hotels => 'Find me a place to stay',
      };
}

/// A ready-made trip the user can start a conversation from.
@immutable
class TripIdea {
  const TripIdea({
    required this.title,
    required this.place,
    required this.nights,
    required this.fromPrice,
    required this.tag,
    required this.colors,
  });

  final String title;
  final String place;
  final int nights;
  final int fromPrice; // whole rupees
  final String tag;

  /// Two-stop gradient for the card's cover.
  final List<Color> colors;

  String get subtitle => '$nights nights · from ₹${_grouped(fromPrice)}';

  /// 12400 -> 12,400. Indian grouping (12,400 / 1,24,000) would be more correct
  /// for these prices; plain thousands reads fine at this size and avoids a
  /// dependency on intl for one label.
  static String _grouped(int value) {
    final String digits = value.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
  String get prompt => 'Plan my $nights-night trip to $place';
}

const List<TripIdea> kTripIdeas = <TripIdea>[
  TripIdea(
    title: 'Beaches and long lunches',
    place: 'Goa',
    nights: 3,
    fromPrice: 12400,
    tag: 'Popular',
    colors: <Color>[Color(0xFFFFA36B), Color(0xFFEF6E8C)],
  ),
  TripIdea(
    title: 'Forts, markets, palaces',
    place: 'Jaipur',
    nights: 2,
    fromPrice: 8200,
    tag: 'Heritage',
    colors: <Color>[Color(0xFF8E7BF0), Color(0xFF6A68DF)],
  ),
  TripIdea(
    title: 'Snow, pines and slow mornings',
    place: 'Manali',
    nights: 4,
    fromPrice: 15600,
    tag: 'Mountains',
    colors: <Color>[Color(0xFF64B7E8), Color(0xFF6A68DF)],
  ),
  TripIdea(
    title: 'Backwaters and houseboats',
    place: 'Alleppey',
    nights: 3,
    fromPrice: 13900,
    tag: 'Calm',
    colors: <Color>[Color(0xFF5FC3A6), Color(0xFF3D8FB0)],
  ),
];

/// A past conversation, as it appears under History.
///
/// A view model, not a wire type: the API's shape lives in
/// `features/history/data/history_client.dart` and is mapped into this. That
/// keeps date formatting and "what if it has no title" out of the widgets, and
/// lets the tile stay a dumb thing that draws four strings.
@immutable
class TripHistoryEntry {
  const TripHistoryEntry({
    required this.title,
    required this.preview,
    required this.mode,
    required this.when,
    this.id,
    this.saved = false,
  });

  final String title;
  final String preview;

  /// Null when the conversation never produced a result, so there is nothing
  /// honest to put an icon on. The tile draws a neutral one.
  final TravelMode? mode;
  final String when;

  /// The backend session id. Null for the sample entries below, which are not
  /// real conversations and cannot be resumed.
  final String? id;

  /// Bookmarked from the chat screen's save button.
  final bool saved;
}

/// "Just now", "Yesterday", "3 days ago" — a timestamp as someone would say it.
///
/// Deliberately coarse. Nobody scanning a list of past conversations wants
/// "14:32 on 18 September"; they want to know whether it was this morning or
/// a while back. Anything older than a month gets an actual date, because by
/// then "seven weeks ago" has stopped meaning anything.
String humanWhen(DateTime when, {DateTime? now}) {
  final DateTime ref = now ?? DateTime.now();
  final Duration ago = ref.difference(when);

  if (ago.inSeconds < 60) return 'Just now';
  if (ago.inMinutes < 60) {
    final int m = ago.inMinutes;
    return m == 1 ? 'A minute ago' : '$m minutes ago';
  }

  // The calendar day is decided before the hour count, not after.
  //
  // Doing it the other way round — any gap under 24 hours reported in hours —
  // means something said at 11pm is still "16 hours ago" at 3pm the next
  // afternoon, which is true and useless: the reader has slept since, and what
  // they want to know is that it was yesterday. Hours are only the right unit
  // within the day you are still in.
  final DateTime a = DateTime(when.year, when.month, when.day);
  final DateTime b = DateTime(ref.year, ref.month, ref.day);
  final int days = b.difference(a).inDays;

  if (days <= 0) {
    final int h = ago.inHours;
    return h == 1 ? 'An hour ago' : '$h hours ago';
  }
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  if (days < 14) return 'Last week';
  if (days < 31) return '${days ~/ 7} weeks ago';

  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final String date = '${when.day} ${months[when.month - 1]}';
  return when.year == ref.year ? date : '$date ${when.year}';
}

/// Sample conversations.
///
/// No longer what the app shows — the home screen loads the real thing from
/// the API. Kept as fixtures for the widget tests and for a demo with no
/// backend running; note that none of them carry an [TripHistoryEntry.id], so
/// tapping one starts a new conversation rather than resuming anything.
const List<TripHistoryEntry> kHistory = <TripHistoryEntry>[
  TripHistoryEntry(
    title: 'Hotel in Jaipur',
    preview: "I'm looking for a budget hotel near the old city for the weekend…",
    mode: TravelMode.hotels,
    when: 'Yesterday',
  ),
  TripHistoryEntry(
    title: 'Trains to Varanasi',
    preview: 'Overnight, arriving before 8am, sleeper or 3AC is fine…',
    mode: TravelMode.trains,
    when: '2 days ago',
  ),
  TripHistoryEntry(
    title: 'Goa in December',
    preview: 'Three nights, north Goa, somewhere walkable to the beach…',
    mode: TravelMode.flights,
    when: 'Last week',
  ),
  TripHistoryEntry(
    title: 'Bus to Rishikesh',
    preview: 'Leaving Friday evening from Delhi, back Sunday night…',
    mode: TravelMode.bus,
    when: 'Last week',
  ),
];
