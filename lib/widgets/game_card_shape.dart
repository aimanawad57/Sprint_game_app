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
    final color = gameCardColorValue(card.color);
    final positions = _symbolPositions(card.count);
    final iconSize = switch (card.count) {
      1 => maxWidth * 0.34,
      2 => maxWidth * 0.29,
      3 => maxWidth * 0.28,
      4 => maxWidth * 0.25,
      _ => maxWidth * 0.23,
    };

    return SizedBox(
      width: maxWidth,
      height: maxWidth * 1.18,
      child: Stack(
        children: [
          for (var i = 0; i < positions.length; i++)
            Align(
              alignment: positions[i],
              child: _RaisedShapeIcon(
                shape: card.shape,
                color: color,
                size: iconSize,
              ),
            ),
        ],
      ),
    );
  }

  List<Alignment> _symbolPositions(int count) {
    return switch (count) {
      1 => const [Alignment.center],
      2 => const [Alignment(-0.42, -0.55), Alignment(0.42, 0.55)],
      3 => const [
        Alignment(0, -0.62),
        Alignment(-0.48, 0.46),
        Alignment(0.48, 0.46),
      ],
      4 => const [
        Alignment(-0.48, -0.54),
        Alignment(0.48, -0.54),
        Alignment(-0.48, 0.54),
        Alignment(0.48, 0.54),
      ],
      _ => const [
        Alignment(-0.48, -0.62),
        Alignment(0.48, -0.62),
        Alignment.center,
        Alignment(-0.48, 0.62),
        Alignment(0.48, 0.62),
      ],
    };
  }
}

class _RaisedShapeIcon extends StatelessWidget {
  const _RaisedShapeIcon({
    required this.shape,
    required this.color,
    required this.size,
  });

  final GameCardShape shape;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: const Offset(0, 2),
          child: GameCardShapeIcon(
            shape: shape,
            color: Colors.black.withValues(alpha: 0.18),
            size: size,
          ),
        ),
        GameCardShapeIcon(shape: shape, color: color, size: size),
      ],
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
