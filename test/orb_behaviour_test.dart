import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:backPAC/orb/orb_expression.dart';

/// Runs the choreographer forward and hands back every frame it produced.
List<OrbFrame> run(OrbChoreographer c, double seconds) {
  final List<OrbFrame> frames = <OrbFrame>[];
  for (int i = 0; i < seconds * 120; i++) {
    frames.add(c.advance(1 / 120));
  }
  return frames;
}

void main() {
  test('a poke makes it jump, and it lands again', () {
    final OrbChoreographer c =
        OrbChoreographer(playfulness: 0, random: math.Random(1));
    c.poke();
    final List<OrbFrame> frames = run(c, 2.5);

    expect(frames.map((OrbFrame f) => f.lift).reduce(math.max), greaterThan(0.5),
        reason: 'it should leave the floor');
    expect(frames.last.hop, closeTo(0, 0.001),
        reason: 'and be back on the floor afterwards');
    expect(frames.map((OrbFrame f) => f.squash).reduce(math.max),
        greaterThan(0.2),
        reason: 'landing should squash it');
  });

  test('it holds still while speaking', () {
    final OrbChoreographer c = OrbChoreographer(
      initialMood: OrbMood.speaking,
      playfulness: 1,
      random: math.Random(2),
    );
    final List<OrbFrame> frames = run(c, 25);

    expect(c.antic, isNull);
    expect(frames.map((OrbFrame f) => f.lift).reduce(math.max), 0,
        reason: 'no bouncing mid-sentence');
    expect(frames.map((OrbFrame f) => f.mouthOpen).reduce(math.max),
        greaterThan(0.4),
        reason: 'but the mouth should be working');
  });

  test('left alone and playful, it finds something to do', () {
    final OrbChoreographer c =
        OrbChoreographer(playfulness: 1, random: math.Random(3));
    var played = 0;
    OrbAntic? last;
    for (int i = 0; i < 60 * 120; i++) {
      c.advance(1 / 120);
      if (c.antic != null && c.antic != last) played++;
      last = c.antic;
    }
    expect(played, greaterThan(5), reason: 'a minute should hold several antics');
  });

  test('playfulness 0 keeps it perfectly still', () {
    final OrbChoreographer c =
        OrbChoreographer(playfulness: 0, random: math.Random(4));
    final List<OrbFrame> frames = run(c, 40);
    expect(c.antic, isNull);
    expect(frames.map((OrbFrame f) => f.lift).reduce(math.max), 0);
  });

  test('a wink closes one eye and not the other', () {
    final OrbChoreographer c =
        OrbChoreographer(playfulness: 0, random: math.Random(5));
    c.play(OrbAntic.wink);
    final List<OrbFrame> frames = run(c, 0.6);
    final OrbFrame shut = frames.reduce((OrbFrame a, OrbFrame b) =>
        a.leftEyeOpen < b.leftEyeOpen ? a : b);
    expect(shut.leftEyeOpen, lessThan(0.05));
    expect(shut.rightEyeOpen, greaterThan(0.9));
    expect(shut.smirk, greaterThan(0.2));
  });

  test('motion stays smooth — no jumps between frames', () {
    final OrbChoreographer c =
        OrbChoreographer(playfulness: 1, random: math.Random(6));
    OrbFrame prev = c.advance(1 / 60);
    var maxHopStep = 0.0;
    for (int i = 0; i < 60 * 60; i++) {
      final OrbFrame f = c.advance(1 / 60);
      maxHopStep = math.max(maxHopStep, (f.hop - prev.hop).abs());
      prev = f;
    }
    // A 60 fps frame may not move the orb more than a tenth of its radius.
    expect(maxHopStep, lessThan(0.1));
  });
}
