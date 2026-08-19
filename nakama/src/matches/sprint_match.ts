const invalidMatchParametersMessage =
  "expectedUserIds must contain exactly two distinct, non-empty user IDs";
const unauthorizedJoinMessage = "This user was not assigned to this match.";
const disconnectTimeoutMs = 30 * 1000;
// Fairness resolution window. Sized adaptively per match from the *gap*
// between the players' measured RTT ((max - min) / 2, clamped to [min,
// max]) — two equally-latent players need no compensation regardless of how
// high that shared latency is, only a real difference between them does.
// moveFairnessWindowMs is the fallback used until both players have an RTT
// estimate.
const moveFairnessWindowMs = 150;
const minFairnessWindowMs = 100;
const maxFairnessWindowMs = 300;
// A conservative EMA keeps the degraded-connection indicator and fairness
// window responsive without letting one noisy move replace the whole estimate.
const rttEmaAlpha = 0.25;
const waitingMatchTimeoutMs = 5 * 60 * 1000;
const activeIdleTimeoutMs = 15 * 60 * 1000;
const finishedEmptyGraceMs = 5 * 1000;
const rematchTimeoutMs = 30 * 1000;
const rematchCountdownMs = 5 * 1000;

function displayNameFromPresence(presence: nkruntime.Presence): string | null {
  const username = presence.username;
  if (typeof username === "string" && username.trim().length > 0) {
    return username.trim();
  }

  return null;
}

function displayNameFromAccount(
  nk: nkruntime.Nakama | null,
  userId: string,
  logger: nkruntime.Logger
): string | null {
  if (!nk) {
    return null;
  }

  try {
    const account = nk.accountGetId(userId);
    const displayName = account && account.user && account.user.displayName;
    if (typeof displayName === "string" && displayName.trim().length > 0) {
      return displayName.trim();
    }
  } catch (error) {
    logger.warn(
      "Could not resolve sprint player display name for user %s: %s",
      userId,
      error
    );
  }

  return null;
}

function resolvePlayerDisplayName(
  nk: nkruntime.Nakama | null,
  logger: nkruntime.Logger,
  presence: nkruntime.Presence,
  existingDisplayName?: string
): string {
  return (
    displayNameFromAccount(nk, presence.userId, logger) ||
    displayNameFromPresence(presence) ||
    existingDisplayName ||
    "Player"
  );
}

function parsePlayerOrder(
  params: {[key: string]: any}
): [string, string] | null {
  if (!params || !Array.isArray(params.expectedUserIds)) {
    return null;
  }

  const expectedUserIds = params.expectedUserIds;
  if (expectedUserIds.length !== 2) {
    return null;
  }

  const playerAId = expectedUserIds[0];
  const playerBId = expectedUserIds[1];
  const idsAreValid =
    typeof playerAId === "string" &&
    playerAId.trim().length > 0 &&
    typeof playerBId === "string" &&
    playerBId.trim().length > 0 &&
    playerAId !== playerBId;

  return idsAreValid ? [playerAId, playerBId] : null;
}

function createWaitingMatchState(
  playerOrder: [string, string],
  nowMs: number = Date.now()
): SprintMatchState {
  const playerAId = playerOrder[0];
  const playerBId = playerOrder[1];
  const players: {[userId: string]: PlayerMatchState} = {};

  players[playerAId] = {
    userId: playerAId,
    displayName: "Player",
    hand: [],
    deck: [],
    connected: false,
    disconnectedAtMs: null,
    rttEstimateMs: null,
    rttSampleSequence: 0,
    lastStateSentAtMs: null
  };
  players[playerBId] = {
    userId: playerBId,
    displayName: "Player",
    hand: [],
    deck: [],
    connected: false,
    disconnectedAtMs: null,
    rttEstimateMs: null,
    rttSampleSequence: 0,
    lastStateSentAtMs: null
  };

  return {
    roundNumber: 1,
    rematchResponses: {
      [playerAId]: "pending",
      [playerBId]: "pending"
    },
    rematchPhase: "idle",
    rematchRequestedAtMs: null,
    roundStartsAtMs: null,
    rematchExpired: false,
    rematchUnavailable: false,
    status: MatchStatus.Waiting,
    playerOrder: playerOrder,
    players: players,
    presences: {},
    centerPiles: {
      pile_1: [],
      pile_2: []
    },
    stateVersion: 0,
    winnerId: null,
    endReason: null,
    startedAtMs: null,
    endedAtMs: null,
    resultPersistencePending: false,
    resultPersisted: false,
    matchCode: null,
    pendingMoves: [],
    nextPendingMoveSequence: 0,
    nextTieBreakerPlayerId: playerAId,
    createdAtMs: nowMs,
    lastActivityAtMs: nowMs,
    finishedEmptySinceMs: null,
    resumablePointersPublished: false
  };
}

