import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backPAC/features/chat/chat_page.dart';
import 'package:backPAC/features/home/home_page.dart';
import 'package:backPAC/features/home/widgets/history_section.dart';
import 'package:backPAC/features/home/widgets/travel_modes.dart';
import 'package:backPAC/features/home/widgets/trip_ideas_row.dart';

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> settleEntrances(WidgetTester tester) async {
  // The sections fade in on staggered timers.
  await tester.pump(const Duration(milliseconds: 900));
}

void main() {
  testWidgets('home shows the greeting, every travel mode and the trip ideas',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await settleEntrances(tester);

    expect(find.text('Hi, Jasmin'), findsOneWidget);
    expect(find.text('24 requests left'), findsOneWidget);
    expect(find.byType(TravelModes), findsOneWidget);
    expect(find.text('Trains'), findsWidgets);
    // The row is horizontal and lazily built, so the last card starts offscreen.
    await tester.drag(find.byType(TravelModes), const Offset(-260, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Hotels'), findsWidgets);
    expect(find.byType(TripIdeasRow), findsOneWidget);
    expect(find.text('Goa'), findsWidgets);
    expect(find.text('History'), findsOneWidget);
  });

  testWidgets('tapping a travel mode opens the chat already asking for it',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await settleEntrances(tester);

    await tester.tap(find.text('Flights').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.text('Find me flights for my next trip'), findsOneWidget);

    // Let the assistant answer, so no timer is left running at teardown.
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('When are you thinking of going'), findsOneWidget);
  });

  testWidgets('history filters down to one mode', (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await settleEntrances(tester);

    await tester.scrollUntilVisible(
      find.text('Trains to Varanasi'),
      240,
      scrollable: find.byType(Scrollable).first,
      duration: const Duration(milliseconds: 16),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Trains to Varanasi'), findsOneWidget);
    expect(find.text('Hotel in Jaipur'), findsOneWidget);

    // The filter chips scroll horizontally; the last one starts offscreen.
    await tester.drag(
      find.descendant(
        of: find.byType(HistorySection),
        matching: find.text('All'),
      ),
      const Offset(-220, 0),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.descendant(
      of: find.byType(HistorySection),
      matching: find.text('Hotels'),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Hotel in Jaipur'), findsOneWidget);
    expect(find.text('Trains to Varanasi'), findsNothing);
  });
}
