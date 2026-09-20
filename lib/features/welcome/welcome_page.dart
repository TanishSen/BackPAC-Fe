import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_config.dart';
import '../../app/app_theme.dart';
import '../../orb/rezolve_orb.dart';
import '../../app/app.dart' show routeObserver;
import '../auth/auth_page.dart';
import '../auth/data/auth_service.dart';
import '../home/home_page.dart';
import 'data/greeting_client.dart';
import 'data/greeting_voice.dart';
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
    with SingleTickerProviderStateMixin, RouteAware {
  /// Keeps the headline breaking into three lines rather than two long ones.
  static const double _headlineMeasure = 258;

  /// Stage height as a multiple of the orb: the orb, plus room for the bubble
  /// above its shoulder and the reflection below it.
  static const double _stageRatio = 1.52;

  static const String _headlineLead = 'Your ';
  static const String _headlineAccent = 'Smart Assistant';
  static const String _headlineTail = ' for any planning…';
  /// What it says with no backend to speak for it. The screen still works
  /// offline — it just does it silently, exactly as it always did.
  static const List<String> _fallbackPoke = <String>[
    'Hehe!',
    'That tickles',
    'Hey, stop it!',
    'Boop',
    'Again?',
    'Ready when you are',
  ];

  static const List<String> _fallbackIdle = <String>[
    'So… where are we going?',
    'Still thinking?',
    "Let's plan something!",
    'What are you thinking?',
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
  /// Everything the orb can say, fetched in the background just after the
  /// opening line. Null until it arrives, and null forever if the backend
  /// isn't running — in which case the screen behaves silently, as it always
  /// did.
  late final GreetingClient _greetings =
      GreetingClient(baseUrl: AppConfig.backendUrl);
  final GreetingVoice _voice = GreetingVoice();
  WelcomeLines? _lines;

  /// Whether the opening line has gone out, so the silent fallback below and
  /// the arriving audio never both greet.
  bool _hasGreeted = false;

  /// Whether this screen is the one you are looking at.
  ///
  /// Pushing the home screen does not dispose this one — it sits alive under
  /// the new route with its timers still ticking and its player still loaded,
  /// so without this it carries on greeting and nudging from behind another
  /// page. [mounted] is no help: it stays true the whole time. Everything that
  /// speaks or schedules checks this instead.
  bool _awake = true;

  /// How many times it has nudged an idle user. Drives the gaps below, and
  /// resets the moment they do anything.
  int _nudges = 0;

  /// How long to wait before speaking up again, by nudge count.
  ///
  /// Escalating on purpose. The first prompt lands quickly, while someone is
  /// still deciding whether this thing is worth their time — after that it
  /// backs off, because an orb that pipes up every three seconds stops being
  /// charming almost immediately. The last gap repeats forever.
  static const List<Duration> _idleGaps = <Duration>[
    Duration(milliseconds: 3500),
    Duration(seconds: 7),
    Duration(seconds: 12),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];

  String _bubble = 'Hello!';
  OrbMood _mood = OrbMood.idle;
  bool _greeting = false;
  Timer? _greetOnce;
  Timer? _idleNudge;
  Timer? _hush;
  Timer? _bubbleOff;
  Timer? _pokeReply;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // A safety net, not the plan: if the greeting audio has not arrived by now
    // (no backend, slow network), greet silently rather than open on nothing.
    _greetOnce = Timer(AppDurations.greetingDelay, () {
      if (mounted && !_hasGreeted) _greet(null);
    });
    _voice.speaking.addListener(_onSpeakingChanged);
  }

  /// The opening line first, because it is wanted immediately; the rest in the
  /// background, because a tap must not wait on a round trip.
  Future<void> _load() async {
    final SpokenLine? opening = await _greetings.fetchGreeting();
    if (mounted && _awake && opening != null) {
      // Straight away. The greeting is the first thing the app does, so it
      // waits on nothing but its own audio — no timer, no stagger.
      if (!_hasGreeted) _greet(opening);
    }

    final WelcomeLines? lines = await _greetings.fetchWelcomeLines();
    if (!mounted || lines == null) return;
    setState(() => _lines = lines);
  }

  /// Open the conversation. Spoken if the audio made it, silent if it didn't.
  void _greet(SpokenLine? opening) {
    _hasGreeted = true;
    _greetOnce?.cancel();
    if (opening != null) {
      _say(opening);
    } else {
      _show('Hello!');
    }
  }

  // --- saying things --------------------------------------------------------

  /// Say a line out loud: bubble, mouth, and the level track that shapes it.
  void _say(SpokenLine line) {
    if (!_awake) return;
    _hush?.cancel(); // the voice's own clock decides when this one ends
    _idleNudge?.cancel();
    _bubbleOff?.cancel();
    setState(() {
      _greeting = true;
      _bubble = line.text;
      _mood = OrbMood.speaking;
    });
    unawaited(_voice.say(line));
  }

  /// Show a line without saying it — the offline path, and the stand-in while
  /// the audio is still on its way.
  void _show(String text, {Duration hold = AppDurations.greetingSpeech}) {
    if (!_awake) return;
    _hush?.cancel();
    _idleNudge?.cancel();
    _bubbleOff?.cancel();
    setState(() {
      _greeting = true;
      _bubble = text;
      _mood = OrbMood.speaking;
    });
    _hush = Timer(hold, () {
      if (!mounted) return;
      setState(() => _mood = OrbMood.idle);
      // Finish with a hop, so the first thing you see it do is unmistakably
      // alive rather than a wait for it to decide on something.
      _orb.play(OrbAntic.doubleHop);
      _hideBubble();
      _scheduleNudge();
    });
  }

  /// The orb reached the end of a spoken line: settle, land it, put the bubble
  /// away, and start counting down to the next nudge.
  void _onSpeakingChanged() {
    if (_voice.speaking.value || !mounted || !_awake) return;
    setState(() => _mood = OrbMood.idle);
    _orb.play(OrbAntic.doubleHop);
    _hideBubble();
    _scheduleNudge();
  }

  /// Clear the speech bubble a beat after the voice stops.
  ///
  /// The bubble is a caption, not a sign: it belongs to the line being said and
  /// goes away with it, leaving the orb sitting quietly. The short delay is so
  /// the last word is readable rather than snatched away on the final syllable.
  void _hideBubble() {
    _bubbleOff?.cancel();
    _bubbleOff = Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _greeting = false);
    });
  }

  // --- being poked ----------------------------------------------------------

  /// How long after the last tap the orb answers back.
  ///
  /// Every tap gets the immediate half — the haptic, the plink, and a hop the
  /// orb does on its own. The *reply* waits for you to finish. Someone
  /// drumming on it should get a bouncing orb, not eight half-spoken lines
  /// sawing each other off; one indignant sentence once they stop is both
  /// funnier and the only thing that sounds like a reaction.
  static const Duration _pokeReplyDelay = Duration(milliseconds: 650);

  /// Tapping the orb: it hops and looks at your finger on its own. This gives
  /// it something to say about being prodded — once you have stopped prodding.
  void _onPoke() {
    HapticFeedback.lightImpact();
    // A browser will not play sound until the page has been interacted with,
    // so the opening greeting is usually silent on web. This is the first
    // gesture there is — let it through.
    unawaited(_voice.retryAudio());
    unawaited(_dropSound.stop().then((_) {
      if (mounted) {
        _dropSound.play(
          AssetSource('sounds/freesound_community-water-drip-45622.mp3'),
        );
      }
    }));

    // They are clearly here. Start the idle escalation over.
    _nudges = 0;

    // Cut off whatever it was saying — being poked mid-sentence should stop it,
    // the way interrupting a person does — and clear the caption with it.
    _voice.stop();
    _hush?.cancel();
    _idleNudge?.cancel();
    _bubbleOff?.cancel();
    if (_greeting) setState(() => _greeting = false);

    // Restart the countdown. While the tapping continues this keeps being
    // pushed back, so the reply only lands once it stops.
    _pokeReply?.cancel();
    _pokeReply = Timer(_pokeReplyDelay, _replyToPoke);
  }

  /// The tapping has stopped. Say something about it.
  void _replyToPoke() {
    if (!mounted) return;
    final List<SpokenLine>? spoken = _lines?.poke;
    if (spoken != null && spoken.isNotEmpty) {
      _say(_pickLine(spoken));
    } else {
      _show(_pickText(_fallbackPoke), hold: const Duration(milliseconds: 1400));
    }
  }

  // --- nudging an idle user -------------------------------------------------

  void _scheduleNudge() {
    _idleNudge?.cancel();
    if (!_awake) return;
    final Duration gap = _idleGaps[math.min(_nudges, _idleGaps.length - 1)];
    _idleNudge = Timer(gap, _nudge);
  }

  /// Speak up after a stretch of nothing. Curious, never nagging — and the gap
  /// before the next one grows every time.
  void _nudge() {
    // Not while it is already talking, and not on top of a reply that is
    // waiting for the tapping to stop.
    if (!mounted || _voice.speaking.value || (_pokeReply?.isActive ?? false)) {
      return;
    }
    _nudges++;
    final List<SpokenLine>? spoken = _lines?.idle;
    if (spoken != null && spoken.isNotEmpty) {
      _say(_pickLine(spoken));
    } else {
      _show(_pickText(_fallbackIdle));
    }
  }

  // --- picking a line -------------------------------------------------------

  /// The last thing it said, so it never says the same thing twice running —
  /// which is what makes a small set of lines feel like a personality rather
  /// than a loop.
  String _lastSaid = '';

  SpokenLine _pickLine(List<SpokenLine> from) {
    SpokenLine choice = from[_rng.nextInt(from.length)];
    if (from.length > 1 && choice.text == _lastSaid) {
      choice = from[(from.indexOf(choice) + 1) % from.length];
    }
    _lastSaid = choice.text;
    return choice;
  }

  String _pickText(List<String> from) {
    String choice = from[_rng.nextInt(from.length)];
    if (from.length > 1 && choice == _lastSaid) {
      choice = from[(from.indexOf(choice) + 1) % from.length];
    }
    _lastSaid = choice;
    return choice;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  /// Something has been pushed over this screen.
  @override
  void didPushNext() => _goQuiet();

  /// That something has been popped, and this screen is back on top.
  @override
  void didPopNext() => _wakeUp();

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _greetOnce?.cancel();
    _idleNudge?.cancel();
    _hush?.cancel();
    _bubbleOff?.cancel();
    _pokeReply?.cancel();
    _idleFloat.dispose();
    _orb.dispose();
    _dropSound.dispose();
    _voice.speaking.removeListener(_onSpeakingChanged);
    _voice.dispose();
    _greetings.dispose();
    super.dispose();
  }

  /// Put this screen to sleep: the voice, every countdown, and any reply still
  /// waiting to land.
  ///
  /// Cancelling the timers is not enough on its own — stopping the voice fires
  /// [_onSpeakingChanged], which would otherwise start the next countdown
  /// immediately — so [_awake] goes down first and holds everything shut.
  void _goQuiet() {
    _awake = false;
    _greetOnce?.cancel();
    _idleNudge?.cancel();
    _hush?.cancel();
    _bubbleOff?.cancel();
    _pokeReply?.cancel();
    _voice.stop();
    if (mounted) {
      setState(() {
        _greeting = false;
        _mood = OrbMood.idle;
      });
    }
  }

  /// Back on this screen after the home screen was popped: it may speak again,
  /// starting from a fresh silence rather than mid-escalation.
  void _wakeUp() {
    if (!mounted) return;
    _awake = true;
    _nudges = 0;
    _scheduleNudge();
  }

  void _start() {
    // The push leaves this screen alive underneath, so silence it by hand and
    // let it speak again only once it is back on top.
    _goQuiet();

    // Straight to the home screen if there is already a session — Supabase
    // restores one from disk at launch, so someone who signed in last week
    // never sees the form again. Otherwise sign in first: the history screen
    // and starting a call both need a token the backend will accept.
    final Widget next = AuthService().isSignedIn
        ? const HomePage()
        : AuthPage(
            onSignedIn: () {
              // Replace rather than push, so Back from the home screen does
              // not land on a login form for an account already signed in.
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const HomePage(),
                ),
              );
            },
          );

    // No .then(_wakeUp) here. Coming back is the route observer's business —
    // see didPopNext — because this future also fires when the pushed route is
    // replaced, which is exactly what signing in does.
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (BuildContext _) => next));
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
                            amplitude: _voice.level,
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
    required this.amplitude,
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

  /// Live loudness of the spoken greeting, 0..1 — so the orb's mouth is shaped
  /// by the actual words. Zero when it isn't talking, which the orb reads as
  /// "improvise nothing" and simply holds still.
  final ValueListenable<double> amplitude;

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
                // Rebuilt on its own so a level arriving 20 times a second
                // repaints the orb and nothing else on the page.
                child: ValueListenableBuilder<double>(
                  valueListenable: amplitude,
                  builder: (BuildContext context, double level, _) => RezolveOrb(
                    size: size,
                    headroom: _headroom,
                    mood: mood,
                    // Null hands the orb back its own improvised rhythm, which
                    // is what should happen when there is no audio to follow.
                    amplitude: level > 0 ? level : null,
                    controller: controller,
                    onTap: onPoke,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: size * 0.10 + t * 5,
                // Switched rather than faded to transparent: a bubble held at
                // zero opacity is still in the tree, so a screen reader goes on
                // announcing a caption that is no longer on screen.
                child: AnimatedSwitcher(
                  duration: AppDurations.bubbleIn,
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeOut,
                  transitionBuilder: (Widget child, Animation<double> anim) =>
                      FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.86, end: 1).animate(anim),
                      alignment: Alignment.bottomRight,
                      child: child,
                    ),
                  ),
                  child: showBubble
                      ? SpeechBubble(key: ValueKey<String>(bubble), text: bubble)
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