// Used for a match created via a shareable code: the creator is known, but
// the second seat stays open (UNASSIGNED_PLAYER_ID) until someone redeems
// the code and joins.
function createOpenWaitingMatchState(
  creatorId: string,
  code: string,
  nowMs: number = Date.now()
): SprintMatchState {
  const players: {[userId: string]: PlayerMatchState} = {};

  players[creatorId] = {
    userId: creatorId,
    displayName: "Player",
    hand: [],
    deck: [],
    connected: false,
    disconnectedAtMs: null,
    rttEstimateMs: null,
    rttSampleSequence: 0,
    lastStateSentAtMs: null
  };

  return {
    roundNumber: 1,
    rematchResponses: {
      [creatorId]: "pending"
    },
    rematchPhase: "idle",
    rematchRequestedAtMs: null,
    roundStartsAtMs: null,
    rematchExpired: false,
    rematchUnavailable: false,
    status: MatchStatus.Waiting,
    playerOrder: [creatorId, UNASSIGNED_PLAYER_ID],
    players: players,
    presences: {},
    centerPiles: {
      pile_1: [],
      pile_2: []
    },
    stateVersion: 0,
    winnerId: null,
    endReason: null,
    startedAtMs: null,
    endedAtMs: null,
    resultPersistencePending: false,
    resultPersisted: false,
    matchCode: code,
    pendingMoves: [],
    nextPendingMoveSequence: 0,
    nextTieBreakerPlayerId: creatorId,
    createdAtMs: nowMs,
    lastActivityAtMs: nowMs,
    finishedEmptySinceMs: null,
    resumablePointersPublished: false
  };
}

// Deletes the match_codes storage record once neither assigned player is
// still connected to the match, so a stale code can no longer resolve to a
// match nobody is coming back to. Kept alive while at least one of the two
// players remains connected, so a dropped player can still redeem the code
// again to look up the matchId and reconnect.
function invalidateMatchCode(
  nk: nkruntime.Nakama,
  logger: nkruntime.Logger,
  state: SprintMatchState
): void {
  if (!state.matchCode) {
    return;
  }

  nk.storageDelete([
    {collection: MATCH_CODE_COLLECTION, key: state.matchCode, userId: SYSTEM_USER_ID}
  ]);
  logger.info("Invalidated sprint match code %s", state.matchCode);
  state.matchCode = null;
}

function connectedPresenceCount(state: SprintMatchState): number {
  return Object.keys(state.presences).length;
}

type MatchCleanupDecision = {
  terminate: boolean;
  reason: string | null;
};

function markFinishedEmptyState(
  state: SprintMatchState,
  nowMs: number
): void {
  if (
    state.status === MatchStatus.Finished &&
    connectedPresenceCount(state) === 0
  ) {
    if (state.finishedEmptySinceMs === null) {
      state.finishedEmptySinceMs = nowMs;
    }
    return;
  }

  state.finishedEmptySinceMs = null;
}

function shouldTerminateSprintMatch(
  state: SprintMatchState,
  nowMs: number
): MatchCleanupDecision {
  markFinishedEmptyState(state, nowMs);

  if (
    state.status === MatchStatus.Waiting &&
    nowMs - state.createdAtMs >= waitingMatchTimeoutMs
  ) {
    return {
      terminate: true,
      reason: "waiting match timed out"
    };
  }

  if (
    state.status === MatchStatus.Finished &&
    connectedPresenceCount(state) === 0 &&
    state.finishedEmptySinceMs !== null &&
    nowMs - state.finishedEmptySinceMs >= finishedEmptyGraceMs
  ) {
    if (state.resultPersistencePending && !state.resultPersisted) {
      return {
        terminate: false,
        reason: "finished match is waiting for result persistence"
      };
    }

    return {
      terminate: true,
      reason: "finished match is empty"
    };
  }

  if (
    state.status === MatchStatus.Active &&
    nowMs - state.lastActivityAtMs >= activeIdleTimeoutMs
  ) {
    return {
      terminate: false,
      reason: "active match idle timeout"
    };
  }

  return {
    terminate: false,
    reason: null
  };
}

function buildConnectionChangedPayload(
  state: SprintMatchState,
  changes: ConnectionChange[],
  serverNowMs: number = Date.now()
): ConnectionChangedPayload {
  const connectedUserIds = state.playerOrder.filter(
    (userId) => state.presences[userId] !== undefined
  );
  const disconnectDeadlinesMs = state.status === MatchStatus.Active
    ? state.playerOrder
        .map((userId) => state.players[userId]?.disconnectedAtMs)
        .filter((disconnectedAtMs): disconnectedAtMs is number =>
          disconnectedAtMs !== null && disconnectedAtMs !== undefined
        )
        .map((disconnectedAtMs) => disconnectedAtMs + disconnectTimeoutMs)
    : [];

  return {
    changes: changes,
    connectedUserIds: connectedUserIds,
    connectedCount: connectedUserIds.length,
    expectedCount: state.playerOrder.length,
    disconnectDeadlineMs:
      disconnectDeadlinesMs.length > 0
        ? Math.min.apply(null, disconnectDeadlinesMs)
        : null,
    disconnectGraceMs: disconnectTimeoutMs,
    serverTimeMs: serverNowMs
  };
}

function broadcastConnectionChanged(
  dispatcher: nkruntime.MatchDispatcher,
  state: SprintMatchState,
  changes: ConnectionChange[],
  serverNowMs: number = Date.now()
): void {
  if (changes.length === 0) {
    return;
  }

  dispatcher.broadcastMessage(
    ServerOpcode.ConnectionChanged,
    JSON.stringify(buildConnectionChangedPayload(state, changes, serverNowMs))
  );
}

