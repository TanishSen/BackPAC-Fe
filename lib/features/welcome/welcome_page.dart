import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_theme.dart';
import '../../orb/rezolve_orb.dart';
import '../home/home_page.dart';
import 'widgets/orb_reflection.dart';
import 'widgets/primary_button.dart';
import 'widgets/speech_bubble.dart';

/// The first screen: the assistant greets you, then waits.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with SingleTickerProviderStateMixin {
  /// Keeps the headline breaking into three lines rather than two long ones.
  static const double _headlineMeasure = 258;

  /// Stage height as a multiple of the orb: the orb, plus room for the bubble
  /// above its shoulder and the reflection below it.
  static const double _stageRatio = 1.52;

  static const String _headlineLead = 'Your ';
  static const String _headlineAccent = 'Smart Assistant';
  static const String _headlineTail = ' for any planning…';
  /// What it says when you poke it. Short, and never the same twice running.
  static const List<String> _pokeLines = <String>[
    'Hehe!',
    'That tickles',
    'Hi there!',
    'Boop',
    'Again?',
    'Ready when you are',
  ];

  static const String _subtitle =
      'Get instant help and support\nwith any task or problem';

  /// Drives the bubble's slow float and the reflection's breath. One controller
  /// for both, so they stay in step and cost a single ticker.
  late final AnimationController _idleFloat = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat(reverse: true);

  final RezolveOrbController _orb = RezolveOrbController();
  final math.Random _rng = math.Random();

  /// Dedicated low-latency player for the orb's poke sound, so a fast flurry
  /// of taps never queues up or clips: each tap restarts it from frame zero.
  final AudioPlayer _dropSound = AudioPlayer(playerId: 'orb-poke')
    ..setReleaseMode(ReleaseMode.stop)
    ..setPlayerMode(PlayerMode.lowLatency);
  String _bubble = 'Hello!';
  OrbMood _mood = OrbMood.idle;
  bool _greeting = false;
  Timer? _greetOnce;
  Timer? _greetAgain;
  Timer? _hush;

  @override
  void initState() {
    super.initState();
    _greetOnce = Timer(AppDurations.greetingDelay, _sayHello);
    _greetAgain =
        Timer.periodic(AppDurations.greetingInterval, (_) => _sayHello());
  }

  /// Bubble in, orb talks, orb settles. The bubble stays — it is part of the
  /// composition — but the orb only speaks in short, calm bursts.
  void _sayHello() {
    if (!mounted) return;
    _hush?.cancel();
    setState(() {
      _greeting = true;
      _bubble = 'Hello!';
      _mood = OrbMood.speaking;
    });
    _hush = Timer(AppDurations.greetingSpeech, () {
      if (!mounted) return;
      setState(() => _mood = OrbMood.idle);
      // Finish the hello with a hop, so the first thing you see the orb do is
      // unmistakably alive rather than a wait for it to decide on something.
      _orb.play(OrbAntic.doubleHop);
    });
  }

  /// Tapping the orb: it hops and looks at your finger on its own — this adds
  /// a line in the bubble and a short burst of chatter to go with it.
  void _onPoke() {
    HapticFeedback.lightImpact();
    unawaited(_dropSound.stop().then((_) {
      if (mounted) {
        _dropSound.play(
          AssetSource('sounds/freesound_community-water-drip-45622.mp3'),
        );
      }
    }));
    _hush?.cancel();
    String line = _pokeLines[_rng.nextInt(_pokeLines.length)];
    if (line == _bubble) {
      line = _pokeLines[(_pokeLines.indexOf(line) + 1) % _pokeLines.length];
    }
    setState(() {
      _greeting = true;
      _bubble = line;
      _mood = OrbMood.speaking;
    });
    _hush = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _mood = OrbMood.idle);
    });
  }

  @override
  void dispose() {
    _greetOnce?.cancel();
    _greetAgain?.cancel();
    _hush?.cancel();
    _idleFloat.dispose();
    _orb.dispose();
    _dropSound.dispose();
    super.dispose();
  }

  void _start() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext _) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);

    // Very large system text would break a layout this tight; cap it rather
    // than let the headline collide with the orb.
    final TextScaler scaler = media.textScaler.clamp(maxScaleFactor: 1.25);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: MediaQuery(
        data: media.copyWith(textScaler: scaler),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth - AppSpacing.pageH * 2;

              // Measure the text instead of guessing at it: the orb then takes
              // exactly the room that is genuinely left, at any text scale.
              final double wordmarkH =
                  _measure(TextSpan(text: 'backPAC.', style: AppText.wordmark),
                      width, scaler);
              final double headlineH = _measure(_headlineSpan(),
                  math.min(_headlineMeasure, width), scaler);
              final double subtitleH = _measure(
                  const TextSpan(text: _subtitle, style: AppText.body),
                  width,
                  scaler);

              const double gaps = 18 + 34 + 8 + 8 + 26 + AppSpacing.bottomSafe;
              final double chrome = gaps +
                  wordmarkH +
                  headlineH +
                  subtitleH +
                  AppSpacing.buttonHeight;
              final double free = math.max(0, constraints.maxHeight - chrome);

              final double orbSize = math
                  .min(width * 0.82, free / _stageRatio)
                  .clamp(170.0, 320.0);
              final double stageBox = math.max(orbSize * _stageRatio, free);

              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const SizedBox(height: 18),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('backPAC.', style: AppText.wordmark),
                      ),
                      const SizedBox(height: 34),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxWidth: _headlineMeasure),
                          child: Text.rich(
                            _headlineSpan(),
                            textAlign: TextAlign.center,
                            style: AppText.headline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: stageBox,
                        child: Center(
                          child: _OrbStage(
                            size: orbSize,
                            mood: _mood,
                            bubble: _bubble,
                            showBubble: _greeting,
                            float: _idleFloat,
                            controller: _orb,
                            onPoke: _onPoke,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        _subtitle,
                        textAlign: TextAlign.center,
                        style: AppText.body,
                      ),
                      const SizedBox(height: 26),
                      PrimaryButton(label: "Let's Start", onPressed: _start),
                      const SizedBox(height: AppSpacing.bottomSafe),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static TextSpan _headlineSpan() => const TextSpan(
        style: AppText.headline,
        children: <InlineSpan>[
          TextSpan(text: _headlineLead),
          TextSpan(
            text: _headlineAccent,
            style: TextStyle(color: AppColors.brandSoft),
          ),
          TextSpan(text: _headlineTail),
        ],
      );

  static double _measure(TextSpan span, double maxWidth, TextScaler scaler) {
    final TextPainter painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: scaler,
    )..layout(maxWidth: math.max(0.0, maxWidth));
    final double height = painter.height;
    painter.dispose();
    return height;
  }
}

