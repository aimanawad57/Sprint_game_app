enum GameCardColor { red, orange, yellow, green, blue, purple }

enum GameCardShape { star, diamond, tree, house, circle, flag }

class GameCard {
  const GameCard({
    required this.cardId,
    required this.color,
    required this.shape,
    required this.count,
  });

  final String cardId;
  final GameCardColor color;
  final GameCardShape shape;
  final int count;

  factory GameCard.fromJson(Map<String, dynamic> json) {
    final cardId = json['card_id'];
    if (cardId is! String || cardId.trim().isEmpty) {
      throw const FormatException('card_id must be a non-empty string');
    }

    final count = json['count'];
    if (count is! int || count < 1 || count > 5) {
      throw const FormatException('count must be an integer from 1 to 5');
    }

    return GameCard(
      cardId: cardId,
      color: _parseEnum(
        value: json['color'],
        values: GameCardColor.values,
        fieldName: 'color',
      ),
      shape: _parseEnum(
        value: json['shape'],
        values: GameCardShape.values,
        fieldName: 'shape',
      ),
      count: count,
    );
  }
}

T _parseEnum<T extends Enum>({
  required Object? value,
  required List<T> values,
  required String fieldName,
}) {
  if (value is! String) {
    throw FormatException('$fieldName must be a string');
  }

  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }

  throw FormatException('Unsupported $fieldName: $value');
}