function broadcastRematchStatus(
  dispatcher: nkruntime.MatchDispatcher,
  payload: RematchStatusPayload,
  presences?: nkruntime.Presence[]
): void {
  dispatcher.broadcastMessage(
    ServerOpcode.RematchStatus,
    JSON.stringify(payload),
    presences
  );
}

function roundStartingPayload(
  state: SprintMatchState,
  nowMs: number
): RematchStatusPayload {
  const startsAtMs = state.roundStartsAtMs || nowMs;
  return {
    status: "starting",
    roundNumber:
      state.status === MatchStatus.Waiting
        ? state.roundNumber
        : state.roundNumber + 1,
    startsInMs: Math.max(0, startsAtMs - nowMs),
    startsAtMs: startsAtMs,
    serverTimeMs: nowMs
  };
}

function beginRematchCountdown(
  dispatcher: nkruntime.MatchDispatcher,
  state: SprintMatchState,
  nowMs: number
): void {
  state.rematchPhase = "countdown";
  state.roundStartsAtMs = nowMs + rematchCountdownMs;
  broadcastRematchStatus(dispatcher, roundStartingPayload(state, nowMs));
}

function currentRematchStatusPayload(
  state: SprintMatchState,
  nowMs: number
): RematchStatusPayload | null {
  if (state.rematchPhase === "unavailable" || state.rematchUnavailable) {
    return {status: "unavailable"};
  }
  if (state.rematchPhase === "expired" || state.rematchExpired) {
    return {status: "expired"};
  }
  if (state.roundStartsAtMs !== null) {
    return roundStartingPayload(state, nowMs);
  }
  if (state.rematchPhase === "awaiting_persistence") {
    return {status: "preparing", roundNumber: state.roundNumber + 1};
  }
  const declinedBy = state.playerOrder.find(
    (userId) => state.rematchResponses[userId] === "declined"
  );
  if (declinedBy) {
    return {status: "declined", declinedBy: declinedBy};
  }
  const requestedBy = state.playerOrder.find(
    (userId) => state.rematchResponses[userId] === "accepted"
  );
  if (requestedBy && state.rematchRequestedAtMs !== null) {
    return {
      status: "requested",
      requestedBy: requestedBy,
      expiresInMs: Math.max(
        0,
        rematchTimeoutMs - (nowMs - state.rematchRequestedAtMs)
      )
    };
  }
  return null;
}

function parseRematchDecision(
  data: ArrayBuffer | string | null
): boolean | null {
  let payload: any;
  try {
    payload = JSON.parse(decodeMatchMessageData(data));
  } catch (_) {
    return null;
  }
  return payload && typeof payload.accept === "boolean"
    ? payload.accept
    : null;
}

function handleRematchDecision(
  dispatcher: nkruntime.MatchDispatcher,
  state: SprintMatchState,
  sender: nkruntime.Presence | null,
  data: any,
  nowMs: number
): boolean {
  const userId = sender?.userId;
  const accept = parseRematchDecision(data);
  if (
    state.status !== MatchStatus.Finished ||
    state.endReason !== MatchEndReason.Normal ||
    !userId ||
    state.playerOrder.indexOf(userId) === -1 ||
    accept === null ||
    state.rematchExpired ||
    state.rematchUnavailable ||
    (state.rematchPhase !== "idle" && state.rematchPhase !== "requested") ||
    !bothPlayersConnected(state)
  ) {
    return false;
  }

  if (
    state.rematchRequestedAtMs !== null &&
    nowMs - state.rematchRequestedAtMs >= rematchTimeoutMs
  ) {
    state.rematchExpired = true;
    state.rematchPhase = "expired";
    broadcastRematchStatus(dispatcher, {status: "expired"});
    return false;
  }

  const current = state.rematchResponses[userId];
  const next: RematchResponse = accept ? "accepted" : "declined";
  if (current === next) {
    return true;
  }
  if (current === "declined") {
    return false;
  }

  state.rematchResponses[userId] = next;
  state.lastActivityAtMs = nowMs;
  if (!accept) {
    state.rematchPhase = "declined";
    broadcastRematchStatus(dispatcher, {
      status: "declined",
      declinedBy: userId
    });
    return true;
  }

  if (state.rematchRequestedAtMs === null) {
    state.rematchRequestedAtMs = nowMs;
  }
  state.rematchPhase = "requested";
  const bothAccepted = state.playerOrder.every(
    (playerId) => state.rematchResponses[playerId] === "accepted"
  );
  if (bothAccepted) {
    if (state.resultPersisted && !state.resultPersistencePending) {
      beginRematchCountdown(dispatcher, state, nowMs);
    } else {
      state.rematchPhase = "awaiting_persistence";
      broadcastRematchStatus(dispatcher, {
        status: "preparing",
        roundNumber: state.roundNumber + 1
      });
    }
  } else {
    broadcastRematchStatus(dispatcher, {
      status: "requested",
      requestedBy: userId,
      expiresInMs: rematchTimeoutMs
    });
  }
  return true;
}

function sendMatchStarted(
  dispatcher: nkruntime.MatchDispatcher,
  state: SprintMatchState
): void {
  const serverNowMs = Date.now();
  state.playerOrder.forEach((userId) => {
    const presence = state.presences[userId];
    if (!presence) {
      throw new Error("Cannot send matchStarted without both player presences.");
    }

    dispatcher.broadcastMessage(
      ServerOpcode.MatchStarted,
      JSON.stringify(buildPlayerStateView(state, userId, serverNowMs)),
      [presence]
    );
    state.players[userId].lastStateSentAtMs = serverNowMs;
  });
}

