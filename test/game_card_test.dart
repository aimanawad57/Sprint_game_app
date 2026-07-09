import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game/game_card.dart';

void main() {
  Map<String, dynamic> validCard({
    Object? cardId = 'card_001',
    Object? color = 'red',
    Object? shape = 'star',
    Object? count = 1,
  }) {
    return {'card_id': cardId, 'color': color, 'shape': shape, 'count': count};
  }

  group('GameCard.fromJson', () {
    test('parses every supported color', () {
      for (final color in GameCardColor.values) {
        final card = GameCard.fromJson(validCard(color: color.name));
        expect(card.color, color);
      }
    });

    test('parses every supported shape', () {
      for (final shape in GameCardShape.values) {
        final card = GameCard.fromJson(validCard(shape: shape.name));
        expect(card.shape, shape);
      }
    });

    test('accepts every count from 1 through 5', () {
      for (var count = 1; count <= 5; count++) {
        expect(GameCard.fromJson(validCard(count: count)).count, count);
      }
    });

    test('rejects invalid counts', () {
      for (final count in <Object?>[0, 6, 1.5, '1', null]) {
        expect(
          () => GameCard.fromJson(validCard(count: count)),
          throwsFormatException,
        );
      }
    });

    test('rejects missing fields', () {
      for (final field in <String>['card_id', 'color', 'shape', 'count']) {
        final json = validCard()..remove(field);
        expect(() => GameCard.fromJson(json), throwsFormatException);
      }
    });

    test('rejects unsupported enum values', () {
      expect(
        () => GameCard.fromJson(validCard(color: 'pink')),
        throwsFormatException,
      );
      expect(
        () => GameCard.fromJson(validCard(shape: 'square')),
        throwsFormatException,
      );
    });

    test('rejects blank and incorrectly typed card ids', () {
      for (final cardId in <Object?>['', '  ', 1, null]) {
        expect(
          () => GameCard.fromJson(validCard(cardId: cardId)),
          throwsFormatException,
        );
      }
    });
  });
}
