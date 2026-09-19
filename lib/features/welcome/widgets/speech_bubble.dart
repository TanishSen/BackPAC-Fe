import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

/// The little white "Hello!" bubble, with a tail that points down and to the
/// right, towards the orb.
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Assistant says $text',
      child: CustomPaint(
        painter: _BubblePainter(),
        child: Padding(
          // The extra room at the bottom is the tail's.
          padding: const EdgeInsets.fromLTRB(20, 13, 20, 29),
          // The line changes when the orb is poked, so the bubble resizes and
          // cross-fades rather than snapping to the new words.
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(text, key: ValueKey<String>(text), style: AppText.bubble),
            ),
          ),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  static const double _tail = 16;
  static const double _radius = AppSpacing.bubbleRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect body = Rect.fromLTWH(0, 0, size.width, size.height - _tail);
    final Path path = Path()
      ..addRRect(
          RRect.fromRectAndRadius(body, const Radius.circular(_radius)));

    // Tail: a soft, slightly curved point rather than a hard triangle.
    final double x = size.width * 0.70;
    path
      ..moveTo(x - 13, body.bottom - 1)
      ..quadraticBezierTo(
          x - 2, body.bottom + _tail * 0.72, x + 11, body.bottom + _tail)
      ..quadraticBezierTo(
          x + 9, body.bottom - 1.5, x + 20, body.bottom - 1)
      ..close();

    canvas.drawShadow(path, const Color(0x33262046), 8, true);
    canvas.drawPath(path, Paint()..color = AppColors.surface);
  }

  @override
  bool shouldRepaint(_BubblePainter oldDelegate) => false;
}
