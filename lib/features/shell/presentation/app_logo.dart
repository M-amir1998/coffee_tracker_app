import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// The Coffee Tracker mark: a cup with rising steam on an espresso tile.
/// The same painter generates the platform launcher icons.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Coffee Tracker',
      child: SizedBox.square(
        dimension: size,
        child: const CustomPaint(painter: LogoPainter()),
      ),
    );
  }
}

class LogoPainter extends CustomPainter {
  const LogoPainter({this.background = true});

  /// Without the background tile (for adaptive icon foregrounds).
  final bool background;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);

    if (background) {
      final tile = RRect.fromRectAndRadius(Offset.zero & Size.square(s), Radius.circular(s * 0.26));
      canvas.drawRRect(
        tile,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5A3A2E), Palette.espresso, Palette.deepCoffee],
          ).createShader(Offset.zero & Size.square(s)),
      );
    }

    final cream = Paint()..color = Palette.cream;
    final caramel = Paint()..color = Palette.caramel;

    // Cup body.
    final body = Path()
      ..moveTo(s * 0.24, s * 0.44)
      ..lineTo(s * 0.70, s * 0.44)
      ..cubicTo(s * 0.70, s * 0.63, s * 0.62, s * 0.77, s * 0.47, s * 0.77)
      ..cubicTo(s * 0.32, s * 0.77, s * 0.24, s * 0.63, s * 0.24, s * 0.44)
      ..close();
    canvas.drawPath(body, cream);

    // Coffee surface.
    canvas.drawOval(Rect.fromLTRB(s * 0.27, s * 0.415, s * 0.67, s * 0.475), caramel);

    // Handle.
    canvas.drawArc(
      Rect.fromLTRB(s * 0.62, s * 0.49, s * 0.82, s * 0.66),
      -1.4,
      2.8,
      false,
      Paint()
        ..color = Palette.cream
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.05
        ..strokeCap = StrokeCap.round,
    );

    // Saucer.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(s * 0.18, s * 0.79, s * 0.76, s * 0.83), Radius.circular(s * 0.02)),
      cream,
    );

    // Steam.
    final steam = Paint()
      ..color = Palette.caramel
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.045
      ..strokeCap = StrokeCap.round;
    for (final x in [0.39, 0.53]) {
      final path = Path()
        ..moveTo(s * x, s * 0.36)
        ..cubicTo(s * (x - 0.06), s * 0.30, s * (x + 0.06), s * 0.25, s * x, s * 0.18);
      canvas.drawPath(path, steam);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter oldDelegate) => oldDelegate.background != background;
}
