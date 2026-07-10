import 'package:flutter/material.dart';

import '../models/game/game_card.dart';

Color gameCardColorValue(GameCardColor color) {
  switch (color) {
    case GameCardColor.red:
      return const Color(0xFFE24B4A);
    case GameCardColor.orange:
      return const Color(0xFFE8791E);
    case GameCardColor.yellow:
      return const Color(0xFFF2C230);
    case GameCardColor.green:
      return const Color(0xFF639922);
    case GameCardColor.blue:
      return const Color(0xFF378ADD);
    case GameCardColor.purple:
      return const Color(0xFF7F77DD);
  }
}

class GameCardShapeIcon extends StatelessWidget {
  const GameCardShapeIcon({
    super.key,
    required this.shape,
    required this.color,
    this.size = 24,
  });

  final GameCardShape shape;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GameCardShapePainter(shape: shape, color: color),
      ),
    );
  }
}

class GameCardFace extends StatelessWidget {
  const GameCardFace({super.key, required this.card, this.maxWidth = 120});

  final GameCard card;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final iconSize = switch (card.count) {
      1 => 40.0,
      2 || 3 => 30.0,
      4 => 22.0,
      _ => 20.0,
    };
    final color = gameCardColorValue(card.color);

    return SizedBox(
      width: maxWidth,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var i = 0; i < card.count; i++)
            GameCardShapeIcon(shape: card.shape, color: color, size: iconSize),
        ],
      ),
    );
  }
}

extension on Path {
  void moveToOffset(Offset offset) => moveTo(offset.dx, offset.dy);
  void lineToOffset(Offset offset) => lineTo(offset.dx, offset.dy);
}

class _GameCardShapePainter extends CustomPainter {
  const _GameCardShapePainter({required this.shape, required this.color});

  final GameCardShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(_pathFor(size), paint);
  }

  // All shapes are authored on a shared 0-100 grid so they read as one
  // consistent family regardless of which shape is drawn.
  Path _pathFor(Size size) {
    Offset p(double x, double y) =>
        Offset(x / 100 * size.width, y / 100 * size.height);

    switch (shape) {
      case GameCardShape.star:
        return Path()
          ..moveToOffset(p(50, 5))
          ..lineToOffset(p(61, 38))
          ..lineToOffset(p(97, 38))
          ..lineToOffset(p(68, 59))
          ..lineToOffset(p(79, 92))
          ..lineToOffset(p(50, 71))
          ..lineToOffset(p(21, 92))
          ..lineToOffset(p(32, 59))
          ..lineToOffset(p(3, 38))
          ..lineToOffset(p(39, 38))
          ..close();
      case GameCardShape.diamond:
        return Path()
          ..moveToOffset(p(50, 5))
          ..lineToOffset(p(90, 50))
          ..lineToOffset(p(50, 95))
          ..lineToOffset(p(10, 50))
          ..close();
      case GameCardShape.circle:
        return Path()..addOval(
          Rect.fromCircle(center: p(50, 50), radius: 0.45 * size.shortestSide),
        );
      case GameCardShape.house:
        return Path()
          ..moveToOffset(p(50, 5))
          ..lineToOffset(p(95, 42))
          ..lineToOffset(p(95, 95))
          ..lineToOffset(p(5, 95))
          ..lineToOffset(p(5, 42))
          ..close();
      case GameCardShape.tree:
        return Path()
          ..moveToOffset(p(50, 8))
          ..lineToOffset(p(78, 45))
          ..lineToOffset(p(22, 45))
          ..close()
          ..moveToOffset(p(50, 30))
          ..lineToOffset(p(90, 75))
          ..lineToOffset(p(10, 75))
          ..close()
          ..addRect(Rect.fromPoints(p(42, 75), p(58, 93)));
      case GameCardShape.flag:
        return Path()
          ..addRect(Rect.fromPoints(p(20, 5), p(26, 95)))
          ..moveToOffset(p(26, 10))
          ..lineToOffset(p(85, 25))
          ..lineToOffset(p(26, 40))
          ..close();
    }
  }

  @override
  bool shouldRepaint(covariant _GameCardShapePainter oldDelegate) {
    return oldDelegate.shape != shape || oldDelegate.color != color;
  }
}
