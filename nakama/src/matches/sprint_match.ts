const invalidMatchParametersMessage =
  "expectedUserIds must contain exactly two distinct, non-empty user IDs";
const unauthorizedJoinMessage = "This user was not assigned to this match.";
const disconnectTimeoutMs = 30 * 1000;
const waitingMatchTimeoutMs = 5 * 60 * 1000;
const activeIdleTimeoutMs = 15 * 60 * 1000;
const finishedEmptyGraceMs = 5 * 1000;

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
    disconnectedAtMs: null
  };
  players[playerBId] = {
    userId: playerBId,
    displayName: "Player",
    hand: [],
    deck: [],
    connected: false,
    disconnectedAtMs: null
  };

  return {
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
    createdAtMs: nowMs,
    lastActivityAtMs: nowMs,
    finishedEmptySinceMs: null
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
    disconnectedAtMs: null
  };

  return {
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
    createdAtMs: nowMs,
    lastActivityAtMs: nowMs,
    finishedEmptySinceMs: null
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
  changes: ConnectionChange[]
): ConnectionChangedPayload {
  const connectedUserIds = state.playerOrder.filter(
    (userId) => state.presences[userId] !== undefined
  );

  return {
    changes: changes,
    connectedUserIds: connectedUserIds,
    connectedCount: connectedUserIds.length,
    expectedCount: state.playerOrder.length
  };
}

function broadcastConnectionChanged(
  dispatcher: nkruntime.MatchDispatcher,
  state: SprintMatchState,
  changes: ConnectionChange[]
): void {
  if (changes.length === 0) {
    return;
  }

  dispatcher.broadcastMessage(
    ServerOpcode.ConnectionChanged,
    JSON.stringify(buildConnectionChangedPayload(state, changes))
  );
}

function sendMatchStarted(
  dispatcher: nkruntime.MatchDispatcher,
  state: SprintMatchState
): void {
  state.playerOrder.forEach((userId) => {
    const presence = state.presences[userId];
    if (!presence) {
      throw new Error("Cannot send matchStarted without both player presences.");
    }

    dispatcher.broadcastMessage(
      ServerOpcode.MatchStarted,
      JSON.stringify(buildPlayerStateView(state, userId)),
      [presence]
    );
  });
}

function sendPlayerStateViews(
  dispatcher: nkruntime.MatchDispatcher,
  state: SprintMatchState,
  opcode: ServerOpcode
): void {
  state.playerOrder.forEach((userId) => {
    const presence = state.presences[userId];
    if (!presence) {
      return;
    }

    dispatcher.broadcastMessage(
      opcode,
      JSON.stringify(buildPlayerStateView(state, userId)),
      [presence]
    );
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

function sendPlayerStateView(
  dispatcher: nkruntime.MatchDispatcher,
  state: SprintMatchState,
  userId: string,
  presence: nkruntime.Presence,
  opcode: ServerOpcode
): void {
  dispatcher.broadcastMessage(
    opcode,
    JSON.stringify(buildPlayerStateView(state, userId)),
    [presence]
  );
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
      tickRate: 10,
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
    tickRate: 10,
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
        disconnectedAtMs: null
      };
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

  broadcastConnectionChanged(dispatcher, state, changes);

  if (changes.length > 0) {
    logger.info(
      "Sprint match connection change: connected users %s",
      buildConnectionChangedPayload(state, changes).connectedUserIds.join(",")
    );
  }

  if (initializeGameState(state)) {
    const playerA = state.players[state.playerOrder[0]];
    const playerB = state.players[state.playerOrder[1]];
    logger.info(
      "Sprint match initialized for players %s: hands %d/%d, decks %d/%d, center piles %d/%d, version %d",
      state.playerOrder.join(","),
      playerA.hand.length,
      playerB.hand.length,
      playerA.deck.length,
      playerB.deck.length,
      state.centerPiles.pile_1.length,
      state.centerPiles.pile_2.length,
      state.stateVersion
    );
    sendMatchStarted(dispatcher, state);
  }

  resyncPresences.forEach((presence) => {
    sendPlayerStateView(
      dispatcher,
      state,
      presence.userId,
      presence,
      ServerOpcode.StateUpdate
    );
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

  broadcastConnectionChanged(dispatcher, state, changes);

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

    const result = applySubmitMove(state, message.sender || null, message.data);
    if (!result.accepted) {
      const rejectedResult = result as {
        accepted: false;
        playerId: string | null;
        rejection: MoveRejectedPayload;
      };
      logger.info(
        "Rejected sprint move from user %s: %s",
        rejectedResult.playerId || "unknown",
        rejectedResult.rejection.reason
      );
      sendMoveRejected(dispatcher, state, rejectedResult);
      return;
    }

    logger.info(
      "Accepted sprint move from user %s at version %d",
      result.playerId,
      state.stateVersion
    );
    state.lastActivityAtMs = nowMs;

    sendPlayerStateViews(
      dispatcher,
      state,
      result.gameEnded ? ServerOpcode.GameEnded : ServerOpcode.StateUpdate
    );

    if (!result.gameEnded) {
      resolveAndBroadcastStuckState(dispatcher, state, logger);
    }
  });

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
  if (finalCleanupDecision.terminate) {
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
  return {
    state: state,
    data: JSON.stringify({ok: true})
  };
}
