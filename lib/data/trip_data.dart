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
@immutable
class TripHistoryEntry {
  const TripHistoryEntry({
    required this.title,
    required this.preview,
    required this.mode,
    required this.when,
  });

  final String title;
  final String preview;
  final TravelMode mode;
  final String when;
}

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
