import 'dart:math' as math;
import 'dart:ui';

import 'orb_motion.dart';

/// What the orb is doing. Changing this never snaps: every value below is
/// spring-filtered, so a mood switch eases over ~400 ms on its own.
enum OrbMood {
  /// Quiet, awake, occasional blink — and, left alone, it starts to fidget:
  /// see [OrbAntic].
  idle,

  /// Attending to the user: eyes a touch wider, mouth closed, calm pulse.
  listening,

  /// Working on it: gaze drifts up and away, lids lower slightly.
  thinking,

  /// Talking. The mouth opens in slow syllables and warm light spills from it.
  /// The orb holds still while it speaks — fidgeting mid-sentence reads as
  /// distracted rather than alive.
  speaking,
}

/// The little things the orb does when nobody is asking it for anything.
enum OrbAntic {
  /// One bounce off the floor, with the squash and stretch that sells it.
  hop,

  /// Two or three bounces, each smaller than the last.
  doubleHop,

  lookUp,
  lookDown,
  lookLeft,
  lookRight,

  /// A quick shimmy from side to side.
  wiggle,

  /// One eye, closed, with a smirk. The naughty one.
  wink,

  /// Leans over and rights itself.
  tilt,

  /// Leans in towards you, eyes wide.
  peek,

  /// Rolls its whole colour field over once.
  spin,
}

/// One rendered moment of the orb. Pure data — the painter reads it and draws,
/// which keeps the animation logic testable on its own.
class OrbFrame {
  const OrbFrame({
    required this.time,
    required this.scale,
    required this.sway,
    required this.tilt,
    required this.hop,
    required this.squash,
    required this.lift,
    required this.leftEyeOpen,
    required this.rightEyeOpen,
    required this.eyeWide,
    required this.squint,
    required this.gaze,
    required this.mouthOpen,
    required this.mouthWidth,
    required this.smile,
    required this.smirk,
    required this.warmth,
    required this.halo,
  });

  final double time;

  /// Breathing. Hovers around 1.0 by about ±1.5%.
  final double scale;

  /// Whole-orb wander and lean, in ball radii.
  final Offset sway;

  /// Radians. The colour field rotates; the face does not.
  final double tilt;

  /// Height off the floor, in ball radii. Negative is up.
  final double hop;

  /// -1 stretched tall and thin .. 0 round .. +1 squashed wide and flat.
  /// Anchored at the bottom of the ball, so a squash flattens onto the floor.
  final double squash;

  /// 0 resting on the floor .. 1 at the top of a big hop. The page uses this to
  /// shrink and fade the shadow underneath.
  final double lift;

  final double leftEyeOpen; // 0 shut .. 1 open
  final double rightEyeOpen;
  final double eyeWide; // -0.2 narrowed .. 0.3 wide
  final double squint; // 0 .. 1, the happy `^ ^` bend
  final Offset gaze; // -1..1 in each axis
  final double mouthOpen; // 0 closed .. 1 wide
  final double mouthWidth; // ~0.8 .. 1.2
  final double smile; // 0 .. 1
  final double smirk; // -1 .. 1, pulls one corner up higher than the other
  final double warmth; // 0 .. 1, how much the low clouds glow
  final double halo; // 0 .. 1, outer bloom

  static const OrbFrame rest = OrbFrame(
    time: 0,
    scale: 1,
    sway: Offset.zero,
    tilt: 0,
    hop: 0,
    squash: 0,
    lift: 0,
    leftEyeOpen: 1,
    rightEyeOpen: 1,
    eyeWide: 0,
    squint: 0,
    gaze: Offset.zero,
    mouthOpen: 0,
    mouthWidth: 1,
    smile: 0,
    smirk: 0,
    warmth: 0,
    halo: 0.1,
  );
}

/// Drives the orb. Feed it `dt` each frame and it hands back an [OrbFrame].
///
/// Two layers run at once: a calm baseline (breath, blink, drifting gaze,
/// speech) and, when the orb is idle, a stream of [OrbAntic]s on top.
class OrbChoreographer {
  OrbChoreographer({
    OrbMood initialMood = OrbMood.idle,
    this.playfulness = 0.7,
    math.Random? random,
  })  : _mood = initialMood,
        _rng = random ?? math.Random();

  /// 0 = perfectly still between greetings, 1 = a handful every few seconds.
  double playfulness;

  final math.Random _rng;

