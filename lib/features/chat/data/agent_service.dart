import 'dart:math' as math;

import '../model/chat_message.dart';

/// What the assistant sends back.
class AgentReply {
  const AgentReply({required this.text, this.replies = const <String>[]});

  final String text;
  final List<String> replies;
}

/// The seam between the UI and whatever answers the user.
///
/// The app ships a [ScriptedAgent] so the whole flow is demonstrable with no
/// backend. Swapping in a real one is a single implementation of this
/// interface — nothing in the widgets knows the difference.
abstract class AgentService {
  /// How long the UI should show the typing indicator before the reply lands.
  /// The wait belongs to the caller, not here — a controller can cancel a
  /// timer it owns, but nobody can cancel a Future that is already sleeping.
  Duration get thinkingTime;

  Future<AgentReply> respondTo(String prompt, List<ChatMessage> history);
}

/// A canned trip-planning conversation. It follows the shape a real planner
/// takes — dates, travellers, budget, then an itinerary — so the demo holds
/// together however the user replies.
class ScriptedAgent implements AgentService {
  ScriptedAgent({math.Random? random}) : _rng = random ?? math.Random();

  final math.Random _rng;
  int _turn = 0;

  @override
  Duration get thinkingTime =>
      Duration(milliseconds: 900 + _rng.nextInt(700));

  static const List<AgentReply> _script = <AgentReply>[
    AgentReply(
      text: 'Happy to help. When are you thinking of going, and how many of '
          'you are travelling?',
      replies: <String>['This weekend', 'Next month', 'Just me'],
    ),
    AgentReply(
      text: 'Got it. What matters most — keeping it cheap, keeping it short, '
          'or somewhere you can properly relax?',
      replies: <String>['Keep it cheap', 'Somewhere relaxing', 'Surprise me'],
    ),
    AgentReply(
      text: 'Here is a shape for the trip:\n\n'
          '• Fri evening — overnight train, arrives 7:10am\n'
          '• Sat — old city on foot, rooftop lunch, fort at sunset\n'
          '• Sun — market crawl, late afternoon flight back\n\n'
          'Stays start around ₹2,900 a night near the centre. Want me to hold '
          'one of them?',
      replies: <String>['Hold the hotel', 'Show cheaper stays', 'Change the dates'],
    ),
    AgentReply(
      text: 'Done — held for 24 hours, nothing charged yet. I can add the '
          'train tickets to the same booking if that helps.',
      replies: <String>['Add the trains', 'Not yet, thanks'],
    ),
    AgentReply(
      text: 'All set. I have put the whole plan in your trips — say the word '
          'and I will move anything around.',
      replies: <String>['Thanks!'],
    ),
  ];

  @override
  Future<AgentReply> respondTo(String prompt, List<ChatMessage> history) async {
    final AgentReply reply = _script[math.min(_turn, _script.length - 1)];
    _turn++;
    return reply;
  }
}
