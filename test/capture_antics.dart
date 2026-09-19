// Renders the orb's antics and mouth shapes to PNGs for eyeballing.
//   ANTIC_OUT=/tmp/antics flutter test test/capture_antics.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backPAC/orb/orb_expression.dart';
import 'package:backPAC/orb/orb_painter.dart';

const double kW = 300;
const double kH = 378; // 1 + headroom

Future<void> shot(String path, OrbFrame frame) async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final Canvas canvas = Canvas(rec, const Rect.fromLTWH(0, 0, kW, kH));
  canvas.drawRect(const Rect.fromLTWH(0, 0, kW, kH),
      Paint()..color = const Color(0xFFF4F4F6));
  OrbPainter(frame: frame).paint(canvas, const Size(kW, kH));
  final ui.Image img = await rec.endRecording().toImage(kW.toInt(), kH.toInt());
  final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('capture antics', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final Directory out = Directory(Platform.environment['ANTIC_OUT'] ?? 'antics')
        ..createSync(recursive: true);

      Future<void> run(String label, OrbAntic? antic, List<double> marks,
          {OrbMood mood = OrbMood.idle}) async {
        final OrbChoreographer c = OrbChoreographer(
          initialMood: mood,
          playfulness: 0, // only the antic we ask for
          random: math.Random(4),
        );
        if (antic != null) c.play(antic);
        final List<double> wanted = marks.toList();
        double t = 0;
        int i = 0;
        OrbFrame frame = OrbFrame.rest;
        while (wanted.isNotEmpty && t < 12) {
          frame = c.advance(1 / 120);
          t += 1 / 120;
          if (t >= wanted.first) {
            wanted.removeAt(0);
            await shot(
                '${out.path}/$label-${i.toString().padLeft(2, '0')}.png', frame);
            i++;
          }
        }
      }

      await run('a-hop', OrbAntic.doubleHop, <double>[
        for (int i = 0; i < 14; i++) 0.03 + i * 0.075,
      ]);
      await run('b-wink', OrbAntic.wink, <double>[0.10, 0.22, 0.40, 0.60]);
      await run('c-look', OrbAntic.lookLeft, <double>[0.35, 0.9]);
      await run('d-lookup', OrbAntic.lookUp, <double>[0.35, 0.9]);
      await run('e-peek', OrbAntic.peek, <double>[0.4, 1.0]);
      // Mouth shapes across a whole spoken phrase.
      await run('f-talk', null, <double>[0.5, 0.8, 1.1, 1.4, 1.7, 2.0, 2.3, 2.6],
          mood: OrbMood.speaking);
    });
  });
}