  OrbMood _mood;
  OrbMood get mood => _mood;
  set mood(OrbMood value) {
    if (value == _mood) return;
    _mood = value;
    _endAntic();
    _gazeHold = 0.3;
    _gazeTarget = Offset.zero;
    if (value == OrbMood.speaking) _speechClock = 0;
    // A beat to settle after talking, then back to playing.
    _anticIn = 1.3;
  }

  /// Optional live level, 0..1, from a TTS engine or mic. When set, it replaces
  /// the synthetic speech rhythm — still spring-smoothed, so raw jittery
  /// amplitude data comes out soothing rather than chattering.
  double? amplitude;

  /// The antic playing right now, if any. Handy for tests and debugging.
  OrbAntic? get antic => _antic;

  double _t = 0;
  double _speechClock = 0;

  // ---- lids ----
  double _blinkIn = 2.4;
  double _blinkPhase = -1;
  int _queuedBlinks = 0;
  double _winkT = -1;

  // ---- gaze ----
  Offset _gazeTarget = Offset.zero;
  double _gazeHold = 1.6;

  // ---- antics ----
  OrbAntic? _antic;
  double _anticT = 0;
  double _anticDur = 0;
  double _anticIn = 1.6;
  int _hopsLeft = 0;
  double _spinFrom = 0;

  // ---- bounce physics, in ball radii ----
  static const double _gravity = 11.0;
  double _hopY = 0;
  double _hopV = 0;

  final Spring _mouth = Spring(stiffness: 68);
  final Spring _width = Spring(stiffness: 70, initial: 1);
  final Spring _smile = Spring(stiffness: 55);
  final Spring _smirk = Spring(stiffness: 60);
  final Spring _wide = Spring(stiffness: 45);
  final Spring _squint = Spring(stiffness: 50);
  final Spring _peek = Spring(stiffness: 60);
  final Spring _spin = Spring(stiffness: 26, damping: 11);
  final Spring2 _gaze = Spring2(stiffness: 34);
  final Spring2 _lean = Spring2(stiffness: 55);

  /// Jelly: deliberately under-damped so a landing wobbles before it settles.
  final Spring _squash = Spring(stiffness: 210, damping: 13);

  /// Somebody tapped the orb. It looks where it was touched, jumps, and grins.
  ///
  /// [where] is in the orb's own space: (0, 0) is the middle, (-1, -1) the top
  /// left corner.
  void poke([Offset where = Offset.zero]) {
    _gazeTarget = Offset(where.dx.clamp(-1.0, 1.0), where.dy.clamp(-1.0, 1.0));
    _gazeHold = 1.1;
    _startAntic(OrbAntic.doubleHop);
    _smile.snapTo(math.max(_smile.value, 0.55));
  }

  /// Trigger one deliberately, instead of waiting for the orb to choose.
  void play(OrbAntic which) => _startAntic(which);

