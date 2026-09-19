import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

/// The soft colour smudge under the orb — the orb's light bouncing off the
/// page. Painted as three blurred gradients rather than a mirrored copy of the
/// orb, so it costs nothing per frame.
class OrbReflection extends StatelessWidget {
  const OrbReflection({super.key, required this.width, this.opacity = 1});

  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: SizedBox(
          width: width,
          height: width * 0.30,
          child: CustomPaint(painter: _ReflectionPainter()),
        ),
      ),
    );
  }
}

class _ReflectionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    void smudge(Color color, double cx, double cy, double rx, double ry,
        double alpha) {
      final Rect rect = Rect.fromCenter(
        center: Offset(size.width * cx, size.height * cy),
        width: size.width * rx,
        height: size.height * ry,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
            stops: const <double>[0.08, 1.0],
          ).createShader(rect),
      );
    }

    smudge(AppColors.reflectViolet, 0.66, 0.38, 0.72, 1.20, 0.26);
    smudge(AppColors.reflectPink, 0.44, 0.36, 0.82, 1.15, 0.30);
    smudge(AppColors.reflectOrange, 0.36, 0.52, 0.48, 0.90, 0.24);
  }

  @override
  bool shouldRepaint(_ReflectionPainter oldDelegate) => false;
}
