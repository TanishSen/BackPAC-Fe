import 'package:backPAC/features/chat/model/trip_card.dart';
import 'package:backPAC/features/chat/widgets/trip_card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// How a card copes with providers that answer with different detail.
///
/// The flight fare calendar gives a departure time, a price and a transfer
/// count — and no arrival time or duration. A card that assumes the full set
/// renders nonsense, which is how "0m" reached the screen.
void main() {
  Future<void> pumpCard(WidgetTester tester, Map<String, dynamic> data) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TripCardView(
          card: TripCard(
            kind: TripCardKind.flights,
            rows: <Map<String, dynamic>>[data],
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a flight with no arrival time still shows when it leaves',
      (WidgetTester tester) async {
    await pumpCard(tester, <String, dynamic>{
      'name': 'SG-612',
      'provider': 'SpiceJet',
      'depart': '2026-12-25T19:00:00+05:30',
      'arrive': '',
      'durationMinutes': 0,
      'stops': 1,
      'priceInr': 24125,
      'priceIsApproximate': true,
    });

    // 19:00 IST, not 13:30 UTC. Parsing the offset away made every Indian
    // departure five and a half hours early.
    expect(find.textContaining('19:00'), findsOneWidget);
    expect(find.textContaining('13:30'), findsNothing);
    // Not "0m": zero means the provider did not say, not that the flight is
    // instantaneous.
    expect(find.textContaining('0m'), findsNothing);
    expect(find.textContaining('1 stop'), findsOneWidget);
  });

  testWidgets('an estimated price is marked as one', (WidgetTester tester) async {
    await pumpCard(tester, <String, dynamic>{
      'name': 'SG-612',
      'provider': 'SpiceJet',
      'depart': '2026-12-25T19:00:00+05:30',
      'arrive': '',
      'durationMinutes': 0,
      'stops': 0,
      'priceInr': 24125,
      'priceIsApproximate': true,
    });
    expect(find.textContaining('~'), findsOneWidget);
  });

  testWidgets('a live price carries no tilde', (WidgetTester tester) async {
    await pumpCard(tester, <String, dynamic>{
      'name': 'Shiv Ganga',
      'provider': 'IRCTC',
      'depart': '2026-12-25T19:55:00+05:30',
      'arrive': '2026-12-26T07:40:00+05:30',
      'durationMinutes': 705,
      'stops': 0,
      'priceInr': 1450,
      'priceIsApproximate': false,
    });
    expect(find.textContaining('~'), findsNothing);
    expect(find.textContaining('19:55 → 07:40'), findsOneWidget);
    expect(find.textContaining('11h 45m'), findsOneWidget);
    expect(find.textContaining('non-stop'), findsOneWidget);
  });
}