  OrbFrame advance(double dt) {
    // Clamp so a background tab or a janky first frame can't jolt the orb.
    dt = dt.clamp(0.0, 1 / 20);
    _t += dt;
    if (_mood == OrbMood.speaking) _speechClock += dt;

    _stepAntics(dt);
    _stepBounce(dt);
    _stepLids(dt);
    _stepGaze(dt);

    // ---- speech ------------------------------------------------------------
    var mouthTarget = 0.0;
    var widthTarget = 1.0;
    if (_mood == OrbMood.speaking) {
      final live = amplitude;
      if (live != null) {
        mouthTarget = live.clamp(0.0, 1.0);
      } else {
        // Slow syllables (~0.95 Hz) whose rhythm itself wanders, gated by a
        // much slower phrase envelope so the orb pauses for breath.
        final syllable = 0.5 +
            0.5 *
                math.sin(2 * math.pi * 0.95 * _speechClock +
                    sbm(_speechClock * 0.5) * 2.4);
        final phrase = smoothstep(0.30, 0.62, fbm(_speechClock * 0.21 + 3.7));
        mouthTarget = (0.16 + 0.74 * syllable) * phrase;
      }
      // Vowel shape: wide for "ee", narrow for "oh". Drifts independently of
      // how open the mouth is, which is what makes it read as speech.
      widthTarget = 0.86 + 0.30 * fbm(_speechClock * 0.63 + 8.2);
    } else if (_antic == OrbAntic.hop || _antic == OrbAntic.doubleHop) {
      // A little "wheee" while airborne.
      mouthTarget = 0.22 + 0.34 * (-_hopY).clamp(0.0, 1.0);
      widthTarget = 1.06;
    } else if (_antic == OrbAntic.peek) {
      mouthTarget = 0.16;
    }
    _mouth.step(dt, mouthTarget);
    _width.step(dt, widthTarget);

    // ---- mood shaping ------------------------------------------------------
    final anticSmile = switch (_antic) {
      OrbAntic.hop || OrbAntic.doubleHop || OrbAntic.wiggle => 0.55,
      OrbAntic.wink => 0.62,
      OrbAntic.peek || OrbAntic.spin => 0.40,
      _ => 0.0,
    };
    final smileTarget = math.max(
      anticSmile,
      switch (_mood) {
        OrbMood.idle => 0.16,
        OrbMood.listening => 0.28,
        OrbMood.thinking => 0.04,
        OrbMood.speaking => 0.34 + 0.16 * _mouth.value,
      },
    );
    final wideTarget = switch (_mood) {
          OrbMood.idle => 0.0,
          OrbMood.listening => 0.16,
          OrbMood.thinking => -0.12,
          OrbMood.speaking => 0.05,
        } +
        (_antic == OrbAntic.peek ? 0.22 : 0.0) +
        (_antic == OrbAntic.lookUp ? 0.10 : 0.0);
    // Cheeks lift on the loud parts of a sentence, and on a big smile.
    final squintTarget = switch (_mood) {
      OrbMood.speaking => 0.30 * smoothstep(0.55, 1.0, _mouth.value),
      OrbMood.listening => 0.12,
      _ => 0.0,
    };
    _smile.step(dt, smileTarget);
    _wide.step(dt, wideTarget);
    _squint.step(dt, squintTarget);
    _smirk.step(dt, _winkT >= 0 ? 0.85 : 0.0);
    _lean.settle(dt);
    _spin.stepToTarget(dt);
    _peek.step(dt, _antic == OrbAntic.peek ? 1 : 0);

    // ---- body --------------------------------------------------------------
    final breath = math.sin(2 * math.pi * _t / 5.6); // one slow breath / 5.6 s
    final scale = 1 + breath * 0.014 + _mouth.value * 0.008 + _peek.value * 0.05;

    var sway = Offset(sbm(_t * 0.07) * 0.016, sbm(_t * 0.055 + 9.1) * 0.013) +
        _lean.value;
    var tilt = sbm(_t * 0.045 + 21.7) * 0.035; // ±2° of ambient drift
    tilt += _spin.value;

    if (_antic == OrbAntic.wiggle) {
      // A decaying shimmy — fast at the start, settled by the end.
      final decay = 1 - (_anticT / _anticDur).clamp(0.0, 1.0);
      final w = math.sin(_anticT * 17) * decay;
      sway += Offset(w * 0.07, 0);
      tilt += w * 0.07;
    }

    final warmth = _mouth.value * 0.85 +
        (_mood == OrbMood.listening ? 0.10 + 0.06 * (0.5 + 0.5 * breath) : 0.0);
    final halo = 0.08 + 0.06 * (0.5 + 0.5 * breath) + 0.42 * _mouth.value;

    final lidBase = 1 + _wide.value;
    final blink = _lidOpenness(_blinkPhase);
    // The right lid trails the left by 25 ms. Nobody notices it directly;
    // everyone notices when both lids are perfectly synchronous.
    final blinkR = _lidOpenness(_blinkPhase - 0.025);
    final wink = _winkOpenness();

    return OrbFrame(
      time: _t,
      scale: scale,
      sway: sway,
      tilt: tilt,
      hop: _hopY,
      squash: _squash.value.clamp(-1.0, 1.0),
      lift: (-_hopY / 0.34).clamp(0.0, 1.0),
      leftEyeOpen: (math.min(blink, wink) * lidBase).clamp(0.0, 1.3),
      rightEyeOpen: (blinkR * lidBase).clamp(0.0, 1.3),
      eyeWide: _wide.value,
      squint: _squint.value,
      gaze: _gaze.value,
      mouthOpen: _mouth.value.clamp(0.0, 1.0),
      mouthWidth: _width.value,
      smile: _smile.value.clamp(0.0, 1.0),
      smirk: _smirk.value,
      warmth: warmth.clamp(0.0, 1.0),
      halo: halo.clamp(0.0, 1.0),
    );
  }

