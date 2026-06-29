import 'game_card.dart';

enum GameMatchStatus { waiting, active, finished }

class CenterPileView {
  const CenterPileView({required this.topCard});

  final GameCard topCard;

  factory CenterPileView.fromJson(Map<String, dynamic> json) {
    return CenterPileView(
      topCard: GameCard.fromJson(
        _requiredMap(json['topCard'], fieldName: 'topCard'),
      ),
    );
  }
}

class GameStateView {
  GameStateView({
    required this.stateVersion,
    required this.status,
    required List<GameCard> myHand,
    required this.myDeckCount,
    required this.opponentHandCount,
    required this.opponentDeckCount,
    required this.pile1,
    required this.pile2,
    required this.winnerId,
  }) : myHand = List<GameCard>.unmodifiable(myHand);

  final int stateVersion;
  final GameMatchStatus status;
  final List<GameCard> myHand;
  final int myDeckCount;
  final int opponentHandCount;
  final int opponentDeckCount;
  final CenterPileView pile1;
  final CenterPileView pile2;
  final String? winnerId;

  factory GameStateView.fromJson(Map<String, dynamic> json) {
    final handJson = json['myHand'];
    if (handJson is! List) {
      throw const FormatException('myHand must be a list');
    }

    final hand = <GameCard>[];
    for (var index = 0; index < handJson.length; index++) {
      try {
        hand.add(
          GameCard.fromJson(
            _requiredMap(handJson[index], fieldName: 'myHand[$index]'),
          ),
        );
      } on FormatException catch (error) {
        throw FormatException('Invalid myHand[$index]: ${error.message}');
      }
    }

    final centerPiles = _requiredMap(
      json['centerPiles'],
      fieldName: 'centerPiles',
    );

    final winnerValue = json['winnerId'];
    if (winnerValue != null &&
        (winnerValue is! String || winnerValue.trim().isEmpty)) {
      throw const FormatException(
        'winnerId must be null or a non-empty string',
      );
    }

    return GameStateView(
      stateVersion: _nonNegativeInt(
        json['stateVersion'],
        fieldName: 'stateVersion',
      ),
      status: _parseStatus(json['status']),
      myHand: hand,
      myDeckCount: _nonNegativeInt(
        json['myDeckCount'],
        fieldName: 'myDeckCount',
      ),
      opponentHandCount: _nonNegativeInt(
        json['opponentHandCount'],
        fieldName: 'opponentHandCount',
      ),
      opponentDeckCount: _nonNegativeInt(
        json['opponentDeckCount'],
        fieldName: 'opponentDeckCount',
      ),
      pile1: CenterPileView.fromJson(
        _requiredMap(centerPiles['pile_1'], fieldName: 'centerPiles.pile_1'),
      ),
      pile2: CenterPileView.fromJson(
        _requiredMap(centerPiles['pile_2'], fieldName: 'centerPiles.pile_2'),
      ),
      winnerId: winnerValue as String?,
    );
  }
}

Map<String, dynamic> _requiredMap(Object? value, {required String fieldName}) {
  if (value is! Map) {
    throw FormatException('$fieldName must be an object');
  }

  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    throw FormatException('$fieldName must have string keys');
  }
}

int _nonNegativeInt(Object? value, {required String fieldName}) {
  if (value is! int || value < 0) {
    throw FormatException('$fieldName must be a non-negative integer');
  }
  return value;
}

GameMatchStatus _parseStatus(Object? value) {
  if (value is! String) {
    throw const FormatException('status must be a string');
  }

  for (final status in GameMatchStatus.values) {
    if (status.name == value) return status;
  }

  throw FormatException('Unsupported status: $value');
}
