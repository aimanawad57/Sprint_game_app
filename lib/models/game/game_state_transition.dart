import 'game_card.dart';
import 'game_move.dart';

enum GameStateTransitionType {
  cardPlayed('card_played');

  const GameStateTransitionType(this.wireValue);

  final String wireValue;
}

enum GameStateTransitionActor {
  self('self'),
  opponent('opponent');

  const GameStateTransitionActor(this.wireValue);

  final String wireValue;
}

class GameStateTransition {
  const GameStateTransition({
    required this.type,
    required this.actor,
    required this.card,
    required this.targetPileId,
  });

  final GameStateTransitionType type;
  final GameStateTransitionActor actor;
  final GameCard card;
  final GamePileId targetPileId;

  factory GameStateTransition.fromJson(Map<String, dynamic> json) {
    final typeValue = json['type'];
    final actorValue = json['actor'];
    final pileValue = json['targetPileId'];

    final type = GameStateTransitionType.values
        .where((candidate) => candidate.wireValue == typeValue)
        .firstOrNull;
    final actor = GameStateTransitionActor.values
        .where((candidate) => candidate.wireValue == actorValue)
        .firstOrNull;
    final targetPileId = GamePileId.values
        .where((candidate) => candidate.wireValue == pileValue)
        .firstOrNull;
    if (type == null) {
      throw FormatException('Unsupported transition type: $typeValue');
    }
    if (actor == null) {
      throw FormatException('Unsupported transition actor: $actorValue');
    }
    if (targetPileId == null) {
      throw FormatException('Unsupported transition pile: $pileValue');
    }
    final cardJson = json['card'];
    if (cardJson is! Map) {
      throw const FormatException('transition card must be an object');
    }

    return GameStateTransition(
      type: type,
      actor: actor,
      card: GameCard.fromJson(Map<String, dynamic>.from(cardJson)),
      targetPileId: targetPileId,
    );
  }
}
