import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game/game_card.dart';
import 'package:sprint_app/models/game/game_state_view.dart';

void main() {
  Map<String, dynamic> card(String id, String color, String shape, int count) {
    return {'card_id': id, 'color': color, 'shape': shape, 'count': count};
  }

  Map<String, dynamic> validState({Object? winnerId}) {
    return {
      'stateVersion': 1,
      'status': 'active',
      'myHand': [
        card('card_001', 'red', 'star', 1),
        card('card_002', 'blue', 'heart', 2),
        card('card_003', 'green', 'circle', 3),
      ],
      'myDeckCount': 27,
      'opponentHandCount': 3,
      'opponentDeckCount': 27,
      'centerPiles': {
        'pile_1': {'topCard': card('card_061', 'orange', 'diamond', 4)},
        'pile_2': {'topCard': card('card_062', 'purple', 'spiral', 5)},
      },
      'winnerId': winnerId,
    };
  }

  group('GameStateView.fromJson', () {
    test('parses a complete active game state', () {
      final state = GameStateView.fromJson(validState());

      expect(state.stateVersion, 1);
      expect(state.status, GameMatchStatus.active);
      expect(state.myHand, hasLength(3));
      expect(state.myDeckCount, 27);
      expect(state.opponentHandCount, 3);
      expect(state.opponentDeckCount, 27);
      expect(state.pile1.topCard.cardId, 'card_061');
      expect(state.pile2.topCard.cardId, 'card_062');
      expect(state.winnerId, isNull);
    });

    test('accepts a non-empty winner id', () {
      final state = GameStateView.fromJson(validState(winnerId: 'player-a'));
      expect(state.winnerId, 'player-a');
    });

    test('creates an unmodifiable hand', () {
      final state = GameStateView.fromJson(validState());

      expect(
        () => state.myHand.add(
          const GameCard(
            cardId: 'extra',
            color: GameCardColor.red,
            shape: GameCardShape.star,
            count: 1,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('rejects a missing center pile', () {
      final state = validState();
      (state['centerPiles'] as Map<String, dynamic>).remove('pile_2');
      expect(() => GameStateView.fromJson(state), throwsFormatException);
    });

    test('rejects a malformed card in the hand', () {
      final state = validState();
      (state['myHand'] as List<Object?>)[0] = {'card_id': 'broken'};
      expect(() => GameStateView.fromJson(state), throwsFormatException);
    });

    test('rejects negative public and private counts', () {
      for (final field in <String>[
        'stateVersion',
        'myDeckCount',
        'opponentHandCount',
        'opponentDeckCount',
      ]) {
        final state = validState()..[field] = -1;
        expect(() => GameStateView.fromJson(state), throwsFormatException);
      }
    });

    test('rejects unsupported status and invalid winner ids', () {
      expect(
        () => GameStateView.fromJson(validState()..['status'] = 'paused'),
        throwsFormatException,
      );
      expect(
        () => GameStateView.fromJson(validState(winnerId: '')),
        throwsFormatException,
      );
    });
  });
}
