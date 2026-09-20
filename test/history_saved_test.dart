import 'package:backPAC/data/trip_data.dart';
import 'package:backPAC/features/home/home_page.dart';
import 'package:backPAC/features/home/widgets/history_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A chip inside the history section, not the travel-mode tile of the same
/// name higher up the page. `find.text('Hotels')` matches both, and tapping
/// the wrong one silently does nothing to the filter.
Finder historyChip(String label) => find.descendant(
      of: find.byType(HistorySection),
      matching: find.text(label),
    );

/// Saving a conversation, and finding it again.
void main() {
  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  const List<TripHistoryEntry> rows = <TripHistoryEntry>[
    TripHistoryEntry(
      id: '1',
      title: 'Goa in December',
      preview: 'Flights from Delhi',
      mode: TravelMode.flights,
      when: 'Yesterday',
      saved: true,
    ),
    TripHistoryEntry(
      id: '2',
      title: 'Trains to Varanasi',
      preview: 'Overnight, before 8am',
      mode: TravelMode.trains,
      when: '2 days ago',
    ),
    TripHistoryEntry(
      id: '3',
      title: 'Hotel in Jaipur',
      preview: 'Near the old city',
      mode: TravelMode.hotels,
      when: 'Last week',
      saved: true,
    ),
  ];

  Future<void> pumpHome(WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(name: 'Tanish', loadHistory: () async => rows),
    ));
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.scrollUntilVisible(
      historyChip('Saved'),
      240,
      // The page, not the horizontal chip row beside it.
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('the Saved chip narrows the list to bookmarked conversations',
      (WidgetTester tester) async {
    await pumpHome(tester);

    expect(find.text('Trains to Varanasi'), findsOneWidget);

    await tester.tap(historyChip('Saved'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Goa in December'), findsOneWidget);
    expect(find.text('Hotel in Jaipur'), findsOneWidget);
    expect(find.text('Trains to Varanasi'), findsNothing,
        reason: 'it was never saved');
  });

  testWidgets('saved and travel mode narrow independently',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(
        name: 'Tanish',
        loadHistory: () async => const <TripHistoryEntry>[
          // Two saved conversations of different kinds, so narrowing by mode
          // on top of Saved has something to actually exclude.
          TripHistoryEntry(
            id: '1',
            title: 'Goa in December',
            preview: 'Flights from Delhi',
            mode: TravelMode.flights,
            when: 'Yesterday',
            saved: true,
          ),
          TripHistoryEntry(
            id: '2',
            title: 'Trains to Varanasi',
            preview: 'Overnight, before 8am',
            mode: TravelMode.trains,
            when: '2 days ago',
            saved: true,
          ),
        ],
      ),
    ));
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.scrollUntilVisible(
      historyChip('Saved'),
      240,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(historyChip('Saved'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Goa in December'), findsOneWidget);
    expect(find.text('Trains to Varanasi'), findsOneWidget);

    // "Saved trains" is a sensible thing to want, which is why saving is its
    // own axis rather than another travel-mode chip.
    await tester.tap(historyChip('Trains'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Trains to Varanasi'), findsOneWidget);
    expect(find.text('Goa in December'), findsNothing,
        reason: 'saved, but not a train');
  });

  testWidgets('an empty Saved list says how to fill it',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(
        name: 'Tanish',
        loadHistory: () async => const <TripHistoryEntry>[
          TripHistoryEntry(
            id: '2',
            title: 'Trains to Varanasi',
            preview: 'Overnight',
            mode: TravelMode.trains,
            when: 'Yesterday',
          ),
        ],
      ),
    ));
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.scrollUntilVisible(
      historyChip('Saved'),
      240,
      // The page, not the horizontal chip row beside it.
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(historyChip('Saved'));
    await tester.pump(const Duration(milliseconds: 300));

    // Not "nothing here yet", which would read as a fault rather than an
    // instruction.
    expect(find.textContaining('Tap the bookmark'), findsOneWidget);
  });

  testWidgets('a saved conversation is marked in the full list',
      (WidgetTester tester) async {
    await pumpHome(tester);
    expect(
      find.descendant(
        of: find.byType(HistorySection),
        matching: find.byIcon(Icons.bookmark_rounded),
      ),
      // Two saved rows, plus the chip's own glyph.
      findsNWidgets(3),
    );
  });
}
