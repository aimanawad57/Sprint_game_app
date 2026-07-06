const invalidMatchParametersMessage =
  "expectedUserIds must contain exactly two distinct, non-empty user IDs";
const unauthorizedJoinMessage = "This user was not assigned to this match.";

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
  playerOrder: [string, string]
): SprintMatchState {
  const playerAId = playerOrder[0];
  const playerBId = playerOrder[1];
  const players: {[userId: string]: PlayerMatchState} = {};

  players[playerAId] = {
    userId: playerAId,
    hand: [],
    deck: [],
    connected: false
  };
  players[playerBId] = {
    userId: playerBId,
    hand: [],
    deck: [],
    connected: false
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
    winnerId: null
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
      "Sprint match is stuck but both center piles contain only one card; reset deferred"
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
    state: createWaitingMatchState(playerOrder),
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

  if (!isExpectedUser) {
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
  const changes: ConnectionChange[] = [];

  presences.forEach((presence) => {
    const player = state.players[presence.userId];
    if (!player) {
      logger.warn(
        "Ignored joined presence for unknown sprint player: %s",
        presence.userId
      );
      return;
    }

    state.presences[presence.userId] = presence;
    player.connected = true;
    changes.push({
      userId: presence.userId,
      status: ConnectionStatus.Connected
    });
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

    delete state.presences[presence.userId];
    player.connected = false;
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
): {state: SprintMatchState} {
  messages.forEach((message) => {
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

    sendPlayerStateViews(
      dispatcher,
      state,
      result.gameEnded ? ServerOpcode.GameEnded : ServerOpcode.StateUpdate
    );

    if (!result.gameEnded) {
      resolveAndBroadcastStuckState(dispatcher, state, logger);
    }
  });

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
