/// A result card the agent produced — the rows behind what it just said.
///
/// The agent speaks two or three options aloud and sends the full list here at
/// the same time, so the screen can show detail the ear would lose (exact
/// times, prices, ratings) without the voice reading out a table.
///
/// Wire format, over the LiveKit data channel (see the agent's
/// CardDispatcherProcessor):
///   {"type":"agent-card","cardType":"search_trains","payload":[ {...}, ... ]}
library;

import 'package:flutter/foundation.dart';

/// What kind of thing the rows describe. Anything unrecognised renders as a
/// plain list rather than being dropped — a new agent tool should degrade, not
/// disappear.
enum TripCardKind { trains, flights, stays, other }

@immutable
class TripCard {
  const TripCard({required this.kind, required this.rows});

  final TripCardKind kind;
  final List<Map<String, dynamic>> rows;

  bool get isEmpty => rows.isEmpty;

  /// Build from a data-channel payload. Returns null if there is nothing worth
  /// showing, so callers can simply skip it.
  static TripCard? fromPayload(String cardType, dynamic payload) {
    if (payload is! List) return null;
    final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
      for (final dynamic row in payload)
        if (row is Map<String, dynamic> && !row.containsKey('error')) row,
    ];
    if (rows.isEmpty) return null;
    return TripCard(kind: _kindOf(cardType), rows: rows);
  }

  static TripCardKind _kindOf(String cardType) => switch (cardType) {
        'search_trains' => TripCardKind.trains,
        'search_flights' => TripCardKind.flights,
        'search_stays' => TripCardKind.stays,
        _ => TripCardKind.other,
      };

  String get title => switch (kind) {
        TripCardKind.trains => 'Trains',
        TripCardKind.flights => 'Flights',
        TripCardKind.stays => 'Places to stay',
        TripCardKind.other => 'Results',
      };
}
