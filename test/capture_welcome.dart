@Tags(<String>['screenshot'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backPAC/app/app.dart';

/// Renders the real widget tree to a PNG, for eyeballing the design without a
/// device. Run with: SHOT_OUT=/tmp/shots flutter test test/screenshot_test.dart
void main() {
  testWidgets('capture welcome page', (WidgetTester tester) async {
    final String dir = Platform.environment['SHOT_OUT'] ?? 'shots';
    Directory(dir).createSync(recursive: true);

    const Size logical = Size(390, 844); // iPhone 14/15 class
    tester.view.physicalSize = logical * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);

    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(
        RepaintBoundary(key: key, child: const backPACApp()));

    // Let the greeting land and the orb settle mid-sentence.
    await tester.pump(const Duration(milliseconds: 800));
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }

    await tester.runAsync(() async {
      final RenderRepaintBoundary boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 2);
      final ByteData? bytes =
          await image.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/welcome.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
