import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game/game_card.dart';
import 'package:sprint_app/models/game/game_move.dart';
import 'package:sprint_app/models/game/game_state_transition.dart';
import 'package:sprint_app/models/game/game_state_view.dart';

void main() {
  Map<String, dynamic> card(String id, String color, String shape, int count) {
    return {'card_id': id, 'color': color, 'shape': shape, 'count': count};
  }

  Map<String, dynamic> validState({
    Object? winnerId,
    Object? winnerName,
    Object? endReason,
  }) {
    return {
      'stateVersion': 1,
      'status': 'active',
      'elapsedTimeMs': 37250,
      'myHand': [
        card('card_001', 'red', 'star', 1),
        card('card_002', 'blue', 'tree', 2),
        card('card_003', 'green', 'circle', 3),
      ],
      'myDeckCount': 26,
      'opponentHandCount': 3,
      'opponentDeckCount': 26,
      'centerPiles': {
        'pile_1': {'topCard': card('card_061', 'orange', 'diamond', 4)},
        'pile_2': {'topCard': card('card_060', 'purple', 'house', 5)},
      },
      'winnerId': winnerId,
      'winnerName': winnerName,
      'endReason': endReason,
    };
  }

  group('GameStateView.fromJson', () {
    test('parses a complete active game state', () {
      final state = GameStateView.fromJson(validState());

      expect(state.stateVersion, 1);
      expect(state.status, GameMatchStatus.active);
      expect(state.elapsedTimeMs, 37250);
      expect(state.myHand, hasLength(3));
      expect(state.myDeckCount, 26);
      expect(state.opponentHandCount, 3);
      expect(state.opponentDeckCount, 26);
      expect(state.pile1.topCard.cardId, 'card_061');
      expect(state.pile2.topCard.cardId, 'card_060');
      expect(state.winnerId, isNull);
      expect(state.winnerName, isNull);
      expect(state.endReason, isNull);
      expect(state.transitions, isEmpty);
      expect(state.myRttEstimateMs, isNull);
      expect(state.myRttSampleSequence, isNull);
    });

    test('parses ordered presentation transitions and viewer RTT metadata', () {
      final state = validState()
        ..['myRttEstimateMs'] = 248
        ..['myRttSampleSequence'] = 7
        ..['transitions'] = [
          {
            'type': 'card_played',
            'actor': 'self',
            'card': card('card_001', 'red', 'star', 1),
            'targetPileId': 'pile_1',
          },
          {
            'type': 'card_played',
            'actor': 'opponent',
            'card': card('card_002', 'blue', 'tree', 2),
            'targetPileId': 'pile_2',
          },
        ];

      final parsed = GameStateView.fromJson(state);

      expect(parsed.myRttEstimateMs, 248);
      expect(parsed.myRttSampleSequence, 7);
      expect(parsed.transitions, hasLength(2));
      expect(parsed.transitions.first.actor, GameStateTransitionActor.self);
      expect(parsed.transitions.first.targetPileId, GamePileId.pile1);
      expect(parsed.transitions.last.actor, GameStateTransitionActor.opponent);
      expect(parsed.transitions.last.targetPileId, GamePileId.pile2);
    });

    test('ignores malformed optional feedback without losing core state', () {
      final state = validState()
        ..['myRttEstimateMs'] = -10
        ..['myRttSampleSequence'] = 'future'
        ..['transitions'] = [
          {'type': 'future_transition'},
          'not-an-object',
        ];

      final parsed = GameStateView.fromJson(state);

      expect(parsed.stateVersion, 1);
      expect(parsed.myRttEstimateMs, isNull);
      expect(parsed.myRttSampleSequence, isNull);
      expect(parsed.transitions, isEmpty);
    });

    test('ignores a non-list transitions extension', () {
      final parsed = GameStateView.fromJson(
        validState()..['transitions'] = {'future': true},
      );

      expect(parsed.transitions, isEmpty);
    });

    test('accepts a non-empty winner id and winner name', () {
      final state = GameStateView.fromJson(
        validState(winnerId: 'player-a', winnerName: 'Alice'),
      );
      expect(state.winnerId, 'player-a');
      expect(state.winnerName, 'Alice');
    });

    test('accepts valid end reasons', () {
      expect(
        GameStateView.fromJson(validState(endReason: 'normal')).endReason,
        GameMatchEndReason.normal,
      );
      expect(
        GameStateView.fromJson(validState(endReason: 'forfeit')).endReason,
        GameMatchEndReason.forfeit,
      );
      expect(
        GameStateView.fromJson(validState(endReason: 'abandoned')).endReason,
        GameMatchEndReason.abandoned,
      );
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
      expect(
        () => state.transitions.add(
          const GameStateTransition(
            type: GameStateTransitionType.cardPlayed,
            actor: GameStateTransitionActor.self,
            card: GameCard(
              cardId: 'extra-transition',
              color: GameCardColor.red,
              shape: GameCardShape.star,
              count: 1,
            ),
            targetPileId: GamePileId.pile1,
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
        'elapsedTimeMs',
        'myDeckCount',
        'opponentHandCount',
        'opponentDeckCount',
      ]) {
        final state = validState()..[field] = -1;
        expect(() => GameStateView.fromJson(state), throwsFormatException);
      }
    });

    test('rejects missing and non-integer elapsed time', () {
      expect(
        () => GameStateView.fromJson(validState()..remove('elapsedTimeMs')),
        throwsFormatException,
      );
      expect(
        () => GameStateView.fromJson(validState()..['elapsedTimeMs'] = 1.5),
        throwsFormatException,
      );
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
      expect(
        () => GameStateView.fromJson(validState(winnerName: '')),
        throwsFormatException,
      );
      expect(
        () => GameStateView.fromJson(validState(endReason: 'timeout')),
        throwsFormatException,
      );
    });
  });
}
