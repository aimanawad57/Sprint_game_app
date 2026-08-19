import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/gameplay/game_rules.dart';
import 'package:sprint_app/models/game/game_card.dart';
import 'package:sprint_app/models/game/game_move.dart';

GameCard card(String id, GameCardColor color, GameCardShape shape, int count) =>
    GameCard(cardId: id, color: color, shape: shape, count: count);

void main() {
  const pile1 = GameCard(
    cardId: 'pile-1',
    color: GameCardColor.red,
    shape: GameCardShape.star,
    count: 2,
  );
  const pile2 = GameCard(
    cardId: 'pile-2',
    color: GameCardColor.blue,
    shape: GameCardShape.flag,
    count: 4,
  );

  group('legalTargets', () {
    test('returns no target when no attribute matches either pile', () {
      expect(
        legalTargets(
          card('none', GameCardColor.green, GameCardShape.tree, 5),
          pile1,
          pile2,
        ),
        isEmpty,
      );
    });

    test('returns only the matching pile', () {
      expect(
        legalTargets(
          card('one', GameCardColor.red, GameCardShape.house, 3),
          pile1,
          pile2,
        ),
        [GamePileId.pile1],
      );
    });

    test('returns both independently matching piles in stable order', () {
      expect(
        legalTargets(
          card('both', GameCardColor.red, GameCardShape.flag, 5),
          pile1,
          pile2,
        ),
        [GamePileId.pile1, GamePileId.pile2],
      );
    });
  });

  group('move feedback', () {
    test('reports every attribute shared with a pile card', () {
      expect(
        matchingCardAttributes(
          card('multi', GameCardColor.red, GameCardShape.star, 5),
          pile1,
        ),
        [CardMatchAttribute.color, CardMatchAttribute.shape],
      );
    });

    test('legal plays have no rejection message', () {
      final result = evaluateCardPlay(
        card('legal', GameCardColor.green, GameCardShape.star, 5),
        pile1,
      );

      expect(result, CardPlayLegality.legal);
      expect(result.isLegal, isTrue);
      expect(result.feedbackMessage, isNull);
    });

    test('illegal plays provide concise multiplayer-ready guidance', () {
      final result = evaluateCardPlay(
        card('illegal', GameCardColor.green, GameCardShape.tree, 5),
        pile1,
      );

      expect(result, CardPlayLegality.mustMatchCenterCard);
      expect(result.isLegal, isFalse);
      expect(result.feedbackMessage, illegalMoveHint);
    });
  });

  test('matches the shared card-match contract fixture', () {
    final document =
        jsonDecode(
              File(
                'docs/game-contract/card-match-cases.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    expect(document.keys.toSet(), {'schemaVersion', 'cases'});
    expect(document['schemaVersion'], 1);
    final cases = document['cases'] as List<dynamic>;
    expect(cases, isNotEmpty);

    for (final rawCase in cases) {
      final fixtureCase = rawCase as Map<String, dynamic>;
      expect(fixtureCase.keys.toSet(), {
        'name',
        'playedCard',
        'topCard',
        'matches',
      });
      final playedCardJson = fixtureCase['playedCard'] as Map<String, dynamic>;
      final topCardJson = fixtureCase['topCard'] as Map<String, dynamic>;
      const cardKeys = {'card_id', 'color', 'shape', 'count'};
      expect(playedCardJson.keys.toSet(), cardKeys);
      expect(topCardJson.keys.toSet(), cardKeys);
      expect(fixtureCase['matches'], isA<bool>());

      expect(
        cardsMatch(
          GameCard.fromJson(playedCardJson),
          GameCard.fromJson(topCardJson),
        ),
        fixtureCase['matches'],
        reason: fixtureCase['name'] as String,
      );
    }
  });
}