  // --------------------------------------------------------------- antics ---

  void _stepAntics(double dt) {
    if (_antic != null) {
      _anticT += dt;
      if (_anticT >= _anticDur && _hopsLeft == 0 && _hopY >= -0.001) {
        _endAntic();
      }
      return;
    }
    if (playfulness <= 0 ||
        _mood == OrbMood.speaking ||
        _mood == OrbMood.thinking) {
      return;
    }
    _anticIn -= dt * (0.4 + playfulness);
    if (_anticIn <= 0) _startAntic(_chooseAntic());
  }

  /// Antics are dealt from a shuffled deck rather than rolled independently.
  /// A weighted die kept handing out the same trick several times running,
  /// which reads as broken rather than random; a deck guarantees the whole
  /// repertoire shows up, in a different order every time.
  static const List<OrbAntic> _deckTemplate = <OrbAntic>[
    OrbAntic.hop, OrbAntic.hop, OrbAntic.hop, OrbAntic.hop, OrbAntic.hop,
    OrbAntic.doubleHop, OrbAntic.doubleHop, OrbAntic.doubleHop,
    OrbAntic.lookLeft, OrbAntic.lookLeft,
    OrbAntic.lookRight, OrbAntic.lookRight,
    OrbAntic.lookUp, OrbAntic.lookUp,
    OrbAntic.lookDown,
    OrbAntic.wiggle, OrbAntic.wiggle,
    OrbAntic.wink, OrbAntic.wink,
    OrbAntic.tilt,
    OrbAntic.peek,
    OrbAntic.spin,
  ];

  final List<OrbAntic> _deck = <OrbAntic>[];
  OrbAntic? _lastAntic;

  OrbAntic _chooseAntic() {
    if (_deck.isEmpty) {
      _deck.addAll(_deckTemplate);
      _deck.shuffle(_rng);
      // Never open a fresh deck with the trick that closed the last one.
      if (_deck.first == _lastAntic && _deck.length > 1) {
        _deck.add(_deck.removeAt(0));
      }
    }
    final OrbAntic next = _deck.removeAt(0);
    _lastAntic = next;
    return next;
  }

  void _startAntic(OrbAntic a) {
    _antic = a;
    _anticT = 0;
    switch (a) {
      case OrbAntic.hop:
        _anticDur = 0.80;
        _launch(3.45, bounces: 1);
      case OrbAntic.doubleHop:
        _anticDur = 1.50;
        _launch(3.75, bounces: 2);
      case OrbAntic.lookUp:
        _anticDur = 1.5;
        _look(const Offset(0.12, -0.92));
      case OrbAntic.lookDown:
        _anticDur = 1.4;
        _look(const Offset(-0.10, 0.85));
      case OrbAntic.lookLeft:
        _anticDur = 1.5;
        _look(const Offset(-0.95, -0.10));
      case OrbAntic.lookRight:
        _anticDur = 1.5;
        _look(const Offset(0.95, -0.10));
      case OrbAntic.wiggle:
        _anticDur = 0.95;
      case OrbAntic.wink:
        _anticDur = 0.75;
        _winkT = 0;
      case OrbAntic.tilt:
        _anticDur = 1.1;
        _lean.x.target = _rng.nextBool() ? 0.06 : -0.06;
      case OrbAntic.peek:
        _anticDur = 1.3;
      case OrbAntic.spin:
        _anticDur = 1.4;
        _spinFrom = _spin.value;
        _spin.target = _spinFrom + 2 * math.pi;
    }
  }

  void _endAntic() {
    _antic = null;
    _anticT = 0;
    _hopsLeft = 0;
    _winkT = -1;
    _lean.x.target = 0;
    _lean.y.target = 0;
    // Wait longer when the orb is calm, less when it is feeling playful.
    _anticIn = 1.1 + _rng.nextDouble() * 1.9;
    // Keep the accumulated spin angle small without changing what is on
    // screen: a whole turn looks identical.
    if (_spin.value.abs() > math.pi * 4) {
      _spin.snapTo(_spin.value % (2 * math.pi));
    }
  }

  void _look(Offset direction) {
    _gazeTarget = direction;
    _gazeHold = _anticDur;
    // The body leans a little the way it is looking. Eyes alone read as a
    // stare; eyes plus a lean reads as attention.
    _lean.x.target = direction.dx * 0.09;
    _lean.y.target = direction.dy * 0.055;
  }