/// The orb, its reflection and the greeting bubble, composed as one unit so
/// the bubble stays pinned to the orb's shoulder and the shadow stays under its
/// feet at every screen size.
class _OrbStage extends StatelessWidget {
  const _OrbStage({
    required this.size,
    required this.mood,
    required this.bubble,
    required this.showBubble,
    required this.float,
    required this.controller,
    required this.onPoke,
  });

  /// Width of the orb widget. The ball itself is a little smaller — the rest is
  /// the halo — and the widget is taller than [size] to leave hop headroom.
  final double size;
  final OrbMood mood;
  final String bubble;
  final bool showBubble;
  final Animation<double> float;
  final RezolveOrbController controller;
  final VoidCallback onPoke;

  /// Must match [RezolveOrb.headroom] below.
  static const double _headroom = 0.26;

  @override
  Widget build(BuildContext context) {
    final double orbBox = size * (1 + _headroom);

    return SizedBox(
      width: size * 1.30,
      height: size * _WelcomePageState._stageRatio,
      child: AnimatedBuilder(
        animation: float,
        builder: (BuildContext context, Widget? child) {
          final double t = Curves.easeInOut.transform(float.value);
          return Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: <Widget>[
              // The shadow lives on the page, not in the orb, so it can react
              // to the bounce: it shrinks and fades as the orb leaves the
              // floor, and spreads when it lands and squashes.
              Positioned(
                top: orbBox - size * 0.06,
                child: ValueListenableBuilder<OrbFrame>(
                  valueListenable: controller.frames,
                  builder: (BuildContext context, OrbFrame frame, _) {
                    final double lift = frame.lift;
                    final double spread =
                        1 + 0.20 * frame.squash - 0.24 * lift;
                    return OrbReflection(
                      width: size * 0.74 * spread + t * 5,
                      opacity: ((0.92 - 0.55 * lift) + t * 0.08).clamp(0.0, 1.0),
                    );
                  },
                ),
              ),
              Positioned(
                top: 0,
                child: RezolveOrb(
                  size: size,
                  headroom: _headroom,
                  mood: mood,
                  controller: controller,
                  onTap: onPoke,
                ),
              ),
              Positioned(
                left: 0,
                top: size * 0.10 + t * 5,
                child: AnimatedScale(
                  scale: showBubble ? 1 : 0.86,
                  duration: AppDurations.bubbleIn,
                  curve: Curves.easeOutBack,
                  alignment: Alignment.bottomRight,
                  child: AnimatedOpacity(
                    opacity: showBubble ? 1 : 0,
                    duration: AppDurations.bubbleIn,
                    curve: Curves.easeOut,
                    child: SpeechBubble(text: bubble),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
