import 'dart:ui';

/// One soft colour cloud inside the orb.
///
/// Every coordinate here is in *unit space*: the orb is a circle of radius 1
/// centred on `Offset.zero`, so `center` runs roughly -1..1 and `radius` is a
/// fraction of the orb radius. The painter scales unit space to pixels, which
/// is what lets the same numbers drive a 48 px avatar and a 320 px hero.
class OrbBlob {
  const OrbBlob({
    required this.color,
    required this.center,
    required this.radius,
    this.squash = 1.0,
    this.drift = const Offset(0.02, 0.02),
    this.period = 13.0,
    this.phase = 0.0,
    this.core = 0.35,
    this.opacity = 1.0,
    this.warmResponse = 0.0,
  });

  /// Colour at the centre of the cloud; it fades to fully transparent at the rim.
  final Color color;
  final Offset center;
  final double radius;

  /// Vertical radius = [radius] * [squash].
  final double squash;

  /// How far the cloud wanders from [center], in unit space.
  final Offset drift;

  /// Seconds for one full wander cycle. Deliberately co-prime-ish across the
  /// palette so the whole field never visibly repeats.
  final double period;
  final double phase;

  /// Fraction of the radius that stays at full colour before the falloff
  /// begins. Higher = a more solid, defined cloud.
  final double core;
  final double opacity;

  /// How much this cloud brightens while the orb speaks (0 = not at all).
  /// The warm clouds near the mouth use this so light appears to spill out of it.
  final double warmResponse;
}

/// The reference artwork, decomposed into clouds: white-pink at the top left,
/// magenta through the middle, orange low-left, violet down the right side.
class OrbPalette {
  const OrbPalette({
    required this.base,
    required this.blobs,
    required this.halo,
    required this.eye,
    required this.mouthLip,
    required this.mouthMid,
    required this.mouthDeep,
  });

  final Color base;
  final List<OrbBlob> blobs;
  final Color halo;
  final Color eye;

  /// Mouth gradient, top to bottom: bright lip, warm middle, deep throat.
  final Color mouthLip;
  final Color mouthMid;
  final Color mouthDeep;

  static const OrbPalette rezolve = OrbPalette(
    base: Color(0xFFF2AED6),
    halo: Color(0xFFE86FC0),
    eye: Color(0xFFFFFFFF),
    mouthLip: Color(0xFFFFCE9B),
    mouthMid: Color(0xFFFF8A45),
    mouthDeep: Color(0xFFE8551F),
    blobs: <OrbBlob>[
      // The reference reads as a ring of hues around a magenta heart:
      // near-white at the top left, orange at the lower left, coral across the
      // bottom, pink to the lower right, violet down the right edge,
      // periwinkle at the top right. The ring is laid down first, the magenta
      // heart over it, and the bright corner highlight last.
      //
      // 'core' is the fraction of a cloud that stays at full colour before it
      // fades — the main lever on how saturated and defined the orb looks.
      OrbBlob(
        color: Color(0xFFBFA8F2), // periwinkle, top right
        center: Offset(0.70, -0.46),
        radius: 0.56,
        drift: Offset(0.028, 0.022),
        period: 17.0,
        core: 0.55,
      ),
      OrbBlob(
        color: Color(0xFFC9B4F5), // lavender, top
        center: Offset(0.30, -0.80),
        radius: 0.50,
        squash: 0.92,
        drift: Offset(0.024, 0.020),
        period: 25.0,
        phase: 1.7,
        core: 0.50,
      ),
      OrbBlob(
        color: Color(0xFF6A5FDB), // violet, right edge
        center: Offset(0.84, 0.06),
        radius: 0.63,
        squash: 1.18,
        drift: Offset(0.026, 0.032),
        period: 21.0,
        phase: 2.4,
        core: 0.50,
      ),
      OrbBlob(
        color: Color(0xFFE164B8), // pink, lower right
        center: Offset(0.56, 0.56),
        radius: 0.60,
        drift: Offset(0.026, 0.028),
        period: 15.0,
        phase: 1.2,
        core: 0.50,
      ),
      OrbBlob(
        color: Color(0xFFFB6A86), // coral, bottom
        center: Offset(-0.02, 0.80),
        radius: 0.58,
        squash: 0.82,
        drift: Offset(0.024, 0.020),
        period: 18.0,
        phase: 2.9,
        core: 0.50,
        warmResponse: 0.26,
      ),
      OrbBlob(
        color: Color(0xFFFF9350), // orange, lower left — the warmest point
        center: Offset(-0.50, 0.56),
        radius: 0.68,
        squash: 0.94,
        drift: Offset(0.026, 0.024),
        period: 16.0,
        phase: 0.9,
        core: 0.55,
        warmResponse: 0.32,
      ),
      OrbBlob(
        color: Color(0xFFFCC2E2), // soft pink, left
        center: Offset(-0.82, -0.04),
        radius: 0.58,
        squash: 1.04,
        drift: Offset(0.022, 0.026),
        period: 12.0,
        phase: 4.7,
        core: 0.50,
      ),
      OrbBlob(
        color: Color(0xFFFFF4FA), // near-white, top left
        center: Offset(-0.48, -0.50),
        radius: 0.74,
        squash: 0.96,
        drift: Offset(0.028, 0.024),
        period: 19.0,
        phase: 4.1,
        core: 0.52,
      ),
      OrbBlob(
        color: Color(0xFFE8189F), // the magenta heart
        center: Offset(-0.10, 0.04),
        radius: 0.62,
        squash: 1.06,
        drift: Offset(0.032, 0.030),
        period: 23.0,
        phase: 3.3,
        core: 0.38,
      ),
      OrbBlob(
        color: Color(0xFFCE1093), // its deepest point, just left of centre
        center: Offset(-0.26, 0.12),
        radius: 0.40,
        squash: 1.08,
        drift: Offset(0.028, 0.024),
        period: 14.0,
        phase: 5.6,
        core: 0.30,
      ),
      OrbBlob(
        color: Color(0xFFFFF6FB), // the bright corner the reference opens with
        center: Offset(-0.58, -0.60),
        radius: 0.36,
        squash: 0.98,
        drift: Offset(0.018, 0.016),
        period: 27.0,
        phase: 0.4,
        core: 0.28,
        opacity: 0.88,
      ),
    ],
  );
}
