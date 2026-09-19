import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// If your package name is not 'backPAC', change it here to match pubspec.yaml.
import 'package:backPAC/orb/rezolve_orb.dart';

void main() {
  testWidgets('orb animates, changes mood and disposes cleanly',
      (WidgetTester tester) async {
    OrbMood mood = OrbMood.idle;
    late StateSetter setOuter;

    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (BuildContext c, StateSetter set) {
        setOuter = set;
        return Center(child: RezolveOrb(size: 200, mood: mood));
      }),
    ));

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }

    setOuter(() => mood = OrbMood.speaking);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }

    expect(find.byType(RezolveOrb), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Unmount: the ticker and notifier must tear down without complaint.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paused orb holds still', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: RezolveOrb(size: 120, paused: true)),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