  // ---------------------------------------------------------------- bounce --

  void _launch(double speed, {required int bounces}) {
    _hopV = -speed;
    _hopsLeft = bounces - 1;
    // Anticipation: a quick crouch as it pushes off.
    _squash.snapTo(0.34);
  }

  void _stepBounce(double dt) {
    if (_hopY < 0 || _hopV != 0) {
      _hopV += _gravity * dt;
      _hopY += _hopV * dt;
      if (_hopY >= 0) {
        // Landing. The impact squash scales with how hard it hit.
        final impact = (_hopV / 3.0).clamp(0.0, 1.0);
        _hopY = 0;
        if (_hopsLeft > 0) {
          _hopsLeft--;
          _hopV = -_hopV * 0.52;
        } else {
          _hopV = 0;
        }
        _squash.snapTo(0.26 + 0.28 * impact);
      } else {
        // Stretch along the direction of travel while airborne.
        _squash.snapTo(-0.20 * (_hopV.abs() / 3.0).clamp(0.0, 1.0));
      }
    }
    _squash.step(dt, 0);
  }

  // ------------------------------------------------------------------ lids --

  void _stepLids(double dt) {
    if (_winkT >= 0) {
      _winkT += dt;
      if (_winkT > 0.55) _winkT = -1;
    }
    if (_blinkPhase >= 0) {
      _blinkPhase += dt;
      if (_blinkPhase > _blinkDuration) {
        _blinkPhase = -1;
        if (_queuedBlinks > 0) {
          _queuedBlinks--;
          _blinkPhase = 0; // the second half of a double blink
        } else {
          _scheduleBlink();
        }
      }
      return;
    }
    _blinkIn -= dt;
    if (_blinkIn <= 0) {
      _blinkPhase = 0;
      if (_rng.nextDouble() > 0.8) _queuedBlinks = 1; // one in five is a double
    }
  }

  void _scheduleBlink() {
    // 3.2 s .. 6.4 s apart while idle, a little quicker while speaking.
    final base = _mood == OrbMood.speaking ? 2.6 : 3.2;
    _blinkIn = base + _rng.nextDouble() * 3.2;
  }

  static const double _blinkDuration = 0.30;

  /// 1 = open, 0 = shut. Closes faster than it opens, the way a real lid does.
  double _lidOpenness(double phase) {
    if (phase < 0 || phase > _blinkDuration) return 1;
    const close = 0.085;
    const hold = 0.045;
    if (phase < close) {
      final t = phase / close;
      return 1 - t * t; // ease-in: the lid accelerates down
    }
    if (phase < close + hold) return 0;
    final t = (phase - close - hold) / (_blinkDuration - close - hold);
    return 1 - (1 - t) * (1 - t); // ease-out: it floats back up
  }

  /// The left eye only, for [OrbAntic.wink]: down fast, held, back up slowly.
  double _winkOpenness() {
    if (_winkT < 0) return 1;
    const close = 0.11;
    const hold = 0.20;
    if (_winkT < close) {
      final t = _winkT / close;
      return 1 - t * t;
    }
    if (_winkT < close + hold) return 0;
    final t = (_winkT - close - hold) / (0.55 - close - hold);
    return 1 - (1 - t) * (1 - t);
  }

  // ------------------------------------------------------------------ gaze --

  void _stepGaze(double dt) {
    _gazeHold -= dt;
    if (_gazeHold <= 0) {
      switch (_mood) {
        case OrbMood.thinking:
          // Away and up — the universal "let me think" look.
          _gazeTarget = Offset(-0.28 - 0.18 * _rng.nextDouble(),
              -0.30 - 0.14 * _rng.nextDouble());
          _gazeHold = 1.4 + _rng.nextDouble() * 1.6;
        case OrbMood.listening:
          _gazeTarget =
              Offset(sbm(_t * 0.8 + 1.1) * 0.12, sbm(_t * 0.8 + 6.3) * 0.08);
          _gazeHold = 1.8 + _rng.nextDouble() * 2.0;
        default:
          _gazeTarget =
              Offset(sbm(_t * 0.6 + 3.3) * 0.22, sbm(_t * 0.6 + 8.8) * 0.14);
          _gazeHold = 1.6 + _rng.nextDouble() * 2.4;
      }
    }
    _gaze.step(dt, _gazeTarget);
  }
}
