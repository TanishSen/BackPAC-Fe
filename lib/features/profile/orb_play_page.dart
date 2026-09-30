import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_config.dart';
import '../../app/app_theme.dart';
import '../../app/transitions.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../orb/rezolve_orb.dart';
import '../chat/chat_page.dart';
import '../welcome/data/greeting_client.dart';
import '../welcome/data/greeting_voice.dart';
import '../welcome/widgets/speech_bubble.dart';

/// "Play with COOKIE": the orb, with nothing to do but play.
///
/// Two games. Poke it and it answers in its own voice — the same lines the
/// welcome screen uses, fetched once and cached. Or ask it to pick a trip:
/// it spins, lands on somewhere, and one tap turns that into a conversation.
class OrbPlayPage extends StatefulWidget {
  const OrbPlayPage({super.key, this.greetings, this.random});

  /// Injected by tests, which have no backend to fetch lines from.
  final GreetingClient? greetings;
  final math.Random? random;

  @override
  State<OrbPlayPage> createState() => _OrbPlayPageState();
}

/// Somewhere the orb might suggest. A destination, why, and its picture.
class _Pick {
  const _Pick(this.place, this.why, this.emoji);

  final String place;
  final String why;
  final String emoji;
}

const List<_Pick> _picks = <_Pick>[
  _Pick('Hampi', 'boulders and ruins at sunrise', '🏛️'),
  _Pick('Spiti Valley', 'high desert, empty roads', '🏔️'),
  _Pick('Gokarna', 'quieter beaches than Goa', '🏖️'),
  _Pick('Udaipur', 'lakes and palaces', '🏰'),
  _Pick('Meghalaya', 'living root bridges', '🌿'),
  _Pick('Rann of Kutch', 'white salt desert', '🏜️'),
  _Pick('Coorg', 'coffee estates in the mist', '☕'),
  _Pick('Pondicherry', 'French lanes by the sea', '🥐'),
  _Pick('Varanasi', 'the ghats at dawn', '🛕'),
  _Pick('Andaman Islands', 'reefs and clear water', '🐠'),
  _Pick('Darjeeling', 'toy train and tea gardens', '🚂'),
  _Pick('Alleppey', 'a houseboat on the backwaters', '🛶'),
  _Pick('Jaisalmer', 'a night in the dunes', '🐪'),
  _Pick('Rishikesh', 'rafting on the Ganga', '🌊'),
  _Pick('Ladakh', 'monasteries and mountain passes', '🏍️'),
  _Pick('Kaziranga', 'rhinos at first light', '🦏'),
];

class _OrbPlayPageState extends State<OrbPlayPage> {
  late final GreetingClient _greetings =
      widget.greetings ?? GreetingClient(baseUrl: AppConfig.backendUrl);
  late final math.Random _rng = widget.random ?? math.Random();
  final GreetingVoice _voice = GreetingVoice();
  final RezolveOrbController _orb = RezolveOrbController();

  WelcomeLines? _lines;
  String _bubble = 'Poke me! Or ask me where to go.';
  _Pick? _picked;
  bool _spinning = false;
  int _pokes = 0;
  Timer? _reveal;

