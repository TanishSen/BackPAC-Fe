import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backPAC/app/app.dart';
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

  testWidgets('the assistant greets as soon as the page opens',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const backPACApp());

    // Nothing to say yet, so there is no bubble at all — not an invisible one.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SpeechBubble), findsNothing);

    // With no backend in a widget test the spoken greeting never arrives, so
    // the silent fallback greets instead. Either way it opens with a hello.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SpeechBubble), findsOneWidget);
    expect(find.text('Hello!'), findsOneWidget);

    // And the caption goes away with the voice rather than sitting there.
    // Stepped, not one big jump: the fade-out needs frames to run before the
    // bubble is actually taken out of the tree.
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(SpeechBubble), findsNothing,
        reason: 'the bubble belongs to the line, not to the screen');
  });

  testWidgets('poking the orb answers once the poking stops',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const backPACApp());
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Hello!'), findsOneWidget);

    await tester.tap(find.byType(RezolveOrb));
    await tester.pump();

    // The tap cuts the greeting off and the orb waits to see whether more taps
    // are coming; once they stop, it has something to say about it.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byType(SpeechBubble), findsOneWidget);
    expect(find.text('Hello!'), findsNothing,
        reason: 'the greeting should have given way to a reply');
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4)); // let its timers finish
  });

  testWidgets('a flurry of pokes gets one answer, not one per poke',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const backPACApp());
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));

    // Drum on it faster than the reply delay.
    for (int i = 0; i < 6; i++) {
      await tester.tap(find.byType(RezolveOrb));
      await tester.pump(const Duration(milliseconds: 150));
    }

    // Stop, and it gets its one word in.
    await tester.pump(const Duration(milliseconds: 1200));
    final Iterable<String> captions = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(SpeechBubble),
          matching: find.byType(Text),
        ))
        .map((Text t) => t.data ?? '')
        .where((String t) => t.isNotEmpty);
    expect(captions.length, 1, reason: 'exactly one line, however many pokes');

    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a poke reply does not follow you to the home screen',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const backPACApp());
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));

    // Poke it, then leave before the 650ms reply has landed.
    await tester.tap(find.byType(RezolveOrb));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text("Let's Start"));
    // The orb never stops animating, so nothing here ever settles: step the
    // route transition by hand instead.
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The reply is due about now. It must not arrive on top of another screen.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byType(SpeechBubble, skipOffstage: false), findsNothing,
        reason: 'it answered a poke you made on the screen before');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a greeting that was still on its way is dropped, not spoken',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const backPACApp());

    // Leave immediately — before the 700ms greeting has had its turn.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text("Let's Start"));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(SpeechBubble, skipOffstage: false), findsNothing,
        reason: 'the hello landed after you had already gone');
    expect(tester.takeException(), isNull);
  });

  testWidgets('it goes quiet for good once you leave for the home screen',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const backPACApp());
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Hello!'), findsOneWidget);

    await tester.tap(find.text("Let's Start"));
    // The orb never stops animating, so nothing here ever settles: step the
    // route transition by hand instead.
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SpeechBubble, skipOffstage: false), findsNothing,
        reason: 'the greeting should not follow you onto the next screen');

    // Pushing does not dispose this page, so its idle countdown used to carry
    // on behind the home screen and nudge into an empty room. Sit through the
    // whole escalation — 3.5s, 7s, 12s, 20s, 30s — and it must stay silent.
    // Stepped rather than one long jump so every timer in between gets to run.
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(SpeechBubble, skipOffstage: false), findsNothing,
          reason: 'the orb spoke from under the home screen');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('and speaks again when you come back to it',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const backPACApp());
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));

    final NavigatorState nav = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    await tester.tap(find.text("Let's Start"));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    nav.pop();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Silencing it on the way out must not silence it for ever: back on top,
    // the idle nudges start over.
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(SpeechBubble), findsOneWidget,
        reason: 'it should pipe up again once it is the screen you are on');
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a replaced route does not wake it up again',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(const backPACApp());
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));

    final NavigatorState nav =
        tester.state<NavigatorState>(find.byType(Navigator).first);

    // Exactly what signing in does: push a screen, then replace it with
    // another. The pushed route's future completes on that replacement, and
    // waking on it is what had the orb chatting from under the home screen
    // for the rest of the session.
    await tester.tap(find.text("Let's Start"));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    nav.pushReplacement(MaterialPageRoute<void>(
      builder: (BuildContext _) => const Scaffold(body: Text('replacement')),
    ));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Sit through the whole idle escalation with the replacement on top.
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(SpeechBubble, skipOffstage: false), findsNothing,
          reason: 'it woke up when the route above it was replaced');
    }
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
