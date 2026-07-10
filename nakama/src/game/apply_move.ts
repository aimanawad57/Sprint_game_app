type SubmitMovePayload = {
  card_id: string;
  targetPileId: PileId;
  expectedStateVersion: number;
};

type MoveRejectedPayload = {
  stateVersion: number;
  reason: MoveRejectionReason;
  card_id?: string;
  targetPileId?: string;
};

type ApplyMoveResult =
  | {
      accepted: true;
      playerId: string;
      gameEnded: boolean;
    }
  | {
      accepted: false;
      playerId: string | null;
      rejection: MoveRejectedPayload;
    };

function decodeMatchMessageData(data: ArrayBuffer | string | null): string {
  if (typeof data === "string") {
    return data;
  }

  if (data === null || data === undefined) {
    throw new Error("Missing move payload.");
  }

  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let payload = "";
  for (let index = 0; index < bytes.length; index += 1) {
    payload += String.fromCharCode(bytes[index]);
  }
  return payload;
}

function parseSubmitMovePayload(
  data: ArrayBuffer | string | null
): SubmitMovePayload | MoveRejectedPayload {
  let decoded: any;
  try {
    decoded = JSON.parse(decodeMatchMessageData(data));
  } catch (error) {
    return {
      stateVersion: 0,
      reason: MoveRejectionReason.InvalidPayload
    };
  }

  if (decoded === null || typeof decoded !== "object" || Array.isArray(decoded)) {
    return {
      stateVersion: 0,
      reason: MoveRejectionReason.InvalidPayload
    };
  }

  const cardId = decoded.card_id;
  if (typeof cardId !== "string" || cardId.trim().length === 0) {
    return {
      stateVersion: 0,
      reason: MoveRejectionReason.InvalidPayload
    };
  }

  const targetPileId = decoded.targetPileId;
  if (targetPileId !== PileId.Pile1 && targetPileId !== PileId.Pile2) {
    return {
      stateVersion: 0,
      reason: MoveRejectionReason.InvalidTargetPile,
      card_id: cardId,
      targetPileId: typeof targetPileId === "string" ? targetPileId : undefined
    };
  }

  const expectedStateVersion = decoded.expectedStateVersion;
  if (
    !Number.isInteger(expectedStateVersion) ||
    expectedStateVersion < 0
  ) {
    return {
      stateVersion: 0,
      reason: MoveRejectionReason.InvalidPayload,
      card_id: cardId,
      targetPileId: targetPileId
    };
  }

  return {
    card_id: cardId,
    targetPileId: targetPileId,
    expectedStateVersion: expectedStateVersion
  };
}

function isMoveRejectedPayload(
  payload: SubmitMovePayload | MoveRejectedPayload
): payload is MoveRejectedPayload {
  return (payload as MoveRejectedPayload).reason !== undefined;
}

function rejectMove(
  state: SprintMatchState,
  playerId: string | null,
  reason: MoveRejectionReason,
  payload?: SubmitMovePayload | MoveRejectedPayload
): ApplyMoveResult {
  return {
    accepted: false,
    playerId: playerId,
    rejection: {
      stateVersion: state.stateVersion,
      reason: reason,
      card_id: payload?.card_id,
      targetPileId: payload?.targetPileId
    }
  };
}

function confirmActiveMatch(
  state: SprintMatchState,
  payload: SubmitMovePayload
): ApplyMoveResult | null {
  if (state.status === MatchStatus.Finished) {
    return rejectMove(state, null, MoveRejectionReason.GameFinished, payload);
  }

  if (state.status !== MatchStatus.Active) {
    return rejectMove(state, null, MoveRejectionReason.MatchNotActive, payload);
  }

  return null;
}

function confirmSenderPlayer(
  state: SprintMatchState,
  sender: nkruntime.Presence | null,
  payload: SubmitMovePayload
): PlayerMatchState | ApplyMoveResult {
  if (!sender || !sender.userId) {
    return rejectMove(state, null, MoveRejectionReason.PlayerNotInMatch, payload);
  }

  const player = state.players[sender.userId];
  if (!player) {
    return rejectMove(
      state,
      sender.userId,
      MoveRejectionReason.PlayerNotInMatch,
      payload
    );
  }

  return player;
}