function sendPlayerStateViews(
  dispatcher: nkruntime.MatchDispatcher,
  state: SprintMatchState,
  opcode: ServerOpcode,
  transitions: AppliedCardTransition[] = []
): void {
  const serverNowMs = Date.now();
  state.playerOrder.forEach((userId) => {
    const presence = state.presences[userId];
    if (!presence) {
      return;
    }

    dispatcher.broadcastMessage(
      opcode,
      JSON.stringify(
        buildPlayerStateView(state, userId, serverNowMs, transitions)
      ),
      [presence]
    );
    state.players[userId].lastStateSentAtMs = serverNowMs;
  });
}

function sendMoveRejected(
  dispatcher: nkruntime.MatchDispatcher,
  state: SprintMatchState,
  result: ApplyMoveResult
): void {
  if (result.accepted) {
    return;
  }

  const rejectedResult = result as {
    accepted: false;
    playerId: string | null;
    rejection: MoveRejectedPayload;
  };
  const playerId = rejectedResult.playerId;
  const presence = playerId ? state.presences[playerId] : undefined;
  if (!presence) {
    return;
  }

  dispatcher.broadcastMessage(
    ServerOpcode.MoveRejected,
    JSON.stringify(rejectedResult.rejection),
    [presence]
  );
}

function enqueuePendingSubmitMove(
  state: SprintMatchState,
  move: ValidatedSubmitMove
): ApplyMoveResult | null {
  const existingMove = state.pendingMoves.find(
    (pendingMove) => pendingMove.playerId === move.playerId
  );
  if (existingMove) {
    return rejectMove(
      state,
      move.playerId,
      MoveRejectionReason.StaleMove,
      move.payload
    );
  }

  state.pendingMoves.push(move);
  return null;
}

// Sizes the resolution window from the *gap* between the two players'
// measured RTT, not their absolute latency: two equally slow connections
// resolve near-instantly (window floors at min), since neither player has a
// network advantage over the other to compensate for, while a real
// difference between them widens the window so the slower player's move can
// still arrive and be compared fairly. (max(RTT) - min(RTT)) / 2, clamped to
// [min, max]. Falls back to the default until both players have an RTT
// estimate — a gap needs two data points.
function computeFairnessWindowMs(state: SprintMatchState): number {
  const estimates: number[] = [];
  state.playerOrder.forEach((userId) => {
    const rtt = state.players[userId]?.rttEstimateMs;
    if (typeof rtt === "number" && isFinite(rtt) && rtt >= 0) {
      estimates.push(rtt);
    }
  });
  if (estimates.length < 2) {
    return moveFairnessWindowMs;
  }

  const maxRttMs = estimates.reduce((max, rtt) => Math.max(max, rtt), -Infinity);
  const minRttMs = estimates.reduce((min, rtt) => Math.min(min, rtt), Infinity);
  const windowMs = Math.round((maxRttMs - minRttMs) / 2);
  return Math.min(maxFairnessWindowMs, Math.max(minFairnessWindowMs, windowMs));
}

function collectReadyPendingSubmitMoves(
  state: SprintMatchState,
  nowMs: number,
  fairnessWindowMs: number = computeFairnessWindowMs(state)
): ValidatedSubmitMove[] {
  if (state.pendingMoves.length === 0) {
    return [];
  }

  const earliestReceivedAtMs = state.pendingMoves.reduce(
    (earliest, move) => Math.min(earliest, move.receivedAtMs),
    state.pendingMoves[0].receivedAtMs
  );
  const batchDeadlineMs = earliestReceivedAtMs + fairnessWindowMs;
  if (nowMs < batchDeadlineMs) {
    return [];
  }

  const readyMoves: ValidatedSubmitMove[] = [];
  const waitingMoves: ValidatedSubmitMove[] = [];
  state.pendingMoves.forEach((move) => {
    if (move.receivedAtMs <= batchDeadlineMs) {
      readyMoves.push(move);
    } else {
      waitingMoves.push(move);
    }
  });
  state.pendingMoves = waitingMoves;

  return readyMoves.sort(compareByEffectiveResponseTime);
}

function sendPlayerStateView(
  dispatcher: nkruntime.MatchDispatcher,
  state: SprintMatchState,
  userId: string,
  presence: nkruntime.Presence,
  opcode: ServerOpcode
): void {
  const serverNowMs = Date.now();
  dispatcher.broadcastMessage(
    opcode,
    JSON.stringify(buildPlayerStateView(state, userId, serverNowMs)),
    [presence]
  );
  state.players[userId].lastStateSentAtMs = serverNowMs;
}

