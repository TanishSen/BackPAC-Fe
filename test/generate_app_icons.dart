// Renders the app launcher icons from the orb itself, so the icon and the
// in-app assistant can never drift apart.
//
//   flutter test test/generate_app_icons.dart
//
// Not named *_test.dart on purpose: `flutter test` should not rewrite the icon
// set on every run.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backPAC/app/app_theme.dart';
import 'package:backPAC/orb/orb_expression.dart';
import 'package:backPAC/orb/orb_painter.dart';

/// A calm, face-forward pose — no blink, no talking.
final OrbFrame _iconPose = OrbChoreographer(initialMood: OrbMood.idle)
    .advance(1.4);

Future<Uint8List> _render(int px, {double inset = 0.86, Color? bg}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas =
      Canvas(recorder, Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble()));

  if (bg != null) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble()),
      Paint()..color = bg,
    );
  }

  final double size = px * inset;
  canvas.save();
  canvas.translate((px - size) / 2, (px - size) / 2);
  OrbPainter(frame: _iconPose, quality: OrbQuality.high)
      .paint(canvas, Size(size, size));
  canvas.restore();

  final ui.Image image = await recorder.endRecording().toImage(px, px);
  final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

Future<void> _write(String path, Uint8List bytes) async {
  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

void main() {
  testWidgets('generate launcher icons', (WidgetTester tester) async {
    await tester.runAsync(() async {
      // iOS icons must be opaque; Android and web may be transparent, but a
      // solid brand-canvas ground reads better on every home screen.
      const Color ground = Color(0xFFF7F6FB);

      const Map<String, int> ios = <String, int>{
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
        'Icon-App-1024x1024@1x.png': 1024,
      };
      for (final MapEntry<String, int> e in ios.entries) {
        await _write('ios/Runner/Assets.xcassets/AppIcon.appiconset/${e.key}',
            await _render(e.value, bg: ground));
      }

      const Map<String, int> android = <String, int>{
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      };
      for (final MapEntry<String, int> e in android.entries) {
        await _write(
            'android/app/src/main/res/mipmap-${e.key}/ic_launcher.png',
            await _render(e.value, bg: ground));
      }

      await _write('web/icons/Icon-192.png', await _render(192, bg: ground));
      await _write('web/icons/Icon-512.png', await _render(512, bg: ground));
      // Maskable icons get cropped to a circle by the launcher: keep the ball
      // well inside the safe zone.
      await _write('web/icons/Icon-maskable-192.png',
          await _render(192, inset: 0.62, bg: AppColors.canvas));
      await _write('web/icons/Icon-maskable-512.png',
          await _render(512, inset: 0.62, bg: AppColors.canvas));
      await _write('web/favicon.png', await _render(64, bg: ground));
    });
  });
}