function confirmAllPlayersConnected(
  state: SprintMatchState,
  playerId: string,
  payload: SubmitMovePayload
): ApplyMoveResult | null {
  const allPlayersConnected = state.playerOrder.every((userId) => {
    const player = state.players[userId];
    return player?.connected === true && state.presences[userId] !== undefined;
  });

  if (!allPlayersConnected) {
    return rejectMove(
      state,
      playerId,
      MoveRejectionReason.PlayerDisconnected,
      payload
    );
  }

  return null;
}

function getTargetPile(
  state: SprintMatchState,
  payload: SubmitMovePayload
): Card[] | ApplyMoveResult {
  const pile = state.centerPiles[payload.targetPileId];
  if (!pile) {
    return rejectMove(
      state,
      null,
      MoveRejectionReason.InvalidTargetPile,
      payload
    );
  }

  return pile;
}

function findCardInHand(
  player: PlayerMatchState,
  cardId: string
): number {
  return player.hand.findIndex((card) => card.card_id === cardId);
}

function cardsMatch(playedCard: Card, topCard: Card): boolean {
  return (
    playedCard.color === topCard.color ||
    playedCard.shape === topCard.shape ||
    playedCard.count === topCard.count
  );
}

function drawReplacementIfAvailable(player: PlayerMatchState): void {
  const replacement = player.deck.pop();
  if (replacement) {
    player.hand.push(replacement);
  }
}

function updateWinnerIfNeeded(
  state: SprintMatchState,
  player: PlayerMatchState,
  nowMs: number
): boolean {
  if (player.hand.length === 0 && player.deck.length === 0) {
    state.status = MatchStatus.Finished;
    state.winnerId = player.userId;
    state.endReason = MatchEndReason.Normal;
    state.endedAtMs = nowMs;
    state.resultPersistencePending = true;
    return true;
  }

  return false;
}

function applySubmitMove(
  state: SprintMatchState,
  sender: nkruntime.Presence | null,
  data: ArrayBuffer | string | null,
  nowMs: number = Date.now()
): ApplyMoveResult {
  const payload = parseSubmitMovePayload(data);
  if (isMoveRejectedPayload(payload)) {
    return {
      accepted: false,
      playerId: sender?.userId || null,
      rejection: {
        stateVersion: state.stateVersion,
        reason: payload.reason,
        card_id: payload.card_id,
        targetPileId: payload.targetPileId
      }
    };
  }

  const activeMatchFailure = confirmActiveMatch(state, payload);
  if (activeMatchFailure) {
    return activeMatchFailure;
  }

  const playerOrFailure = confirmSenderPlayer(state, sender, payload);
  if ((playerOrFailure as ApplyMoveResult).accepted === false) {
    return playerOrFailure as ApplyMoveResult;
  }
  const player = playerOrFailure as PlayerMatchState;

  const connectionFailure = confirmAllPlayersConnected(
    state,
    player.userId,
    payload
  );
  if (connectionFailure) {
    return connectionFailure;
  }

  const pileOrFailure = getTargetPile(state, payload);
  if ((pileOrFailure as ApplyMoveResult).accepted === false) {
    return pileOrFailure as ApplyMoveResult;
  }
  const targetPile = pileOrFailure as Card[];
  const topCard = targetPile[targetPile.length - 1];
  if (!topCard) {
    return rejectMove(
      state,
      player.userId,
      MoveRejectionReason.InvalidTargetPile,
      payload
    );
  }

  const cardIndex = findCardInHand(player, payload.card_id);
  if (cardIndex === -1) {
    return rejectMove(
      state,
      player.userId,
      MoveRejectionReason.CardNotInHand,
      payload
    );
  }

  const playedCard = player.hand[cardIndex];
  if (!cardsMatch(playedCard, topCard)) {
    return rejectMove(
      state,
      player.userId,
      MoveRejectionReason.CardDoesNotMatch,
      payload
    );
  }

  player.hand.splice(cardIndex, 1);
  targetPile.push(playedCard);
  drawReplacementIfAvailable(player);
  state.stateVersion += 1;

  return {
    accepted: true,
    playerId: player.userId,
    gameEnded: updateWinnerIfNeeded(state, player, nowMs)
  };
}