function recordPlayerRttSample(
  player: PlayerMatchState,
  rawRttMs: number
): void {
  const sampleMs = Math.max(0, Math.floor(rawRttMs));
  const previousEstimate =
    typeof player.rttEstimateMs === "number" &&
    isFinite(player.rttEstimateMs) &&
    player.rttEstimateMs >= 0
      ? player.rttEstimateMs
      : null;
  player.rttEstimateMs = previousEstimate === null
    ? sampleMs
    : Math.round(
        previousEstimate * (1 - rttEmaAlpha) + sampleMs * rttEmaAlpha
      );
  const previousSequence =
    typeof player.rttSampleSequence === "number" &&
    isFinite(player.rttSampleSequence) &&
    player.rttSampleSequence >= 0
      ? Math.floor(player.rttSampleSequence)
      : 0;
  player.rttSampleSequence = previousSequence + 1;
}

function finishMatchByForfeit(
  state: SprintMatchState,
  forfeitingUserId: string,
  nowMs: number
): boolean {
  if (state.status !== MatchStatus.Active) {
    return false;
  }

  const forfeitingPlayer = state.players[forfeitingUserId];
  if (!forfeitingPlayer) {
    return false;
  }

  const winnerId =
    state.playerOrder[0] === forfeitingUserId
      ? state.playerOrder[1]
      : state.playerOrder[0];
  if (!state.players[winnerId]) {
    return false;
  }

  state.status = MatchStatus.Finished;
  state.winnerId = winnerId;
  state.endReason = MatchEndReason.Forfeit;
  state.endedAtMs = nowMs;
  state.stateVersion += 1;
  state.resultPersistencePending = true;
  state.resultPersisted = false;
  state.pendingMoves = [];
  state.lastActivityAtMs = nowMs;
  state.finishedEmptySinceMs = connectedPresenceCount(state) === 0 ? nowMs : null;
  return true;
}

function finishMatchAsAbandoned(
  state: SprintMatchState,
  nowMs: number
): boolean {
  if (state.status !== MatchStatus.Active) {
    return false;
  }

  state.status = MatchStatus.Finished;
  state.winnerId = null;
  state.endReason = MatchEndReason.Abandoned;
  state.endedAtMs = nowMs;
  state.stateVersion += 1;
  state.resultPersistencePending = false;
  state.resultPersisted = false;
  state.pendingMoves = [];
  state.lastActivityAtMs = nowMs;
  state.finishedEmptySinceMs = connectedPresenceCount(state) === 0 ? nowMs : null;
  return true;
}

type DisconnectTimeoutResult = {
  finished: boolean;
  reason: MatchEndReason.Forfeit | MatchEndReason.Abandoned | null;
};

function resolveDisconnectTimeout(
  state: SprintMatchState,
  nowMs: number,
  timeoutMs: number = disconnectTimeoutMs
): DisconnectTimeoutResult {
  if (state.status !== MatchStatus.Active) {
    return {finished: false, reason: null};
  }

  const disconnectedPlayers = state.playerOrder.filter((userId) => {
    const player = state.players[userId];
    return player && !player.connected && player.disconnectedAtMs !== null;
  });
  const timedOutPlayers = disconnectedPlayers.filter((userId) => {
    const disconnectedAtMs = state.players[userId].disconnectedAtMs;
    return disconnectedAtMs !== null && nowMs - disconnectedAtMs >= timeoutMs;
  });

  if (timedOutPlayers.length === 0) {
    return {finished: false, reason: null};
  }

  const connectedPlayers = state.playerOrder.filter((userId) => {
    const player = state.players[userId];
    return player?.connected === true && state.presences[userId] !== undefined;
  });

  if (connectedPlayers.length === 1 && disconnectedPlayers.length === 1) {
    return {
      finished: finishMatchByForfeit(state, disconnectedPlayers[0], nowMs),
      reason: MatchEndReason.Forfeit
    };
  }

  if (connectedPlayers.length === 0 && disconnectedPlayers.length === state.playerOrder.length) {
    return {
      finished: finishMatchAsAbandoned(state, nowMs),
      reason: MatchEndReason.Abandoned
    };
  }

  return {finished: false, reason: null};
}

function abandonMatch(
  state: SprintMatchState,
  sender: nkruntime.Presence | null,
  nowMs: number = Date.now()
): boolean {
  const userId = sender?.userId;
  if (!userId || state.playerOrder.indexOf(userId) === -1) {
    return false;
  }

  return finishMatchByForfeit(state, userId, nowMs);
}

function resolveAndBroadcastStuckState(
  dispatcher: nkruntime.MatchDispatcher,
  state: SprintMatchState,
  logger: nkruntime.Logger,
  random: RandomSource = Math.random,
  maxAttempts: number = MAX_STUCK_RESET_ATTEMPTS
): void {
  const result = resolveStuckState(state, () => {
    logger.info(
      "Resetting stuck sprint center piles at version %d",
      state.stateVersion
    );
    sendPlayerStateViews(dispatcher, state, ServerOpcode.StuckReset);
  }, random, maxAttempts);

  if (result.blockedBySingleCardPiles) {
    logger.warn(
      "Sprint match is stuck but single-card pile replacement could not run safely"
    );
  } else if (result.stillStuck) {
    logger.warn(
      "Sprint match remains stuck after %d center-pile reset attempts",
      result.resetCount
    );
  }
}

