import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backPAC/features/chat/chat_page.dart';
import 'package:backPAC/features/chat/data/agent_service.dart';
import 'package:backPAC/features/chat/model/chat_message.dart';
import 'package:backPAC/features/chat/widgets/typing_indicator.dart';
import 'package:backPAC/features/voice/widgets/mic_button.dart';

/// Pumps in small steps. One big pump renders a single frame, which leaves
/// AnimatedSwitcher still showing the child it is transitioning away from.
Future<void> pumpFor(WidgetTester tester, int ms, {int step = 120}) async {
  for (int t = 0; t < ms; t += step) {
    await tester.pump(Duration(milliseconds: step));
  }
}

/// Answers instantly and always the same, so assertions are about the screen
/// rather than about the script.
class _FastAgent implements AgentService {
  @override
  Duration get thinkingTime => const Duration(milliseconds: 40);

  @override
  Future<AgentReply> respondTo(String prompt, List<ChatMessage> history) async =>
      const AgentReply(
        text: 'Sure — which dates suit you?',
        replies: <String>['This weekend', 'Next month'],
      );
}

/// Same, but slow enough that the typing indicator is observable.
class _SlowAgent extends _FastAgent {
  @override
  Duration get thinkingTime => const Duration(milliseconds: 600);
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> pumpChat(
  WidgetTester tester, {
  String? opener,
  AgentService? agent,
}) async {
  usePhone(tester);
  await tester.pumpWidget(MaterialApp(
    home: ChatPage(
      title: 'Goa',
      opener: opener,
      agent: agent ?? _FastAgent(),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('an opener starts the conversation and gets answered',
      (WidgetTester tester) async {
    await pumpChat(tester,
        opener: 'Plan my 3-night trip to Goa', agent: _SlowAgent());

    expect(find.text('Plan my 3-night trip to Goa'), findsOneWidget);
    expect(find.byType(TypingIndicator), findsOneWidget,
        reason: 'the assistant should visibly be thinking first');

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(TypingIndicator), findsNothing);
    expect(find.text('Sure — which dates suit you?'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // let it finish "speaking"
  });

  testWidgets('the keyboard is one tap away and sends',
      (WidgetTester tester) async {
    await pumpChat(tester);

    expect(find.byType(TextField), findsNothing, reason: 'voice first');
    await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Somewhere warm in December');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(find.text('Somewhere warm in December'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sure — which dates suit you?'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a suggested reply sends itself', (WidgetTester tester) async {
    await pumpChat(tester, opener: 'Plan a trip');
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('This weekend'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Once as the chip that was tapped, once as the message it sent.
    expect(find.text('This weekend'), findsWidgets);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('speaking transcribes, sends, and is answered',
      (WidgetTester tester) async {
    await pumpChat(tester);

    await tester.tap(find.byType(MicButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Listening…'), findsOneWidget);

    // Words arrive one at a time from the recogniser.
    await pumpFor(tester, 1600);
    expect(find.text('Listening…'), findsNothing,
        reason: 'the caption should have become the live transcript');

    await tester.tap(find.byType(MicButton));
    await tester.pump();
    await pumpFor(tester, 600);

    // Speech-to-text: what was said arrives as an ordinary text message.
    expect(find.byType(TextField), findsNothing);
    final Iterable<String> texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data ?? '');
    expect(
      texts.any((String t) => t.split(' ').length >= 4 && t != 'Sure — which dates suit you?'),
      isTrue,
      reason: 'the transcript should be in the thread as a message',
    );
    expect(find.text('Sure — which dates suit you?'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('tapping the mic while the assistant talks interrupts it',
      (WidgetTester tester) async {
    await pumpChat(tester, opener: 'Plan a trip');
    await pumpFor(tester, 700);
    expect(find.text('Tap to interrupt'), findsOneWidget,
        reason: 'the assistant should be speaking its reply');

    await tester.tap(find.byType(MicButton));
    await pumpFor(tester, 600);

    expect(find.text('Tap to interrupt'), findsNothing);
  });
}
