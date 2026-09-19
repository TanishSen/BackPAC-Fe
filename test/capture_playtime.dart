// Renders a stretch of the orb amusing itself, for review as an animation.
//   PLAY_OUT=/tmp/play flutter test test/capture_playtime.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backPAC/orb/orb_expression.dart';
import 'package:backPAC/orb/orb_painter.dart';

const double kW = 260;
const double kH = 328;
const double kFps = 25;
const double kSeconds = 20;

void main() {
  testWidgets('capture playtime', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final Directory out = Directory(Platform.environment['PLAY_OUT'] ?? 'play')
        ..createSync(recursive: true);
      final OrbChoreographer c = OrbChoreographer(
        playfulness: 1,
        random: math.Random(11),
      );
      // A greeting first, then it is left to its own devices.
      c.mood = OrbMood.speaking;
      var spoke = 0.0;

      for (int f = 0; f < kSeconds * kFps; f++) {
        late OrbFrame frame;
        for (int s = 0; s < 4; s++) {
          frame = c.advance(1 / (kFps * 4));
        }
        spoke += 1 / kFps;
        if (spoke > 2.6 && c.mood == OrbMood.speaking) c.mood = OrbMood.idle;

        final ui.PictureRecorder rec = ui.PictureRecorder();
        final Canvas canvas = Canvas(rec, const Rect.fromLTWH(0, 0, kW, kH));
        canvas.drawRect(const Rect.fromLTWH(0, 0, kW, kH),
            Paint()..color = const Color(0xFFF4F4F6));
        OrbPainter(frame: frame).paint(canvas, const Size(kW, kH));
        final ui.Image img =
            await rec.endRecording().toImage(kW.toInt(), kH.toInt());
        final ByteData? bytes =
            await img.toByteData(format: ui.ImageByteFormat.png);
        File('${out.path}/p${f.toString().padLeft(3, '0')}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      }
    });
  });
}
