import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'orb_expression.dart';
import 'orb_motion.dart';
import 'orb_palette.dart';

/// How much work the painter is allowed to do per frame.
enum OrbQuality {
  /// Full blur pass melting the colour clouds together, plus eye bloom and
  /// mouth glow. Comfortably 60 fps on a modern phone.
  high,

  /// Halves the blur. Right for avatars in a list.
  balanced,

  /// Gradients only, no layer blur. For tiny sizes or old hardware.
  low,
}

/// Paints one [OrbFrame]. Stateless with respect to time: hand it the same
/// frame twice and you get the same pixels, which is what makes golden tests
/// and scrubbing possible.
class OrbPainter extends CustomPainter {
  OrbPainter({
    required this.frame,
    this.palette = OrbPalette.rezolve,
    this.quality = OrbQuality.high,
    this.showFace = true,
  });

  final OrbFrame frame;
  final OrbPalette palette;
  final OrbQuality quality;

  /// False paints the colour field alone, no eyes and no mouth. The mic button
  /// uses this so its fill is literally the orb, not an approximation of it.
  final bool showFace;

  // Geometry of the face, in unit space (orb radius = 1).
  static const double _eyeX = 0.225;
  static const double _eyeY = -0.225;
  static const double _eyeW = 0.235;
  static const double _eyeH = 0.335;
  static const double _mouthY = 0.300;
  static const double _mouthW = 0.46;
  static const double _mouthH = 0.30;

  /// Ball diameter as a fraction of the widget box. The remainder is the halo.
  static const double _ballFraction = 0.86;

  @override
  void paint(Canvas canvas, Size size) {
    // The ball is sized by the box's width; any extra height is headroom for
    // hops, so the ball rests on the bottom of the box rather than centring.
    final r = size.width / 2;
    if (r <= 0) return;
    final bodyR = r * _ballFraction * frame.scale;
    final floor = Offset(size.width / 2, size.height - r);

    canvas.save();
    canvas.translate(
      floor.dx + frame.sway.dx * bodyR,
      floor.dy + (frame.sway.dy + frame.hop) * bodyR,
    );

    // Squash and stretch, anchored on the bottom of the ball: a landing
    // flattens onto the floor instead of shrinking towards its middle.
    final squash = frame.squash;
    if (squash.abs() > 0.001) {
      canvas.translate(0, bodyR);
      canvas.scale(1 + 0.34 * squash, 1 - 0.34 * squash);
      canvas.translate(0, -bodyR);
    }

    _paintHalo(canvas, bodyR);

    canvas.save();
    canvas.rotate(frame.tilt); // only the colour field turns, not the face
    _paintBody(canvas, bodyR);
    canvas.restore();

    if (showFace) {
      _paintMouth(canvas, bodyR);
      _paintEyes(canvas, bodyR);
    }

    canvas.restore();
  }

  // ---------------------------------------------------------------- body ----

