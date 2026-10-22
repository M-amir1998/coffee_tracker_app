// Renders the master launcher icons from the same painter the app uses.
// Run with:  flutter test tool/icons/render_logo_test.dart
// then:      python tool/icons/make_platform_icons.py
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/features/shell/presentation/app_logo.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _size = 1024.0;

Future<void> _render(WidgetTester tester, Widget child, String path) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(dimension: _size, child: child),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('render launcher icon masters', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size.square(_size);
    addTearDown(tester.view.reset);

    // Rounded tile, transparent corners: web, macOS, Windows, store listings.
    await _render(tester, const CustomPaint(painter: LogoPainter()), 'assets/icons/app_icon.png');

    // Full-bleed square for platforms that apply their own mask (iOS, web maskable).
    await _render(
      tester,
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5A3A2E), Palette.espresso, Palette.deepCoffee],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(_size * 0.12),
          child: CustomPaint(painter: LogoPainter(background: false)),
        ),
      ),
      'assets/icons/app_icon_full.png',
    );

    // Adaptive icon foreground: artwork inside the 66 % safe zone, transparent.
    await _render(
      tester,
      const Padding(
        padding: EdgeInsets.all(_size * 0.2),
        child: CustomPaint(painter: LogoPainter(background: false)),
      ),
      'assets/icons/app_icon_foreground.png',
    );
  });
}
