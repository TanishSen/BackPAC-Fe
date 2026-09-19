import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../voice_controller.dart';

/// The soft bloom of colour behind the mic.
///
/// It is the app's main piece of feedback: calm when nothing is happening,
/// blushing pink and breathing with the voice while the user talks, and
/// running a slow wave through itself while the assistant answers.
class VoiceAura extends StatefulWidget {
  const VoiceAura({
    super.key,
    required this.state,
    required this.level,
    this.height = 300,
  });

  final VoiceState state;

  /// Live loudness, 0..1.
  final ValueListenable<double> level;
  final double height;

  @override
  State<VoiceAura> createState() => _VoiceAuraState();
}

class _VoiceAuraState extends State<VoiceAura>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  /// Loudness, smoothed. Raw amplitude makes the bloom flicker; this is what
  /// turns it into a swell.
  double _smoothed = 0;

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_clock, widget.level]),
          builder: (BuildContext context, _) {
            final double target = widget.level.value;
            _smoothed += (target - _smoothed) * 0.18;
            return CustomPaint(
              painter: _AuraPainter(
                t: _clock.value * 12,
                level: _smoothed,
                state: widget.state,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AuraPainter extends CustomPainter {
  _AuraPainter({required this.t, required this.level, required this.state});

  final double t;
  final double level;
  final VoiceState state;

  static const Color _pink = Color(0xFFF07EC8);
  static const Color _violet = Color(0xFF8F7BE8);
  static const Color _peach = Color(0xFFF7B48A);
  static const Color _rose = Color(0xFFEF6E8C);

  @override
  void paint(Canvas canvas, Size size) {
    // Everything is anchored to the bottom centre: the colour rises out of the
    // mic rather than floating on the page.
    final Offset root = Offset(size.width / 2, size.height + 20);

    final double energy = switch (state) {
      VoiceState.idle => 0.46,
      VoiceState.listening => 0.72 + level * 0.28,
      VoiceState.thinking => 0.52,
      VoiceState.speaking => 0.64 + level * 0.22,
    };

    // While the assistant talks, a wave travels through the bloom; while the
    // user talks, it swells in place.
    final double travel =
        state == VoiceState.speaking ? math.sin(t * 1.9) * 0.28 : 0;

    void bloom(Color color, double dx, double dy, double rx, double ry,
        double alpha, double phase) {
      final double drift = math.sin(t * 0.55 + phase);
      final Offset c = Offset(
        root.dx + (dx + drift * 0.05 + travel) * size.width,
        root.dy + dy * size.height,
      );
      final double w = rx * size.width * (1 + level * 0.12);
      final double h = ry * size.height * (1 + level * 0.16);
      final Rect rect = Rect.fromCenter(center: c, width: w * 2, height: h * 2);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              color.withValues(alpha: alpha * energy),
              color.withValues(alpha: 0),
            ],
            stops: const <double>[0.0, 1.0],
          ).createShader(rect),
      );
    }

    bloom(_violet, -0.30, -0.10, 0.52, 0.72, 0.30, 0.0);
    bloom(_pink, 0.02, -0.16, 0.58, 0.86, 0.34, 1.7);
    bloom(_rose, 0.28, -0.06, 0.44, 0.62, 0.26, 3.1);
    bloom(_peach, -0.12, 0.02, 0.36, 0.46, 0.24, 4.6);

    // A brighter core right under the button while a voice is active.
    if (state != VoiceState.idle) {
      final Rect core = Rect.fromCircle(
        center: Offset(root.dx, root.dy - size.height * 0.30),
        radius: size.width * (0.20 + level * 0.06),
      );
      canvas.drawOval(
        core,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              Colors.white.withValues(alpha: 0.30 * energy),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(core),
      );
    }
  }

  @override
  bool shouldRepaint(_AuraPainter old) =>
      old.t != t || old.level != level || old.state != state;
}