function sprintMatchInit(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  params: {[key: string]: any}
): {state: SprintMatchState; tickRate: number; label: string} | null {
  const nowMs = Date.now();

  if (params && params.mode === "code") {
    const creatorId = params.creatorId;
    if (typeof creatorId !== "string" || creatorId.trim().length === 0) {
      logger.error("Cannot initialize sprint match: creatorId is required for a code match.");
      return null;
    }

    const code = params.code;
    if (typeof code !== "string" || code.trim().length === 0) {
      logger.error("Cannot initialize sprint match: code is required for a code match.");
      return null;
    }

    logger.info("Initializing open sprint match for creator: %s", creatorId);

    return {
      state: createOpenWaitingMatchState(creatorId, code, nowMs),
      tickRate: 30,
      label: JSON.stringify({mode: "sprint_by_code"})
    };
  }

  const playerOrder = parsePlayerOrder(params);
  if (playerOrder === null) {
    logger.error("Cannot initialize sprint match: %s.", invalidMatchParametersMessage);
    return null;
  }

  logger.info(
    "Initializing waiting sprint match for players: %s",
    playerOrder.join(",")
  );

  return {
    state: createWaitingMatchState(playerOrder, nowMs),
    tickRate: 30,
    label: JSON.stringify({
      mode: "sprint_quickplay",
      expectedPlayers: playerOrder.length
    })
  };
}

function sprintMatchJoinAttempt(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  dispatcher: nkruntime.MatchDispatcher,
  tick: number,
  state: SprintMatchState,
  presence: nkruntime.Presence,
  metadata: {[key: string]: any}
): {state: SprintMatchState; accept: boolean; rejectMessage?: string} {
  const isExpectedUser = state.playerOrder.indexOf(presence.userId) !== -1;
  const hasOpenSecondSeat = state.playerOrder[1] === UNASSIGNED_PLAYER_ID;
  const canFillOpenSeat =
    hasOpenSecondSeat && presence.userId !== state.playerOrder[0];

  if (!isExpectedUser && !canFillOpenSeat) {
    logger.warn("Rejected unauthorized sprint match join from user: %s", presence.userId);
    return {
      state: state,
      accept: false,
      rejectMessage: unauthorizedJoinMessage
    };
  }

  return {
    state: state,
    accept: true
  };
}

function sprintMatchJoin(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  dispatcher: nkruntime.MatchDispatcher,
  tick: number,
  state: SprintMatchState,
  presences: nkruntime.Presence[]
): {state: SprintMatchState} {
  const nowMs = Date.now();
  const changes: ConnectionChange[] = [];
  const resyncPresences: nkruntime.Presence[] = [];

  presences.forEach((presence) => {
    if (
      state.playerOrder[1] === UNASSIGNED_PLAYER_ID &&
      presence.userId !== state.playerOrder[0]
    ) {
      state.playerOrder[1] = presence.userId;
      state.players[presence.userId] = {
        userId: presence.userId,
        displayName: resolvePlayerDisplayName(nk, logger, presence),
        hand: [],
        deck: [],
        connected: false,
        disconnectedAtMs: null,
        rttEstimateMs: null,
        rttSampleSequence: 0,
        lastStateSentAtMs: null
      };
      state.rematchResponses[presence.userId] = "pending";
      // The previous projection only contained the creator. Republish both
      // assigned players on the next match tick.
      state.resumablePointersPublished = false;
      logger.info("Sprint match code redeemed by user: %s", presence.userId);
    }

    const player = state.players[presence.userId];
    if (!player) {
      logger.warn(
        "Ignored joined presence for unknown sprint player: %s",
        presence.userId
      );
      return;
    }

    const gameWasAlreadyInitialized = state.status !== MatchStatus.Waiting;
    player.displayName = resolvePlayerDisplayName(
      nk,
      logger,
      presence,
      player.displayName
    );
    state.presences[presence.userId] = presence;
    player.connected = true;
    player.disconnectedAtMs = null;
    state.lastActivityAtMs = nowMs;
    state.finishedEmptySinceMs = null;
    changes.push({
      userId: presence.userId,
      status: ConnectionStatus.Connected
    });

    if (gameWasAlreadyInitialized) {
      resyncPresences.push(presence);
    }
  });

  broadcastConnectionChanged(dispatcher, state, changes, nowMs);

  if (changes.length > 0) {
    logger.info(
      "Sprint match connection change: connected users %s",
      buildConnectionChangedPayload(state, changes).connectedUserIds.join(",")
    );
  }

  if (
    state.status === MatchStatus.Waiting &&
    bothPlayersConnected(state) &&
    state.roundStartsAtMs === null
  ) {
    state.roundStartsAtMs = nowMs + rematchCountdownMs;
    broadcastRematchStatus(dispatcher, roundStartingPayload(state, nowMs));
  } else if (
    state.status === MatchStatus.Waiting &&
    bothPlayersConnected(state) &&
    state.roundStartsAtMs !== null
  ) {
    const joinedPlayers = presences.filter(
      (presence) => state.players[presence.userId] !== undefined
    );
    if (joinedPlayers.length > 0) {
      broadcastRematchStatus(
        dispatcher,
        roundStartingPayload(state, nowMs),
        joinedPlayers
      );
    }
  }

  resyncPresences.forEach((presence) => {
    sendPlayerStateView(
      dispatcher,
      state,
      presence.userId,
      presence,
      ServerOpcode.StateUpdate
    );
    const rematchStatus = currentRematchStatusPayload(state, nowMs);
    if (state.status === MatchStatus.Finished && rematchStatus) {
      broadcastRematchStatus(dispatcher, rematchStatus, [presence]);
    }
    logger.info(
      "Resynchronized sprint player %s at version %d",
      presence.userId,
      state.stateVersion
    );
  });

  return {state: state};
}

