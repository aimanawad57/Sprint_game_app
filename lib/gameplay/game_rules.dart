import '../models/game/game_card.dart';
import '../models/game/game_move.dart';

const String illegalMoveHint = 'Match the color, shape, or number.';

/// The card attributes that can make a play legal.
enum CardMatchAttribute { color, shape, count }

/// The client-side result of comparing a hand card with a center-pile card.
///
/// The server remains authoritative for multiplayer moves. This result exists
/// so the UI can explain obviously invalid choices without sending them.
enum CardPlayLegality {
  legal,
  mustMatchCenterCard;

  bool get isLegal => this == CardPlayLegality.legal;

  String? get feedbackMessage => switch (this) {
    CardPlayLegality.legal => null,
    CardPlayLegality.mustMatchCenterCard => illegalMoveHint,
  };
}

/// Returns every attribute shared by [played] and [top].
///
/// A card may match on more than one attribute. Keeping that information is
/// useful for highlights and accessible move explanations.
List<CardMatchAttribute> matchingCardAttributes(
  GameCard played,
  GameCard top,
) => List<CardMatchAttribute>.unmodifiable([
  if (played.color == top.color) CardMatchAttribute.color,
  if (played.shape == top.shape) CardMatchAttribute.shape,
  if (played.count == top.count) CardMatchAttribute.count,
]);

bool cardsMatch(GameCard played, GameCard top) =>
    matchingCardAttributes(played, top).isNotEmpty;

CardPlayLegality evaluateCardPlay(GameCard played, GameCard top) =>
    cardsMatch(played, top)
    ? CardPlayLegality.legal
    : CardPlayLegality.mustMatchCenterCard;

/// Returns center piles on which [card] can legally be played.
///
/// Pile order is stable so callers that animate or prioritize targets behave
/// deterministically.
List<GamePileId> legalTargets(GameCard card, GameCard pile1, GameCard pile2) =>
    List<GamePileId>.unmodifiable([
      if (cardsMatch(card, pile1)) GamePileId.pile1,
      if (cardsMatch(card, pile2)) GamePileId.pile2,
    ]);
