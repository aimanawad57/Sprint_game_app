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
  viewerUserId: string,
  serverNowMs: number = Date.now(),
  appliedTransitions: AppliedCardTransition[] = []
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
    elapsedTimeMs: calculateElapsedTimeMs(state, serverNowMs),
    transitions: appliedTransitions.map((transition) => ({
      type: transition.type,
      actor: transition.playerId === viewerUserId ? "self" : "opponent",
      card: cloneCard(transition.card),
      targetPileId: transition.targetPileId
    })),
    myRttEstimateMs: normalizeRttEstimateMs(viewer.rttEstimateMs),
    myRttSampleSequence: normalizeRttSampleSequence(
      viewer.rttSampleSequence
    ),
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

function normalizeRttEstimateMs(value: number | null): number | null {
  if (value === null || !isFinite(value) || value < 0) {
    return null;
  }
  return Math.floor(value);
}

function normalizeRttSampleSequence(value: number): number {
  if (!isFinite(value) || value < 0) {
    return 0;
  }
  return Math.floor(value);
}

function calculateElapsedTimeMs(
  state: SprintMatchState,
  serverNowMs: number = Date.now()
): number {
  if (state.startedAtMs === null) {
    return 0;
  }

  const endMs =
    state.status === MatchStatus.Finished && state.endedAtMs !== null
      ? state.endedAtMs
      : serverNowMs;
  return Math.max(0, Math.floor(endMs - state.startedAtMs));
}