function sprintMatchLeave(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  dispatcher: nkruntime.MatchDispatcher,
  tick: number,
  state: SprintMatchState,
  presences: nkruntime.Presence[]
): {state: SprintMatchState} {
  const nowMs = Date.now();
  const changes: ConnectionChange[] = [];

  presences.forEach((presence) => {
    const player = state.players[presence.userId];
    if (!player) {
      logger.warn(
        "Ignored leaving presence for unknown sprint player: %s",
        presence.userId
      );
      return;
    }

    const currentPresence = state.presences[presence.userId];
    if (
      currentPresence &&
      currentPresence.sessionId !== presence.sessionId
    ) {
      logger.info(
        "Ignored stale sprint leave for player %s session %s",
        presence.userId,
        presence.sessionId
      );
      return;
    }
    if (!currentPresence && !player.connected) {
      logger.info(
        "Ignored duplicate sprint leave for disconnected player %s",
        presence.userId
      );
      return;
    }

    delete state.presences[presence.userId];
    player.connected = false;
    if (state.status === MatchStatus.Active) {
      player.disconnectedAtMs = nowMs;
    }
    state.lastActivityAtMs = nowMs;
    changes.push({
      userId: presence.userId,
      status: ConnectionStatus.Disconnected
    });
  });

  broadcastConnectionChanged(dispatcher, state, changes, nowMs);

  if (state.status === MatchStatus.Finished && changes.length > 0) {
    state.rematchUnavailable = true;
    state.rematchPhase = "unavailable";
    state.roundStartsAtMs = null;
    broadcastRematchStatus(dispatcher, {status: "unavailable"});
  }

  if (changes.length > 0) {
    logger.info(
      "Sprint match connection change: connected users %s",
      buildConnectionChangedPayload(state, changes).connectedUserIds.join(",")
    );
  }

  if (state.matchCode && Object.keys(state.presences).length === 0) {
    invalidateMatchCode(nk, logger, state);
  }

  markFinishedEmptyState(state, nowMs);

  return {state: state};
}

