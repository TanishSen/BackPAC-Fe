import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The little icon tiles from the design: a rounded square in a colour, with a
/// second, lighter one peeking out behind its top-right corner.
///
/// The offset layer is what gives them their sticker-like depth — without it
/// they read as flat swatches.
class StickerIcon extends StatelessWidget {
  const StickerIcon({
    super.key,
    required this.icon,
    required this.tint,
    this.size = 46,
    this.iconSize,
  });

  final IconData icon;
  final Color tint;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final double radius = size * 0.31;
    final Color light = Color.lerp(tint, Colors.white, 0.42)!;

    return SizedBox(
      width: size * 1.16,
      height: size * 1.16,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // The layer behind, tipped a little so a corner shows.
          Positioned(
            right: 0,
            top: 0,
            child: Transform.rotate(
              angle: math.pi / 14,
              child: Container(
                width: size * 0.82,
                height: size * 0.82,
                decoration: BoxDecoration(
                  color: light.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(radius * 0.8),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[light, tint],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(radius),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: tint.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: iconSize ?? size * 0.46,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
