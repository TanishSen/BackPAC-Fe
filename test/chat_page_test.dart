import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backPAC/features/voice/widgets/mic_button.dart';
import 'package:backPAC/features/chat/chat_page.dart';
import 'package:backPAC/features/chat/data/agent_service.dart';
import 'package:backPAC/features/conversation/conversation.dart';
import 'package:backPAC/features/conversation/demo_conversation.dart';
import 'package:backPAC/features/voice/voice_controller.dart' show VoiceState;
import 'package:flutter/foundation.dart';
import 'package:backPAC/features/chat/model/chat_message.dart';
import 'package:backPAC/features/chat/widgets/typing_indicator.dart';

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
  // These tests are about the screen, so they drive the offline conversation
  // with a fake agent — no backend, no LiveKit, no network.
  await tester.pumpWidget(MaterialApp(
    home: ChatPage(
      title: 'Goa',
      opener: opener,
      conversation: DemoConversation(
        agent: agent ?? _FastAgent(),
        opener: opener,
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

/// A conversation parked in one state, so the screen can be checked against it.
class _StuckConversation extends ChangeNotifier implements Conversation {
  /// Null means "not on the server yet", which is what the scripted demo and
  /// a still-connecting call both are. A value means the conversation exists
  /// and can be saved or deleted.
  @override
  final String? sessionId;

  _StuckConversation(this.status, this.statusMessage,
      {this.canType = false, this.sessionId});

  @override
  final ConversationStatus status;
  @override
  final String? statusMessage;

  @override
  List<ChatMessage> get messages => const <ChatMessage>[];
  @override
  bool get isTyping => false;
  @override
  VoiceState get voiceState => VoiceState.thinking;
  @override
  ValueListenable<double> get level => ValueNotifier<double>(0);
  @override
  String get partial => '';
  @override
  final bool canType;
  @override
  Future<void> start() async {}
  @override
  Future<void> onMicTap() async {}
  @override
  Future<void> send(String text) async {}
  @override
  Future<void> end() async {}
}

void main() {

  testWidgets('while connecting the screen says so, and does not invite talking',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: ChatPage(
        title: 'Goa',
        conversation: _StuckConversation(
          ConversationStatus.connecting,
          'Waiting for your assistant…',
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Waiting for your assistant…'), findsWidgets);
    // The assistant has not arrived, so the screen must not be asking the user
    // to start talking to it.
    expect(find.text('Where are we going?'), findsNothing);
    expect(find.text('Listening…'), findsNothing);
    expect(find.text('Thinking…'), findsNothing,
        reason: 'the dock caption should be the connecting message, not this');
  });

  testWidgets('a blocked microphone is explained, and the call stays usable',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: ChatPage(
        title: 'Goa',
        conversation: _StuckConversation(
          ConversationStatus.ready,
          'Microphone blocked. Allow it in Settings, then tap the mic — '
          'or type instead.',
          canType: true,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    // Says what to do about it, rather than blaming the network.
    expect(find.textContaining('Microphone blocked'), findsOneWidget);
    // And the call is still a call: the keyboard is still offered.
    expect(find.byIcon(Icons.keyboard_alt_outlined), findsOneWidget);
  });

  testWidgets('a failed connection explains itself', (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: ChatPage(
        title: 'Goa',
        conversation: _StuckConversation(
          ConversationStatus.failed,
          "Your assistant didn't pick up. Try again in a moment.",
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining("didn't pick up"), findsOneWidget);
  });

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

  testWidgets('deleting asks first, and a refusal changes nothing',
      (WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: ChatPage(
        title: 'Goa',
        conversation: _StuckConversation(
          ConversationStatus.ready,
          null,
          sessionId: 'a-real-session',
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump(const Duration(milliseconds: 300));

    // It says what is actually lost, rather than "Are you sure?".
    expect(find.textContaining('cannot be undone'), findsOneWidget);

    await tester.tap(find.text('Keep it'));
    await tester.pump(const Duration(milliseconds: 300));

    // Still here.
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsNothing);
  });

  // The scripted demo has no backend behind it, so `sessionId` is null — the
  // same state a live call is in before it has connected. Both header buttons
  // have to say so rather than appear to work. One test each: they share a
  // snackbar, and a second message replaces the first.
  testWidgets('saving is refused until the conversation exists',
      (WidgetTester tester) async {
    await pumpChat(tester);

    await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('nothing to save'), findsOneWidget);
    // Still unsaved — the icon did not change behind the message.
    expect(find.byIcon(Icons.bookmark_rounded), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('deleting is refused until the conversation exists',
      (WidgetTester tester) async {
    await pumpChat(tester);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('nothing to delete'), findsOneWidget);
    // Straight to an explanation — no confirmation for something that cannot
    // happen.
    expect(find.textContaining('cannot be undone'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the delete button sits away from the back button',
      (WidgetTester tester) async {
    await pumpChat(tester);

    final double back =
        tester.getCenter(find.byIcon(Icons.arrow_back_rounded)).dx;
    final double del =
        tester.getCenter(find.byIcon(Icons.delete_outline_rounded)).dx;
    final double save =
        tester.getCenter(find.byIcon(Icons.bookmark_border_rounded)).dx;

    // Back on the left, then save, then delete furthest away: the one control
    // here that cannot be undone should not be where a thumb reaching for
    // "back" lands.
    expect(back, lessThan(save));
    expect(save, lessThan(del));
  });
}