function sprintMatchLoop(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  dispatcher: nkruntime.MatchDispatcher,
  tick: number,
  state: SprintMatchState,
  messages: nkruntime.MatchMessage[]
): {state: SprintMatchState} | null {
  const nowMs = Date.now();

  synchronizeResumableMatchPointers(ctx, nk, state, logger);

  if (state.resultPersistencePending && !state.resultPersisted) {
    try {
      persistPendingMatchResult(state, nk);
      logger.info(
        "Persisted sprint match result for winner %s",
        state.winnerId || "unknown"
      );
    } catch (error) {
      logger.error(
        "Could not persist sprint match result; retrying next tick: %s",
        error
      );
    }
  }

  if (
    state.status === MatchStatus.Finished &&
    state.rematchPhase === "awaiting_persistence" &&
    state.resultPersisted &&
    !state.resultPersistencePending &&
    bothPlayersConnected(state)
  ) {
    beginRematchCountdown(dispatcher, state, nowMs);
  }

  if (
    state.status === MatchStatus.Finished &&
    state.rematchPhase === "requested" &&
    state.rematchRequestedAtMs !== null &&
    !state.rematchExpired &&
    nowMs - state.rematchRequestedAtMs >= rematchTimeoutMs
  ) {
    state.rematchExpired = true;
    state.rematchPhase = "expired";
    broadcastRematchStatus(dispatcher, {status: "expired"});
  }

  const timeoutResult = resolveDisconnectTimeout(state, nowMs);
  if (timeoutResult.finished) {
    logger.info(
      "Sprint match finished by disconnect timeout with reason %s and winner %s",
      state.endReason || "unknown",
      state.winnerId || "none"
    );
    sendPlayerStateViews(dispatcher, state, ServerOpcode.GameEnded);
  }

  messages.forEach((message) => {
    if (message.opCode === ClientOpcode.RematchDecision) {
      handleRematchDecision(
        dispatcher,
        state,
        message.sender || null,
        message.data,
        nowMs
      );
      return;
    }
    if (message.opCode === ClientOpcode.AbandonMatch) {
      if (abandonMatch(state, message.sender || null, nowMs)) {
        state.lastActivityAtMs = nowMs;
        logger.info(
          "Sprint match abandoned by player %s; winner %s",
          message.sender?.userId || "unknown",
          state.winnerId || "none"
        );
        sendPlayerStateViews(dispatcher, state, ServerOpcode.GameEnded);
      }
      return;
    }

    if (message.opCode !== ClientOpcode.SubmitMove) {
      return;
    }

    const sequence = state.nextPendingMoveSequence;
    state.nextPendingMoveSequence += 1;
    const result = validateSubmitMoveCandidate(
      state,
      message.sender || null,
      message.data,
      nowMs,
      sequence
    );
    if (result.accepted === false) {
      logger.info(
        "Rejected sprint move from user %s: %s",
        result.playerId || "unknown",
        result.rejection.reason
      );
      sendMoveRejected(dispatcher, state, result);
      return;
    }

    const enqueueFailure = enqueuePendingSubmitMove(state, result.move);
    if (enqueueFailure) {
      logger.info(
        "Rejected duplicate pending sprint move from user %s",
        result.move.playerId
      );
      sendMoveRejected(dispatcher, state, enqueueFailure);
      return;
    }

    // Refresh this player's RTT estimate from the move's timing so the next
    // fairness window is sized to the current connection quality.
    const movingPlayer = state.players[result.move.playerId];
    if (movingPlayer && result.move.networkRttEstimateMs !== null) {
      recordPlayerRttSample(movingPlayer, result.move.networkRttEstimateMs);
    }

    logger.info(
      "Queued sprint move from user %s at version %d",
      result.move.playerId,
      result.move.payload.expectedStateVersion
    );
    state.lastActivityAtMs = nowMs;
  });

  if (
    state.status === MatchStatus.Waiting &&
    state.roundStartsAtMs !== null &&
    nowMs >= state.roundStartsAtMs
  ) {
    state.roundStartsAtMs = null;
    if (initializeGameState(state, Math.random, nowMs)) {
      logger.info(
        "Starting sprint round %d for players %s",
        state.roundNumber,
        state.playerOrder.join(",")
      );
      sendMatchStarted(dispatcher, state);
    }
  }

  if (
    state.rematchPhase === "countdown" &&
    state.roundStartsAtMs !== null &&
    nowMs >= state.roundStartsAtMs &&
    initializeRematchRound(state, Math.random, nowMs)
  ) {
    logger.info(
      "Starting sprint rematch round %d for players %s",
      state.roundNumber,
      state.playerOrder.join(",")
    );
    sendMatchStarted(dispatcher, state);
  }

  const readyMoves = collectReadyPendingSubmitMoves(state, Date.now());
  if (readyMoves.length > 0) {
    const batchResult = applyPendingSubmitMoveBatch(state, readyMoves, Date.now());

    batchResult.rejections.forEach((rejection) => {
      if (!rejection.accepted) {
        logger.info(
          "Rejected pending sprint move from user %s: %s",
          rejection.playerId || "unknown",
          rejection.rejection.reason
        );
        sendMoveRejected(dispatcher, state, rejection);
      }
    });

    if (batchResult.changed) {
      logger.info(
        "Accepted %d sprint move(s) at version %d",
        batchResult.acceptedPlayerIds.length,
        state.stateVersion
      );
      sendPlayerStateViews(
        dispatcher,
        state,
        batchResult.gameEnded ? ServerOpcode.GameEnded : ServerOpcode.StateUpdate,
        batchResult.transitions
      );
    }

    if (batchResult.changed && !batchResult.gameEnded) {
      resolveAndBroadcastStuckState(dispatcher, state, logger);
    }
  }

  const cleanupDecision = shouldTerminateSprintMatch(state, nowMs);
  if (
    cleanupDecision.reason === "active match idle timeout" &&
    finishMatchAsAbandoned(state, nowMs)
  ) {
    logger.info(
      "Sprint match abandoned after idle timeout at version %d",
      state.stateVersion
    );
    sendPlayerStateViews(dispatcher, state, ServerOpcode.GameEnded);
  }

  const finalCleanupDecision = shouldTerminateSprintMatch(state, nowMs);
  synchronizeResumableMatchPointers(ctx, nk, state, logger);
  if (finalCleanupDecision.terminate) {
    if (ctx && ctx.matchId && nk) {
      try {
        clearResumableMatchPointers(
          nk,
          ctx.matchId,
          assignedSprintPlayerIds(state)
        );
        state.resumablePointersPublished = false;
      } catch (error) {
        logger.warn("Could not clear terminating match pointers: %s", error);
      }
    }
    invalidateMatchCode(nk, logger, state);
    logger.info(
      "Terminating sprint match: %s, status %s, connected players %d",
      finalCleanupDecision.reason || "cleanup",
      state.status,
      connectedPresenceCount(state)
    );
    return null;
  }

  return {state: state};
}

function sprintMatchTerminate(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  dispatcher: nkruntime.MatchDispatcher,
  tick: number,
  state: SprintMatchState,
  graceSeconds: number
): {state: SprintMatchState} {
  if (ctx.matchId) {
    try {
      clearResumableMatchPointers(
        nk,
        ctx.matchId,
        assignedSprintPlayerIds(state)
      );
      state.resumablePointersPublished = false;
    } catch (error) {
      logger.warn("Could not clear terminated match pointers: %s", error);
    }
  }
  invalidateMatchCode(nk, logger, state);
  return {state: state};
}

function sprintMatchSignal(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  dispatcher: nkruntime.MatchDispatcher,
  tick: number,
  state: SprintMatchState,
  data: string
): {state: SprintMatchState; data?: string} {
  try {
    const request = JSON.parse(data || "{}");
    if (request.type === "resumable_match_lookup") {
      const belongsToMatch =
        typeof request.userId === "string" &&
        state.playerOrder.indexOf(request.userId) !== -1;
      return {
        state: state,
        data: JSON.stringify({
          resumable: belongsToMatch && state.status !== MatchStatus.Finished
        })
      };
    }
  } catch (error) {
    // Unknown or malformed signals retain the existing generic response.
  }
  return {
    state: state,
    data: JSON.stringify({ok: true})
  };
}
