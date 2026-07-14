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

type MoveRejectedResult = {
  accepted: false;
  playerId: string | null;
  rejection: MoveRejectedPayload;
};

type ApplyMoveResult =
  | {
      accepted: true;
      playerId: string;
      gameEnded: boolean;
    }
  | MoveRejectedResult;

type ValidatedSubmitMove = {
  playerId: string;
  payload: SubmitMovePayload;
  receivedAtMs: number;
  sequence: number;
};

type ValidateSubmitMoveResult =
  | {
      accepted: true;
      move: ValidatedSubmitMove;
    }
  | MoveRejectedResult;

type PendingMoveBatchResult = {
  changed: boolean;
  gameEnded: boolean;
  acceptedPlayerIds: string[];
  rejections: MoveRejectedResult[];
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
): MoveRejectedResult {
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
): MoveRejectedResult | null {
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
): PlayerMatchState | MoveRejectedResult {
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
): MoveRejectedResult | null {
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
): Card[] | MoveRejectedResult {
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

function validateSubmitMovePayload(
  state: SprintMatchState,
  sender: nkruntime.Presence | null,
  payload: SubmitMovePayload,
  receivedAtMs: number,
  sequence: number
): ValidateSubmitMoveResult {
  const activeMatchFailure = confirmActiveMatch(state, payload);
  if (activeMatchFailure) {
    return activeMatchFailure;
  }

  const playerOrFailure = confirmSenderPlayer(state, sender, payload);
  if ((playerOrFailure as MoveRejectedResult).accepted === false) {
    return playerOrFailure as MoveRejectedResult;
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
  if ((pileOrFailure as MoveRejectedResult).accepted === false) {
    return pileOrFailure as MoveRejectedResult;
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

  return {
    accepted: true,
    move: {
      playerId: player.userId,
      payload: payload,
      receivedAtMs: receivedAtMs,
      sequence: sequence
    }
  };
}

function validateSubmitMoveCandidate(
  state: SprintMatchState,
  sender: nkruntime.Presence | null,
  data: ArrayBuffer | string | null,
  receivedAtMs: number,
  sequence: number
): ValidateSubmitMoveResult {
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

  return validateSubmitMovePayload(
    state,
    sender,
    payload,
    receivedAtMs,
    sequence
  );
}

function validatePendingSubmitMove(
  state: SprintMatchState,
  move: ValidatedSubmitMove
): MoveRejectedResult | null {
  const result = validateSubmitMovePayload(
    state,
    {userId: move.playerId} as nkruntime.Presence,
    move.payload,
    move.receivedAtMs,
    move.sequence
  );

  if (result.accepted === true) {
    return null;
  }

  return result;
}

function moveCardWithoutVersionIncrement(
  state: SprintMatchState,
  move: ValidatedSubmitMove
): void {
  const player = state.players[move.playerId];
  const targetPile = state.centerPiles[move.payload.targetPileId];
  const cardIndex = findCardInHand(player, move.payload.card_id);
  const playedCard = player.hand[cardIndex];

  player.hand.splice(cardIndex, 1);
  targetPile.push(playedCard);
  drawReplacementIfAvailable(player);
}

function applyValidatedSubmitMove(
  state: SprintMatchState,
  move: ValidatedSubmitMove,
  nowMs: number = Date.now()
): ApplyMoveResult {
  const validationFailure = validatePendingSubmitMove(state, move);
  if (validationFailure) {
    return validationFailure;
  }

  const player = state.players[move.playerId];
  moveCardWithoutVersionIncrement(state, move);
  state.stateVersion += 1;

  return {
    accepted: true,
    playerId: move.playerId,
    gameEnded: updateWinnerIfNeeded(state, player, nowMs)
  };
}

function otherPlayerId(state: SprintMatchState, userId: string): string | null {
  if (state.playerOrder[0] === userId) {
    return state.playerOrder[1];
  }
  if (state.playerOrder[1] === userId) {
    return state.playerOrder[0];
  }
  return null;
}

function chooseTieBreakerMove(
  state: SprintMatchState,
  moves: ValidatedSubmitMove[]
): ValidatedSubmitMove {
  const priorityUserId = state.nextTieBreakerPlayerId;
  if (priorityUserId) {
    const priorityMove = moves.find((move) => move.playerId === priorityUserId);
    if (priorityMove) {
      return priorityMove;
    }
  }

  for (const userId of state.playerOrder) {
    const playerMove = moves.find((move) => move.playerId === userId);
    if (playerMove) {
      return playerMove;
    }
  }

  return moves[0];
}

function advanceTieBreaker(state: SprintMatchState, winnerId: string): void {
  state.nextTieBreakerPlayerId = otherPlayerId(state, winnerId);
}

function playerHasFinished(state: SprintMatchState, userId: string): boolean {
  const player = state.players[userId];
  return player !== undefined && player.hand.length === 0 && player.deck.length === 0;
}

function chooseBatchWinner(
  state: SprintMatchState,
  winnerIds: string[]
): string {
  const priorityUserId = state.nextTieBreakerPlayerId;
  if (priorityUserId && winnerIds.indexOf(priorityUserId) !== -1) {
    return priorityUserId;
  }

  for (const userId of state.playerOrder) {
    if (winnerIds.indexOf(userId) !== -1) {
      return userId;
    }
  }

  return winnerIds[0];
}

function finishMatchWithWinner(
  state: SprintMatchState,
  winnerId: string,
  nowMs: number
): void {
  state.status = MatchStatus.Finished;
  state.winnerId = winnerId;
  state.endReason = MatchEndReason.Normal;
  state.endedAtMs = nowMs;
  state.resultPersistencePending = true;
  state.resultPersisted = false;
  state.pendingMoves = [];
}

function samePileLoserRejection(
  state: SprintMatchState,
  move: ValidatedSubmitMove
): MoveRejectedResult {
  return rejectMove(
    state,
    move.playerId,
    MoveRejectionReason.StaleMove,
    move.payload
  );
}

function applyPendingSubmitMoveBatch(
  state: SprintMatchState,
  moves: ValidatedSubmitMove[],
  nowMs: number = Date.now()
): PendingMoveBatchResult {
  const result: PendingMoveBatchResult = {
    changed: false,
    gameEnded: false,
    acceptedPlayerIds: [],
    rejections: []
  };
  const validMoves: ValidatedSubmitMove[] = [];

  moves
    .slice()
    .sort((left, right) => left.sequence - right.sequence)
    .forEach((move) => {
      const validationFailure = validatePendingSubmitMove(state, move);
      if (validationFailure) {
        result.rejections.push(validationFailure);
      } else {
        validMoves.push(move);
      }
    });

  const selectedMoves: ValidatedSubmitMove[] = [];
  [PileId.Pile1, PileId.Pile2].forEach((pileId) => {
    const pileMoves = validMoves.filter(
      (move) => move.payload.targetPileId === pileId
    );
    if (pileMoves.length === 1) {
      selectedMoves.push(pileMoves[0]);
      return;
    }

    if (pileMoves.length > 1) {
      const winningMove = chooseTieBreakerMove(state, pileMoves);
      selectedMoves.push(winningMove);
      advanceTieBreaker(state, winningMove.playerId);
      pileMoves.forEach((move) => {
        if (move !== winningMove) {
          result.rejections.push(samePileLoserRejection(state, move));
        }
      });
    }
  });

  selectedMoves
    .slice()
    .sort((left, right) => left.sequence - right.sequence)
    .forEach((move) => {
      const validationFailure = validatePendingSubmitMove(state, move);
      if (validationFailure) {
        result.rejections.push(validationFailure);
        return;
      }

      moveCardWithoutVersionIncrement(state, move);
      result.acceptedPlayerIds.push(move.playerId);
    });

  if (result.acceptedPlayerIds.length === 0) {
    return result;
  }

  state.stateVersion += 1;
  result.changed = true;
  result.rejections.forEach((rejection) => {
    rejection.rejection.stateVersion = state.stateVersion;
  });

  const winnerIds = result.acceptedPlayerIds.filter((userId) =>
    playerHasFinished(state, userId)
  );
  if (winnerIds.length > 0) {
    const winnerId =
      winnerIds.length === 1 ? winnerIds[0] : chooseBatchWinner(state, winnerIds);
    if (winnerIds.length > 1) {
      advanceTieBreaker(state, winnerId);
    }
    finishMatchWithWinner(state, winnerId, nowMs);
    result.gameEnded = true;
  }

  return result;
}

function applySubmitMove(
  state: SprintMatchState,
  sender: nkruntime.Presence | null,
  data: ArrayBuffer | string | null,
  nowMs: number = Date.now()
): ApplyMoveResult {
  const validated = validateSubmitMoveCandidate(state, sender, data, nowMs, 0);
  if (validated.accepted === false) {
    return validated;
  }

  return applyValidatedSubmitMove(state, validated.move, nowMs);
}
