# Rezolve orb — animated assistant face (Flutter)

A procedural, resolution-independent version of the gradient orb: no image
frames, no Rive, no Lottie, **no packages at all** — just `CustomPainter` plus a
few hundred lines of motion maths. Drop the folder in and use it.

```dart
import 'orb/rezolve_orb.dart';

RezolveOrb(
  size: 220,
  mood: _isTalking ? OrbMood.speaking : OrbMood.idle,
)
```

## Moods

| Mood | What it does |
|---|---|
| `OrbMood.idle` | The reference artwork at rest — slow breath, a blink every 3–6 s, and, left alone, the antics below. |
| `OrbMood.listening` | Eyes a touch wider, warm crescent smile, calm pulse in the low clouds. |
| `OrbMood.thinking` | Gaze drifts up and away, lids lower slightly. |
| `OrbMood.speaking` | The orange mouth opens in slow syllables (~1.1 Hz) with phrase pauses, and warm light spills onto the clouds around it. |

Switching mood never snaps — every value is spring-filtered, so it eases over
roughly 400 ms on its own.

## Playing around

Left alone, the orb entertains itself: it bounces off the floor with proper
squash and stretch, looks up, down and around, shimmies, tips over and rights
itself, leans in for a closer look, winks with a smirk, and — rarely — rolls its
whole colour field over once.

```dart
RezolveOrb(playfulness: 0.7)   // default. 0 holds still, 1 is a trick every few seconds
```

Antics are dealt from a shuffled deck rather than rolled independently, so the
whole repertoire shows up in a different order every time; a weighted die kept
handing out the same trick three times running, which reads as broken rather
than random. Nothing fidgets while the orb is speaking or thinking — moving
mid-sentence reads as distracted, not alive.

## Touch, and driving it yourself

Tapping the orb makes it look at your finger, jump, and grin. Pass `onTap` if
the page wants to know too.

```dart
final orb = RezolveOrbController();

RezolveOrb(controller: orb, onTap: () => HapticFeedback.lightImpact())

orb.poke(const Offset(-0.5, -0.5)); // look up-left, hop, grin
orb.play(OrbAntic.wink);
orb.lookAt(Offset.zero);
```

`controller.frames` is a `ValueListenable<OrbFrame>` of what is on screen right
now. The welcome page listens to it to drive the shadow under the orb: it
shrinks and fades as the orb leaves the floor, and spreads when it lands and
squashes. Remember to `dispose()` the controller.

## Layout and the floor

The widget lays out `size` wide and `size * (1 + headroom)` tall — the ball
rests on the bottom edge and the extra height above it is room to bounce into.
`headroom` defaults to 0.26; pass 0 for a strictly square box (the orb will
still hop, but only within its halo margin).

## Driving it from real audio

```dart
RezolveOrb(
  mood: OrbMood.speaking,
  amplitude: _level, // 0..1 from your TTS engine or mic, updated as often as you like
)
```

The level goes through the same critically-damped spring as everything else, so
even raw, jittery amplitude data comes out as smooth, soothing mouth movement
rather than chatter. Leave `amplitude` null and the orb improvises its own
rhythm, which is usually what you want for scripted replies.

## Performance

`OrbQuality.high` (default) draws a blur pass that melts the colour clouds
together, plus eye bloom and mouth glow. `balanced` halves the blur — right for
avatars in a list. `low` is gradients only, for tiny sizes or old hardware.

(An earlier version laid a film-grain tile over the orb to kill gradient
banding. It was dropped: composited over the blurred layer it left a faint
square seam around the widget on CanvasKit, and the palette is saturated enough
not to band without it.)

The widget is wrapped in a `RepaintBoundary`, repaints through a
`ValueNotifier` (so only the painter runs each frame, never the widget tree),
and stops itself whenever Flutter mutes tickers — off-screen routes, background
app. `paused: true` freezes it on the spot.

## Files

| File | Role |
|---|---|
| `rezolve_orb.dart` | The widget. Ticker, grain loading, the public API. Import this one. |
| `orb_expression.dart` | `OrbMood`, `OrbFrame`, and the choreographer that turns time into a face — blinks, gaze, speech rhythm. Pure logic, no painting. |
| `orb_painter.dart` | The `CustomPainter`: body, eyes, mouth. Stateless with respect to time. |
| `orb_palette.dart` | The colour clouds that make up the orb, in unit space. Retune the artwork here. |
| `orb_motion.dart` | Value noise and the springs every animated value is filtered through. |
| `orb_demo_page.dart` | A scratch page showing every mood and a scripted turn. Delete it when you are done with it. |

## Try it

```dart
Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => const OrbDemoPage()),
);
```

`test/orb_widget_test.dart` covers the animation lifecycle — mood changes,
unmount, paused. Run it with `flutter test`.

## How smooth is it, actually

Measured over an 8-second speaking pass sampled at 30 fps: the mouth peaks at
0.77 of full open (it never slams to the stop), the largest single-frame change
is 0.053, and the largest frame-to-frame change *in* that rate is 0.012. There
is no step anywhere in the signal — that is what the springs buy you.

## Tuning

Everything is in unit space — the orb is a circle of radius 1 — so the same
numbers work at 48 px and 320 px.

- **Face layout**: the `_eyeX` / `_eyeY` / `_eyeW` / `_eyeH` / `_mouthY` /
  `_mouthW` constants at the top of `orb_painter.dart`.
- **Colour**: `OrbPalette.rezolve` in `orb_palette.dart`. Each `OrbBlob` has a
  position, radius, wander distance and period; `warmResponse` is how much it
  brightens while the orb speaks.
- **Speech pace**: the `1.08` (syllables per second) and the `0.21` phrase
  envelope in `OrbChoreographer.advance`. Lower both for an even calmer read.
- **Blink rhythm**: `_scheduleBlink` and `_lidOpenness`.
