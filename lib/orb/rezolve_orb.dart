import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'orb_expression.dart';
import 'orb_painter.dart';
import 'orb_palette.dart';

export 'orb_expression.dart' show OrbMood, OrbFrame, OrbAntic;
export 'orb_painter.dart' show OrbQuality;
export 'orb_palette.dart' show OrbPalette, OrbBlob;

/// Handle for making the orb do something on cue.
///
/// ```dart
/// final orb = RezolveOrbController();
/// ...
/// RezolveOrb(controller: orb)
/// ...
/// orb.play(OrbAntic.wink);
/// ```
class RezolveOrbController {
  OrbChoreographer? _choreo;

  /// The frame the orb is currently drawing. Listen to it if something else on
  /// screen should react — a shadow that shrinks as the orb leaves the floor,
  /// say. Updated every frame, so keep the listener cheap.
  final ValueNotifier<OrbFrame> frames =
      ValueNotifier<OrbFrame>(OrbFrame.rest);

  void _attach(OrbChoreographer c) => _choreo = c;
  void _detach(OrbChoreographer c) {
    if (identical(_choreo, c)) _choreo = null;
  }

  /// Bounce, grin, and look at [where] — the same reaction a tap produces.
  /// [where] is in the orb's own space: (0, 0) is the middle, (-1, -1) the top
  /// left corner.
  void poke([Offset where = Offset.zero]) => _choreo?.poke(where);

  /// Play one specific antic.
  void play(OrbAntic which) => _choreo?.play(which);

  /// Look somewhere and hold it for a beat.
  void lookAt(Offset where) => _choreo?.poke(where);

  void dispose() => frames.dispose();
}

/// The animated assistant orb.
///
/// ```dart
/// RezolveOrb(size: 220, mood: _speaking ? OrbMood.speaking : OrbMood.idle)
/// ```
///
/// Everything is drawn procedurally — no images, no Rive, no Lottie, no
/// packages — so it is resolution-independent and a couple of hundred lines of
/// maths rather than a few megabytes of frames.
///
/// Feed [amplitude] (0..1) from your TTS engine or mic if you want the mouth to
/// follow real audio; leave it null and the orb speaks with its own slow,
/// natural rhythm.
class RezolveOrb extends StatefulWidget {
  const RezolveOrb({
    super.key,
    this.size = 200,
    this.mood = OrbMood.idle,
    this.amplitude,
    this.playfulness = 0.7,
    this.headroom = 0.26,
    this.controller,
    this.onTap,
    this.quality = OrbQuality.high,
    this.palette = OrbPalette.rezolve,
    this.paused = false,
  });

  /// Width of the widget, and roughly the diameter of the ball.
  final double size;
  final OrbMood mood;

  /// How often the orb fidgets when it has nothing to do: 0 holds perfectly
  /// still, 1 is a bounce or a wink every few seconds. Antics never interrupt
  /// speech.
  final double playfulness;

  /// Extra height above the ball, as a fraction of [size], for it to bounce
  /// into. The widget lays out [size] wide by size * (1 + headroom) tall, with
  /// the ball resting on the bottom. Pass 0 for a strictly square box.
  final double headroom;

  /// Optional handle for making it hop, wink or look somewhere on cue.
  final RezolveOrbController? controller;

  /// Called when the orb is tapped. The orb reacts to the tap either way.
  final VoidCallback? onTap;

  /// Live speech level, 0..1. Null = the orb improvises its own rhythm.
  final double? amplitude;

  final OrbQuality quality;
  final OrbPalette palette;

  /// Freezes the animation on the current frame (the orb also stops itself
  /// whenever Flutter mutes tickers — off-screen routes, background app).
  final bool paused;

  @override
  State<RezolveOrb> createState() => _RezolveOrbState();
}

class _RezolveOrbState extends State<RezolveOrb>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final OrbChoreographer _choreo;
  late final ValueNotifier<OrbFrame> _frame =
      widget.controller?.frames ?? ValueNotifier<OrbFrame>(OrbFrame.rest);
  bool get _ownsNotifier => widget.controller == null;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _choreo = OrbChoreographer(
      initialMood: widget.mood,
      playfulness: widget.playfulness,
    )..amplitude = widget.amplitude;
    widget.controller?._attach(_choreo);
    _ticker = createTicker(_onTick);
    if (!widget.paused) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _frame.value = _choreo.advance(dt);
  }

  @override
  void didUpdateWidget(RezolveOrb old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller?._detach(_choreo);
      widget.controller?._attach(_choreo);
    }
    _choreo
      ..mood = widget.mood
      ..amplitude = widget.amplitude
      ..playfulness = widget.playfulness;
    if (widget.paused != old.paused) {
      if (widget.paused) {
        _ticker.stop();
      } else {
        _last = Duration.zero;
        _ticker.start();
      }
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(_choreo);
    _ticker.dispose();
    if (_ownsNotifier) _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double height = widget.size * (1 + widget.headroom);
    final Size box = Size(widget.size, height);

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (TapDownDetails d) {
          // Tell the orb where it was touched, in its own -1..1 space, so it
          // looks at your finger rather than straight ahead.
          _choreo.poke(Offset(
            (d.localPosition.dx / box.width) * 2 - 1,
            (d.localPosition.dy / box.height) * 2 - 1,
          ));
          widget.onTap?.call();
        },
        child: SizedBox(
          width: box.width,
          height: box.height,
          child: ValueListenableBuilder<OrbFrame>(
            valueListenable: _frame,
            builder: (BuildContext context, OrbFrame frame, _) {
              return CustomPaint(
                size: box,
                painter: OrbPainter(
                  frame: frame,
                  palette: widget.palette,
                  quality: widget.quality,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
