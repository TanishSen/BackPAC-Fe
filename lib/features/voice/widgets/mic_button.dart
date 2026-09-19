import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../orb/orb_expression.dart';
import '../../../orb/orb_painter.dart';
import '../voice_controller.dart';

/// The mic.
///
/// Two things move: a small waveform inside the circle, and waves rolling
/// outwards from its edge. Three rings at most, thin and fading — a ring of
/// bars around the rim was tried first and read as clutter, so the waves carry
/// the energy on their own.
class MicButton extends StatefulWidget {
  const MicButton({
    super.key,
    required this.state,
    required this.level,
    required this.onTap,
    this.size = 76,
  });

  final VoiceState state;
  final ValueListenable<double> level;
  final VoidCallback onTap;
  final double size;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  bool _down = false;
  double _smoothed = 0;

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double ring = widget.size + 26;
    // Room for the waves to travel into before they fade out.
    final double box = widget.size * 2.15;

    return Semantics(
      button: true,
      label: switch (widget.state) {
        VoiceState.idle => 'Tap to speak',
        VoiceState.listening => 'Listening. Tap to send',
        VoiceState.thinking => 'Thinking',
        VoiceState.speaking => 'Speaking. Tap to interrupt',
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_clock, widget.level]),
          builder: (BuildContext context, _) {
            _smoothed += (widget.level.value - _smoothed) * 0.20;
            final bool active = widget.state != VoiceState.idle;

            return SizedBox(
              width: box,
              height: box,
              child: CustomPaint(
                painter: _RipplePainter(
                  t: _clock.value * 4,
                  level: _smoothed,
                  state: widget.state,
                  from: ring / 2,
                ),
                child: Center(
                  child: Container(
                    // The one ring. It widens a little while a voice is active
                    // and otherwise sits still.
                    width: ring + _smoothed * 6,
                    height: ring + _smoothed * 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF8E7BF0)
                            .withValues(alpha: active ? 0.30 : 0.18),
                        width: 1.6,
                      ),
                    ),
                    child: Center(
                      child: AnimatedScale(
                        scale: _down ? 0.94 : 1,
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        child: Container(
                          width: widget.size,
                          height: widget.size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: const Color(0xFFB07BE8)
                                    .withValues(alpha: 0.30 + _smoothed * 0.16),
                                blurRadius: 24 + _smoothed * 10,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Stack(
                              alignment: Alignment.center,
                              children: <Widget>[
                                // The orb's own colour field, faceless — so the
                                // button cannot drift out of step with the
                                // assistant's colours. Painted slightly larger
                                // than the circle because the orb keeps a halo
                                // margin inside its box.
                                OverflowBox(
                                  maxWidth: widget.size / 0.86,
                                  maxHeight: widget.size / 0.86,
                                  child: CustomPaint(
                                    size: Size.square(widget.size / 0.86),
                                    painter: OrbPainter(
                                      frame: _fieldFrame(_clock.value * 4),
                                      quality: OrbQuality.balanced,
                                      showFace: false,
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _ShinePainter(
                                      phase: _clock.value,
                                      level: _smoothed,
                                    ),
                                  ),
                                ),
                                _Inside(
                                  state: widget.state,
                                  level: _smoothed,
                                  t: _clock.value * 4,
                                  size: widget.size,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A still orb, drifting slowly. Time is the only thing that moves: the colour
/// clouds wander, exactly as they do on the big orb.
OrbFrame _fieldFrame(double t) => OrbFrame(
  time: t,
  scale: 1,
  sway: Offset.zero,
  tilt: math.sin(t * 0.12) * 0.25,
  hop: 0,
  squash: 0,
  lift: 0,
  leftEyeOpen: 0,
  rightEyeOpen: 0,
  eyeWide: 0,
  squint: 0,
  gaze: Offset.zero,
  mouthOpen: 0,
  mouthWidth: 1,
  smile: 0,
  smirk: 0,
  warmth: 0,
  halo: 0,
);

/// What the circle shows: the mic when idle, and a small waveform whenever
/// there is a voice — quick and spiky while the user talks, slow and even
/// while the assistant answers.
class _Inside extends StatelessWidget {
  const _Inside({
    required this.state,
    required this.level,
    required this.t,
    required this.size,
  });

  final VoiceState state;
  final double level;
  final double t;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (state == VoiceState.idle) {
      return Icon(Icons.mic_rounded, color: Colors.white, size: size * 0.36);
    }
    return SizedBox(
      width: size * 0.46,
      height: size * 0.40,
      child: CustomPaint(
        painter: _WavePainter(state: state, level: level, t: t),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.state, required this.level, required this.t});

  final VoiceState state;
  final double level;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const int bars = 5;
    final double slot = size.width / bars;
    final Paint paint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = slot * 0.42;

    // Speed and spread are what separate the two voices: the user's speech is
    // quick and uneven, the assistant's is slower and more regular.
    final double speed = state == VoiceState.speaking ? 4.2 : 8.0;
    final double spread = state == VoiceState.speaking ? 0.55 : 0.9;
    final double floor = state == VoiceState.thinking ? 0.12 : 0.22;

    for (int i = 0; i < bars; i++) {
      final double phase = (i - (bars - 1) / 2) * spread;
      final double wobble = math.sin(t * speed + phase);
      final double centreBias = 1 - (phase.abs() / (bars * spread / 2)) * 0.35;
      final double amount = state == VoiceState.thinking
          ? floor + 0.10 * (0.5 + 0.5 * wobble)
          : floor + (0.78 * level + 0.18) * wobble.abs() * centreBias;
      final double h = (size.height * amount).clamp(
        paint.strokeWidth,
        size.height,
      );
      final double x = slot * i + slot / 2;
      canvas.drawLine(
        Offset(x, size.height / 2 - h / 2),
        Offset(x, size.height / 2 + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.t != t || old.level != level || old.state != state;
}

/// Waves leaving the mic.
///
/// Each ring starts at the button's rim, travels outwards and fades. They are
/// deliberately thin and few: the point is a sense of sound spreading, not a
/// light show. Idle keeps one slow wave going so the button never looks dead;
/// speech makes them quicker, wider and brighter.
class _RipplePainter extends CustomPainter {
  _RipplePainter({
    required this.t,
    required this.level,
    required this.state,
    required this.from,
  });

  final double t;
  final double level;
  final VoiceState state;

  /// Radius the waves are born at — the outer ring of the button.
  final double from;

  static const Color _brand = Color(0xFF8E7BF0);
  static const Color _pink = Color(0xFFE879C0);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);

    final (double speed, double strength, double reach) = switch (state) {
      VoiceState.idle => (0.34, 0.16, 0.55),
      VoiceState.listening => (0.62, 0.30 + level * 0.28, 0.85 + level * 0.45),
      VoiceState.thinking => (0.40, 0.14, 0.50),
      VoiceState.speaking => (0.46, 0.24 + level * 0.20, 0.70 + level * 0.30),
    };

    final double travel = from * reach;

    for (int i = 0; i < 3; i++) {
      final double phase = (t * speed + i / 3) % 1.0;
      // Fade on a curve rather than linearly, so a wave thins out early and
      // spends its last stretch almost invisible.
      final double fade = (1 - phase) * (1 - phase) * strength;
      if (fade < 0.004) continue;
      canvas.drawCircle(
        c,
        from + phase * travel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * (1 - phase) + 0.4
          ..color = Color.lerp(_brand, _pink, phase)!.withValues(alpha: fade),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.t != t || old.level != level || old.state != state;
}

/// The gloss: a soft highlight in the top left that is always there, and a
/// band of light that sweeps across every few seconds — enough to catch the
/// eye and suggest the button is worth pressing.
class _ShinePainter extends CustomPainter {
  _ShinePainter({required this.phase, required this.level});

  /// 0..1, one turn of the button's clock (four seconds).
  final double phase;
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // Standing highlight — the button reads as a glassy bead even at rest.
    canvas.drawCircle(
      Offset(size.width * 0.32, size.height * 0.26),
      size.width * 0.38,
      Paint()
        ..shader =
            RadialGradient(
              colors: <Color>[
                Colors.white.withValues(alpha: 0.18),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: Offset(size.width * 0.34, size.height * 0.28),
                radius: size.width * 0.46,
              ),
            ),
    );

    // The sweep: a quarter of each cycle, eased, so most of the time nothing
    // happens and then light crosses the face of it.
    const double window = 0.26;
    if (phase > window) return;
    final double p = Curves.easeInOutSine.transform(phase / window);
    final double centre = -0.25 + p * 1.5;
    final double strength = 0.42 + level * 0.18;

    double stop(double v) => v.clamp(0.0, 1.0);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: strength),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
          ],
          stops: <double>[
            0,
            stop(centre - 0.16),
            stop(centre),
            stop(centre + 0.16),
            1,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ShinePainter old) =>
      old.phase != phase || old.level != level;
}