  /// Said when the backend is out of reach, so a poke still gets an answer.
  static const List<String> _offlinePokes = <String>[
    'Hey! That tickles.',
    'Boop!',
    "Again? Let's plan instead.",
    'Oi! Trip first.',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadLines());
  }

  Future<void> _loadLines() async {
    final WelcomeLines? lines = await _greetings.fetchWelcomeLines();
    if (mounted) setState(() => _lines = lines);
  }

  @override
  void dispose() {
    _reveal?.cancel();
    _voice.dispose();
    _orb.dispose();
    super.dispose();
  }

  void _poke() {
    unawaited(_voice.retryAudio());
    setState(() {
      _pokes++;
      _picked = null;
    });
    final List<SpokenLine>? spoken = _lines?.poke;
    if (spoken != null && spoken.isNotEmpty) {
      final SpokenLine line = spoken[_rng.nextInt(spoken.length)];
      setState(() => _bubble = line.text);
      unawaited(_voice.say(line));
    } else {
      setState(() => _bubble = _offlinePokes[_rng.nextInt(_offlinePokes.length)]);
    }
  }

  void _trick(OrbAntic antic, String line) {
    _voice.stop();
    _orb.play(antic);
    setState(() {
      _bubble = line;
      _picked = null;
    });
  }

  /// The trip roulette: a spin, a beat of suspense, then somewhere.
  void _surprise() {
    if (_spinning) return;
    _voice.stop();
    _orb.play(OrbAntic.spin);
    setState(() {
      _spinning = true;
      _picked = null;
      _bubble = 'Hmm, let me think…';
    });
    _reveal?.cancel();
    _reveal = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      final _Pick pick = _picks[_rng.nextInt(_picks.length)];
      _orb.play(OrbAntic.hop);
      setState(() {
        _spinning = false;
        _picked = pick;
        _bubble = 'How about ${pick.place}? ${pick.emoji}';
      });
    });
  }

  void _plan(_Pick pick) {
    Navigator.of(context).push(SlideUpRoute<void>(
      page: ChatPage(
        title: pick.place,
        opener: 'Plan a trip to ${pick.place} — ${pick.why}',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final double orb = math.min(MediaQuery.of(context).size.width * 0.58, 240);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFFE6E0FA), AppColors.canvas],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 8, AppSpacing.pageH, 0),
                child: Row(
                  children: <Widget>[
                    RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Play with COOKIE',
                        style: AppText.title.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_pokes > 0)
                      Text('$_pokes poke${_pokes == 1 ? '' : 's'}', style: AppText.caption),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    SpeechBubble(text: _bubble),
                    const SizedBox(height: 4),
                    ValueListenableBuilder<bool>(
                      valueListenable: _voice.speaking,
                      builder: (BuildContext _, bool speaking, Widget? _) =>
                          ValueListenableBuilder<double>(
                        valueListenable: _voice.level,
                        builder: (BuildContext _, double level, Widget? _) => RezolveOrb(
                          size: orb,
                          controller: _orb,
                          playfulness: 0.9,
                          mood: speaking
                              ? OrbMood.speaking
                              : _spinning
                                  ? OrbMood.thinking
                                  : OrbMood.idle,
                          amplitude: speaking ? level : null,
                          onTap: _poke,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('Tap COOKIE to poke it', style: AppText.caption),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _picked == null
                    ? const SizedBox(height: 0)
                    : Padding(
                        key: ValueKey<String>(_picked!.place),
                        padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 0, AppSpacing.pageH, 12),
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                          child: ListTile(
                            leading: Text(_picked!.emoji, style: const TextStyle(fontSize: 28)),
                            title: Text(_picked!.place, style: AppText.cardTitle),
                            subtitle: Text(_picked!.why, style: AppText.caption),
                            trailing: FilledButton(
                              onPressed: () => _plan(_picked!),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.brand,
                                shape: const StadiumBorder(),
                              ),
                              child: const Text('Plan it'),
                            ),
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 0, AppSpacing.pageH, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _spinning ? null : _surprise,
                    icon: const Icon(Icons.casino_rounded),
                    label: const Text('Surprise me — where should I go?'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const StadiumBorder(),
                      // From AppText: a bare TextStyle here replaces the
                      // button's font rather than adding to it.
                      textStyle: AppText.label.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 0, AppSpacing.pageH, 16),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final (String label, OrbAntic antic, String line) in <(String, OrbAntic, String)>[
                      ('Hop', OrbAntic.doubleHop, 'Boing boing!'),
                      ('Wink', OrbAntic.wink, "You didn't see that."),
                      ('Wiggle', OrbAntic.wiggle, 'Dance break!'),
                      ('Peek', OrbAntic.peek, 'Hello there…'),
                      ('Spin', OrbAntic.spin, 'Wheee!'),
                    ])
                      ActionChip(
                        label: Text(label),
                        onPressed: () => _trick(antic, line),
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: AppColors.brandLine),
                        labelStyle: AppText.label.copyWith(color: AppColors.brand, fontWeight: FontWeight.w600),
                        shape: const StadiumBorder(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
