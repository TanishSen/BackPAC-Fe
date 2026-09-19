import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backPAC/app/app.dart';
import 'package:backPAC/features/home/home_page.dart';
import 'package:backPAC/features/welcome/widgets/primary_button.dart';
import 'package:backPAC/features/welcome/widgets/speech_bubble.dart';
import 'package:backPAC/orb/rezolve_orb.dart';

/// The page is designed for a phone; the default 800x600 test surface would
/// push the CTA off-screen.
void usePhone(WidgetTester tester, {Size logical = const Size(390, 844)}) {
  tester.view.physicalSize = logical * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('welcome page shows the brand, headline, orb and CTA',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const backPACApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('backPAC.'), findsOneWidget);
    expect(find.textContaining('Smart Assistant'), findsOneWidget);
    expect(find.byType(RezolveOrb), findsOneWidget);
    expect(find.byType(PrimaryButton), findsOneWidget);
    expect(find.text("Let's Start"), findsOneWidget);
  });

  testWidgets('the assistant greets shortly after the page opens',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const backPACApp());

    // Before the greeting fires the bubble is mounted but fully transparent.
    await tester.pump(const Duration(milliseconds: 100));
    AnimatedOpacity fade = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byType(SpeechBubble),
        matching: find.byType(AnimatedOpacity),
      ).first,
    );
    expect(fade.opacity, 0);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));
    fade = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byType(SpeechBubble),
        matching: find.byType(AnimatedOpacity),
      ).first,
    );
    expect(fade.opacity, 1);
    expect(find.text('Hello!'), findsOneWidget);
  });

  testWidgets('Let\'s Start opens the next screen', (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const backPACApp());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('poking the orb makes it answer with a different line',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const backPACApp());
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Hello!'), findsOneWidget);

    await tester.tap(find.byType(RezolveOrb));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Hello!'), findsNothing);
    expect(find.byType(SpeechBubble), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout survives a small phone and large system text',
      (WidgetTester tester) async {
    usePhone(tester, logical: const Size(320, 568));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: const backPACApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}