  void _paintHalo(Canvas canvas, double r) {
    final h = frame.halo;
    if (h <= 0.01) return;
    // The widget box edge: the halo fades to nothing exactly there.
    final double haloR = r;
    canvas.drawCircle(
      Offset.zero,
      haloR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          haloR,
          <Color>[
            palette.halo.withValues(alpha: 0.16 * h),
            palette.halo.withValues(alpha: 0.10 * h),
            palette.halo.withValues(alpha: 0),
          ],
          <double>[0.52, 0.74, 1.0],
        )
        ..blendMode = BlendMode.srcOver,
    );
    // A warmer second bloom low down, so speech light leaks out of the orb.
    if (frame.warmth > 0.02) {
      canvas.drawCircle(
        Offset(0, r * 0.26),
        r * 0.70,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(0, r * 0.26),
            r * 0.70,
            <Color>[
              palette.mouthMid.withValues(alpha: 0.20 * frame.warmth),
              palette.mouthMid.withValues(alpha: 0),
            ],
            <double>[0.35, 1.0],
          ),
      );
    }
  }

  void _paintBody(Canvas canvas, double r) {
    // The layer is a little larger than the ball, and the ball is clipped to a
    // real circle inside it. Both matter: a blob cut by the layer's own square
    // clip leaves a straight colour edge, and a fade rect whose antialiased
    // border lands on that clip leaves a faint square outline around the orb.
    final bounds = Rect.fromCircle(center: Offset.zero, radius: r * 1.06);
    final circle = Rect.fromCircle(center: Offset.zero, radius: r);
    final sigma = switch (quality) {
      OrbQuality.high => r * 0.012,
      OrbQuality.balanced => r * 0.009,
      OrbQuality.low => 0.0,
    };

    canvas.saveLayer(
      bounds,
      Paint()
        ..imageFilter =
            sigma > 0 ? ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma) : null,
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(circle), doAntiAlias: true);
    canvas.drawCircle(Offset.zero, r, Paint()..color = palette.base);

    for (final blob in palette.blobs) {
      final w = 2 * math.pi * (frame.time / blob.period) + blob.phase;
      final c = Offset(
        (blob.center.dx + math.sin(w) * blob.drift.dx) * r,
        (blob.center.dy + math.cos(w * 0.83) * blob.drift.dy) * r,
      );
      final rx = blob.radius * r;
      final ry = blob.radius * blob.squash * r;
      final rect = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);

      var color = blob.color;
      if (blob.warmResponse > 0 && frame.warmth > 0) {
        // Clouds near the mouth catch the light coming out of it.
        color = Color.lerp(
          color,
          palette.mouthLip,
          blob.warmResponse * frame.warmth,
        )!;
      }

      canvas.drawOval(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            rx,
            <Color>[
              color.withValues(alpha: blob.opacity),
              color.withValues(alpha: blob.opacity * 0.86),
              color.withValues(alpha: 0),
            ],
            <double>[0.0, blob.core, 1.0],
            TileMode.clamp,
            (Matrix4.identity()
                  ..translateByDouble(c.dx, c.dy, 0, 1)
                  ..scaleByDouble(1, ry / rx, 1, 1)
                  ..translateByDouble(-c.dx, -c.dy, 0, 1))
                .storage,
          ),
      );
    }

    canvas.restore(); // end of the circular clip

    // Feather the rim: alpha falls to zero just inside the edge, which is what
    // gives the reference its soft, lit-from-within silhouette. The rect is
    // deliberately bigger than the layer so its own edge is never visible.
    canvas.drawRect(
      bounds.inflate(r * 0.5),
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.radial(
          Offset.zero,
          r,
          <Color>[
            const Color(0xFFFFFFFF),
            const Color(0xFFFFFFFF),
            const Color(0x00FFFFFF),
          ],
          <double>[0.0, 0.955, 1.0],
        ),
    );

    canvas.restore();

  }

  // ---------------------------------------------------------------- eyes ----

  void _paintEyes(Canvas canvas, double r) {
    final gaze = Offset(frame.gaze.dx * 0.085, frame.gaze.dy * 0.062);
    _paintEye(canvas, r, gaze, -1, frame.leftEyeOpen);
    _paintEye(canvas, r, gaze, 1, frame.rightEyeOpen);
  }

  void _paintEye(Canvas canvas, double r, Offset gaze, int side, double open) {
    final o = open.clamp(0.0, 1.3);
    final w = _eyeW * (1 + frame.eyeWide * 0.10) * r;
    final maxH = _eyeH * (1 + frame.eyeWide * 0.16) * r;
    const minH = 0.042;
    final h = math.max(maxH * o, minH * r);

    // The lid comes down from the top: the bottom edge of the eye stays put.
    final bottom = (_eyeY + gaze.dy) * r + maxH / 2;
    final cx = (side * _eyeX + gaze.dx) * r;
    final cy = bottom - h / 2;

    final notch = 0.30 * (o * o); // the little dip in the base, fades as it shuts
    final bow = (1 - o.clamp(0.0, 1.0)) * 0.30 - frame.squint * 0.46;

    final path = _eyePath(Offset(cx, cy), w, h, notch, bow);

    // Bloom first, crisp shape over it — the eyes in the reference glow a little.
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.eye.withValues(alpha: 0.34)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.045),
    );
    canvas.drawPath(path, Paint()..color = palette.eye);
  }

  /// The reference eye: a rounded arch with a soft dip in its base.
  ///
  /// [notch] is how deep that dip is, [bow] bends the whole shape — positive
  /// pushes the middle down (a closing lid), negative lifts it (a happy squint).
  Path _eyePath(Offset c, double w, double h, double notch, double bow) {
    final hw = w / 2;
    final hh = h / 2;
    final m = bow * h.clamp(w * 0.35, double.infinity);
    return Path()
      ..moveTo(c.dx - hw, c.dy + hh)
      ..cubicTo(
        c.dx - hw, c.dy - hh * 0.25 + m * 0.5,
        c.dx - hw * 0.52, c.dy - hh + m,
        c.dx, c.dy - hh + m,
      )
      ..cubicTo(
        c.dx + hw * 0.52, c.dy - hh + m,
        c.dx + hw, c.dy - hh * 0.25 + m * 0.5,
        c.dx + hw, c.dy + hh,
      )
      ..quadraticBezierTo(
        c.dx, c.dy + hh - h * notch + m,
        c.dx - hw, c.dy + hh,
      )
      ..close();
  }

  // --------------------------------------------------------------- mouth ----

  void _paintMouth(Canvas canvas, double r) {
    final open = frame.mouthOpen;
    final smile = frame.smile;
    final smirk = frame.smirk;
    final visible = smoothstep(0.02, 0.16, open);

    final cx = frame.gaze.dx * 0.020 * r;
    final cy = (_mouthY + open * 0.010 + frame.gaze.dy * 0.014) * r;

    canvas.save();
    // A smirk tips the whole mouth, not just one corner.
    if (smirk.abs() > 0.001) {
      canvas.translate(cx, cy);
      canvas.rotate(smirk * 0.085);
      canvas.translate(-cx, -cy);
    }

    if (visible < 1) _paintClosedSmile(canvas, r, cx, cy, 1 - visible);

    if (visible > 0.01) {
      final w = _mouthW * frame.mouthWidth * (0.82 + 0.30 * open) * r;
      final h = _mouthH * open * r;
      final hw = w / 2;

      // Corners ride up with the smile; a smirk lifts one of them further.
      final lift = smile * 0.055 * r;
      final leftY = cy - lift - math.max(0.0, -smirk) * 0.035 * r;
      final rightY = cy - lift - math.max(0.0, smirk) * 0.035 * r;

      final path = Path()
        ..moveTo(cx - hw, leftY)
        // Upper lip: a shallow bow, so the opening has a real top edge.
        ..cubicTo(cx - hw * 0.52, cy + h * 0.10, cx + hw * 0.52, cy + h * 0.10,
            cx + hw, rightY)
        // Lower lip: one deep, smooth arc.
        ..cubicTo(cx + hw * 0.80, cy + h * 1.18, cx - hw * 0.80, cy + h * 1.18,
            cx - hw, leftY)
        ..close();

      _paintAperture(canvas, r, path, open, visible, cy, h, hw, cx);
    }

    canvas.restore();
  }

  /// Mouth shut: a warm crescent rather than a drawn-on line. This is what the
  /// orb wears at rest, so it has to be subtle.
  void _paintClosedSmile(
      Canvas canvas, double r, double cx, double cy, double weight) {
    final a = frame.smile * weight * 0.78;
    if (a <= 0.01) return;
    final w = _mouthW * 0.78 * r;
    final bend = 0.055 * r * (0.5 + frame.smile);
    final path = Path()
      ..moveTo(cx - w / 2, cy - 0.012 * r)
      ..quadraticBezierTo(cx, cy + bend, cx + w / 2, cy - 0.012 * r);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.034
        ..shader = ui.Gradient.linear(
          Offset(cx - w / 2, cy),
          Offset(cx + w / 2, cy),
          <Color>[
            palette.mouthMid.withValues(alpha: a * 0.75),
            palette.mouthLip.withValues(alpha: a),
            palette.mouthMid.withValues(alpha: a * 0.75),
          ],
          <double>[0.0, 0.5, 1.0],
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.014),
    );
  }

  /// The open mouth: glow, lit interior, shadowed roof, tongue, lip rim.
  void _paintAperture(Canvas canvas, double r, Path path, double open,
      double visible, double cy, double h, double hw, double cx) {
    final Rect bounds = path.getBounds();

    // Light spilling out of the opening.
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.mouthMid.withValues(alpha: 0.44 * visible)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.075),
    );

    final Paint fill = Paint()
      ..shader = ui.Gradient.linear(
        Offset(bounds.center.dx, bounds.top),
        Offset(bounds.center.dx, bounds.bottom),
        <Color>[
          palette.mouthDeep.withValues(alpha: visible),
          palette.mouthMid.withValues(alpha: visible),
          palette.mouthLip.withValues(alpha: visible),
        ],
        <double>[0.0, 0.46, 1.0],
      );
    canvas.drawPath(path, fill);
    // Stroking the same path with a round join softens the two corners, which
    // otherwise come to a point and read as a beak.
    canvas.drawPath(
      path,
      Paint()
        ..shader = fill.shader
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = r * 0.016,
    );

    canvas.save();
    canvas.clipPath(path);

    // The roof of the mouth falls into shadow: this is what turns a flat
    // orange shape into an opening with depth.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(bounds.center.dx, bounds.top - h * 0.08),
          Offset(bounds.center.dx, bounds.top + bounds.height * 0.46),
          <Color>[
            const Color(0xFF8A2E08).withValues(alpha: 0.30 * visible),
            const Color(0x006E1F04),
          ],
        ),
    );

    // A tongue, once the mouth is properly open. It is what keeps a wide
    // "aah" from looking like a hole cut in the orb.
    final tongue = smoothstep(0.58, 0.92, open) * visible;
    if (tongue > 0.01) {
      final Rect t = Rect.fromCenter(
        center: Offset(cx, cy + h * 1.02),
        width: hw * 1.02,
        height: h * 0.66,
      );
      canvas.drawOval(
        t,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(t.center.dx, t.top + t.height * 0.3),
            t.width * 0.62,
            <Color>[
              const Color(0xFFFF7E92).withValues(alpha: 0.85 * tongue),
              const Color(0xFFE8556F).withValues(alpha: 0.85 * tongue),
            ],
          ),
      );
    }
    canvas.restore();

    // Bright rim along the lower lip — the detail that makes it read as an
    // opening with a lip rather than a flat shape.
    final Path lip = Path()
      ..moveTo(cx - hw * 0.90, cy + h * 0.16)
      ..quadraticBezierTo(cx, cy + h * 1.30, cx + hw * 0.90, cy + h * 0.16);
    canvas.drawPath(
      lip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.016 * (0.6 + 0.4 * open)
        ..color = palette.mouthLip.withValues(alpha: 0.6 * visible)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.010),
    );
  }

  @override
  bool shouldRepaint(OrbPainter old) =>
      old.frame != frame ||
      old.palette != palette ||
      old.quality != quality ||
      old.showFace != showFace;
}
