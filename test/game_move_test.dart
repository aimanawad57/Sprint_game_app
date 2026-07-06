import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game/game_move.dart';

void main() {
  test('SubmitMovePayload uses the documented wire field names', () {
    const payload = SubmitMovePayload(
      cardId: 'card_017',
      targetPileId: GamePileId.pile1,
      expectedStateVersion: 8,
    );

    expect(payload.toJson(), {
      'card_id': 'card_017',
      'targetPileId': 'pile_1',
      'expectedStateVersion': 8,
    });
  });

  test('MoveRejectedView parses every stable rejection reason', () {
    for (final reason in MoveRejectionReason.values) {
      final rejection = MoveRejectedView.fromJson({
        'stateVersion': 9,
        'reason': reason.wireValue,
        'card_id': 'card_017',
        'targetPileId': 'pile_2',
      });

      expect(rejection.reason, reason);
      expect(rejection.stateVersion, 9);
      expect(rejection.cardId, 'card_017');
      expect(rejection.targetPileId, 'pile_2');
      expect(rejection.reason.displayMessage, isNotEmpty);
    }
  });

  test('MoveRejectedView rejects malformed payloads', () {
    expect(
      () => MoveRejectedView.fromJson({
        'stateVersion': -1,
        'reason': 'card_does_not_match',
      }),
      throwsFormatException,
    );
    expect(
      () => MoveRejectedView.fromJson({
        'stateVersion': 2,
        'reason': 'unknown_reason',
      }),
      throwsFormatException,
    );
    expect(
      () => MoveRejectedView.fromJson({
        'stateVersion': 2,
        'reason': 'card_does_not_match',
        'card_id': '',
      }),
      throwsFormatException,
    );
  });
}
