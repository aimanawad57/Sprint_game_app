import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game/game_card.dart';
import 'package:sprint_app/models/game/game_move.dart';
import 'package:sprint_app/practice/local_game_rules.dart';

const redStar2 = GameCard(
  cardId: 'a',
  color: GameCardColor.red,
  shape: GameCardShape.star,
  count: 2,
);

GameCard card(String id, GameCardColor color, GameCardShape shape, int count) =>
    GameCard(cardId: id, color: color, shape: shape, count: count);

void main() {
  test('matching accepts color, shape, or count and rejects no match', () {
    expect(
      cardsMatch(
        card('color', GameCardColor.red, GameCardShape.flag, 5),
        redStar2,
      ),
      isTrue,
    );
    expect(
      cardsMatch(
        card('shape', GameCardColor.blue, GameCardShape.star, 5),
        redStar2,
      ),
      isTrue,
    );
    expect(
      cardsMatch(
        card('count', GameCardColor.blue, GameCardShape.flag, 2),
        redStar2,
      ),
      isTrue,
    );
    expect(
      cardsMatch(
        card('none', GameCardColor.blue, GameCardShape.flag, 5),
        redStar2,
      ),
      isFalse,
    );
  });

  test('legal targets checks both independent center piles', () {
    final targets = legalTargets(
      card('move', GameCardColor.red, GameCardShape.flag, 4),
      redStar2,
      card('pile2', GameCardColor.blue, GameCardShape.flag, 1),
    );
    expect(targets, [GamePileId.pile1, GamePileId.pile2]);
  });

  test('replacement drawing and winner detection mirror server rules', () {
    final deck = [redStar2];
    final hand = <GameCard>[];
    expect(drawReplacement(deck, hand), redStar2);
    expect(deck, isEmpty);
    expect(hand, [redStar2]);
    expect(playerHasWon(deck, hand), isFalse);
    hand.clear();
    expect(playerHasWon(deck, hand), isTrue);
  });

  test('catalog and deterministic shuffle preserve all 60 cards', () {
    expect(sprintCardCatalog, hasLength(60));
    final first = shuffledCards(sprintCardCatalog, Random(7));
    final second = shuffledCards(sprintCardCatalog, Random(7));
    expect(first.map((card) => card.cardId), second.map((card) => card.cardId));
    expect(first.map((card) => card.cardId).toSet(), hasLength(60));
  });
}
