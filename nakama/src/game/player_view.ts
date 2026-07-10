function cloneCard(card: Card): Card {
  return {
    card_id: card.card_id,
    color: card.color,
    shape: card.shape,
    count: card.count
  };
}

function buildPlayerStateView(
  state: SprintMatchState,
  viewerUserId: string
): PlayerStateView {
  const viewer = state.players[viewerUserId];
  if (!viewer) {
    throw new Error("Cannot build a player view for a user outside the match.");
  }

  const opponentUserId =
    state.playerOrder[0] === viewerUserId
      ? state.playerOrder[1]
      : state.playerOrder[0];
  const opponent = state.players[opponentUserId];
  const pile1Top = state.centerPiles.pile_1[state.centerPiles.pile_1.length - 1];
  const pile2Top = state.centerPiles.pile_2[state.centerPiles.pile_2.length - 1];
  if (!pile1Top || !pile2Top) {
    throw new Error("Cannot build an active player view without two center-pile cards.");
  }
  const winner = state.winnerId ? state.players[state.winnerId] : null;

  return {
    stateVersion: state.stateVersion,
    status: state.status,
    myHand: viewer.hand.map(cloneCard),
    myDeckCount: viewer.deck.length,
    opponentHandCount: opponent.hand.length,
    opponentDeckCount: opponent.deck.length,
    centerPiles: {
      pile_1: {topCard: cloneCard(pile1Top)},
      pile_2: {topCard: cloneCard(pile2Top)}
    },
    winnerId: state.winnerId,
    winnerName: winner ? winner.displayName : null,
    endReason: state.endReason
  };
}
