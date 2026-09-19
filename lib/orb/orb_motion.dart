import 'dart:math' as math;
import 'dart:ui';

/// Smooth, deterministic value noise in one dimension.
///
/// Everything organic in the orb — the drift of the colour clouds, the wander
/// of the gaze, the rise and fall of speech — is driven from this rather than
/// from `Random`, so motion is continuous instead of jumping frame to frame,
/// and identical on every device and every run.
double _hash(double n) {
  final x = math.sin(n * 127.1) * 43758.5453123;
  return x - x.floorToDouble();
}

/// Value noise, 0..1, with a smoothstep between integer samples.
double noise1(double x) {
  final i = x.floorToDouble();
  final f = x - i;
  final u = f * f * (3 - 2 * f);
  return _hash(i) * (1 - u) + _hash(i + 1) * u;
}

/// Two octaves of [noise1] — enough shape to feel alive, cheap enough to call
/// a handful of times a frame.
double fbm(double x) => noise1(x) * 0.65 + noise1(x * 2.17 + 11.3) * 0.35;

/// Signed version, -1..1.
double sbm(double x) => fbm(x) * 2 - 1;

double smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double lerp(double a, double b, double t) => a + (b - a) * t;

/// A critically-damped spring. Every value the face exposes is filtered
/// through one of these, which is what makes the animation impossible to
/// make jerky: even an instant state change arrives as a smooth ease, and a
/// jittery external amplitude (a live mic level, say) comes out soft.
class Spring {
  Spring({required this.stiffness, double? damping, double initial = 0})
      : damping = damping ?? 2 * math.sqrt(stiffness),
        _value = initial,
        _target = initial;

  final double stiffness;
  final double damping;
  double _value;
  double _velocity = 0;
  double _target;

  double get value => _value;
  set target(double t) => _target = t;

  /// Sub-stepped so a dropped frame (a long `dt`) can never make it explode.
  void step(double dt, double target) {
    _target = target;
    var remaining = dt;
    const maxStep = 1 / 120;
    while (remaining > 0) {
      final h = remaining < maxStep ? remaining : maxStep;
      final accel = stiffness * (_target - _value) - damping * _velocity;
      _velocity += accel * h;
      _value += _velocity * h;
      remaining -= h;
    }
  }

  /// Advance towards whatever target was last set, without restating it.
  void stepToTarget(double dt) => step(dt, _target);

  void snapTo(double v) {
    _value = v;
    _target = v;
    _velocity = 0;
  }
}

/// A spring over a point, for gaze and sway.
class Spring2 {
  Spring2({required double stiffness})
      : x = Spring(stiffness: stiffness),
        y = Spring(stiffness: stiffness);

  final Spring x;
  final Spring y;

  Offset get value => Offset(x.value, y.value);

  void step(double dt, Offset target) {
    x.step(dt, target.dx);
    y.step(dt, target.dy);
  }

  /// Advance towards the per-axis targets already set.
  void settle(double dt) {
    x.stepToTarget(dt);
    y.stepToTarget(dt);
  }
}
