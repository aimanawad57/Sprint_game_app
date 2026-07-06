enum GamePileId {
  pile1('pile_1'),
  pile2('pile_2');

  const GamePileId(this.wireValue);

  final String wireValue;
}

class SubmitMovePayload {
  const SubmitMovePayload({
    required this.cardId,
    required this.targetPileId,
    required this.expectedStateVersion,
  });

  final String cardId;
  final GamePileId targetPileId;
  final int expectedStateVersion;

  Map<String, dynamic> toJson() {
    return {
      'card_id': cardId,
      'targetPileId': targetPileId.wireValue,
      'expectedStateVersion': expectedStateVersion,
    };
  }
}

enum MoveRejectionReason {
  invalidPayload('invalid_payload'),
  matchNotActive('match_not_active'),
  playerNotInMatch('player_not_in_match'),
  cardNotInHand('card_not_in_hand'),
  invalidTargetPile('invalid_target_pile'),
  cardDoesNotMatch('card_does_not_match'),
  staleMove('stale_move'),
  gameFinished('game_finished');

  const MoveRejectionReason(this.wireValue);

  final String wireValue;

  String get displayMessage {
    switch (this) {
      case MoveRejectionReason.invalidPayload:
        return 'The move data was invalid.';
      case MoveRejectionReason.matchNotActive:
        return 'The match is not active.';
      case MoveRejectionReason.playerNotInMatch:
        return 'You are not registered in this match.';
      case MoveRejectionReason.cardNotInHand:
        return 'That card is no longer in your hand.';
      case MoveRejectionReason.invalidTargetPile:
        return 'The selected center pile is invalid.';
      case MoveRejectionReason.cardDoesNotMatch:
        return 'That card does not match the center card.';
      case MoveRejectionReason.staleMove:
        return 'The game changed before your move was processed.';
      case MoveRejectionReason.gameFinished:
        return 'The game has already finished.';
    }
  }
}

class MoveRejectedView {
  const MoveRejectedView({
    required this.stateVersion,
    required this.reason,
    this.cardId,
    this.targetPileId,
  });

  final int stateVersion;
  final MoveRejectionReason reason;
  final String? cardId;
  final String? targetPileId;

  factory MoveRejectedView.fromJson(Map<String, dynamic> json) {
    final stateVersion = json['stateVersion'];
    if (stateVersion is! int || stateVersion < 0) {
      throw const FormatException(
        'stateVersion must be a non-negative integer',
      );
    }

    final reasonValue = json['reason'];
    if (reasonValue is! String) {
      throw const FormatException('reason must be a string');
    }

    MoveRejectionReason? reason;
    for (final candidate in MoveRejectionReason.values) {
      if (candidate.wireValue == reasonValue) {
        reason = candidate;
        break;
      }
    }
    if (reason == null) {
      throw FormatException('Unsupported move rejection reason: $reasonValue');
    }

    return MoveRejectedView(
      stateVersion: stateVersion,
      reason: reason,
      cardId: _optionalNonEmptyString(json['card_id'], 'card_id'),
      targetPileId: _optionalNonEmptyString(
        json['targetPileId'],
        'targetPileId',
      ),
    );
  }
}

String? _optionalNonEmptyString(Object? value, String fieldName) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName must be a non-empty string when present');
  }
  return value;
}
