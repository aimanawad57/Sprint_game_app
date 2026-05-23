function rpcHealthcheck(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  return JSON.stringify({
    ok: true,
    service: "sprint-nakama",
    userId: ctx.userId || null
  });
}

type SprintMatchState = {
  presences: {[userId: string]: nkruntime.Presence};
  expectedUserIds: string[];
};

function matchmakerMatched(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  matches: nkruntime.MatchmakerResult[]
): string {
  const userIds = matches.map((match) => match.presence.userId);

  logger.info("Creating sprint authoritative match for users: %s", userIds.join(","));

  return nk.matchCreate("sprint_authoritative_match", {
    expectedUserIds: userIds
  });
}

function matchInit(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  params: {[key: string]: any}
): {state: SprintMatchState; tickRate: number; label: string} {
  const expectedUserIds = (params.expectedUserIds || []) as string[];

  return {
    state: {
      presences: {},
      expectedUserIds: expectedUserIds
    },
    tickRate: 10,
    label: JSON.stringify({
      mode: "sprint_quickplay",
      expectedPlayers: expectedUserIds.length
    })
  };
}

function matchJoinAttempt(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  dispatcher: nkruntime.MatchDispatcher,
  tick: number,
  state: SprintMatchState,
  presence: nkruntime.Presence,
  metadata: {[key: string]: any}
): {state: SprintMatchState; accept: boolean; rejectMessage?: string} {
  const isExpectedUser =
    state.expectedUserIds.length === 0 ||
    state.expectedUserIds.indexOf(presence.userId) !== -1;

  if (!isExpectedUser) {
    return {
      state: state,
      accept: false,
      rejectMessage: "This user was not assigned to this match."
    };
  }

  return {
    state: state,
    accept: true
  };
}

function matchJoin(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  dispatcher: nkruntime.MatchDispatcher,
  tick: number,
  state: SprintMatchState,
  presences: nkruntime.Presence[]
): {state: SprintMatchState} {
  presences.forEach((presence) => {
    state.presences[presence.userId] = presence;
  });

  const joinedCount = Object.keys(state.presences).length;

  dispatcher.broadcastMessage(
    1,
    JSON.stringify({
      type: "players_joined",
      joinedCount: joinedCount,
      expectedCount: state.expectedUserIds.length
    })
  );

  return {state: state};
}

function matchLeave(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  dispatcher: nkruntime.MatchDispatcher,
  tick: number,
  state: SprintMatchState,
  presences: nkruntime.Presence[]
): {state: SprintMatchState} {
  presences.forEach((presence) => {
    delete state.presences[presence.userId];
  });

  return {state: state};
}

function matchLoop(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  dispatcher: nkruntime.MatchDispatcher,
  tick: number,
  state: SprintMatchState,
  messages: nkruntime.MatchMessage[]
): {state: SprintMatchState} {
  return {state: state};
}

function matchTerminate(
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

function matchSignal(
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

function InitModule(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  initializer: nkruntime.Initializer
): void {
  initializer.registerRpc("healthcheck", rpcHealthcheck);
  initializer.registerMatchmakerMatched(matchmakerMatched);
  initializer.registerMatch("sprint_authoritative_match", {
    matchInit: matchInit,
    matchJoinAttempt: matchJoinAttempt,
    matchJoin: matchJoin,
    matchLeave: matchLeave,
    matchLoop: matchLoop,
    matchTerminate: matchTerminate,
    matchSignal: matchSignal
  });
  logger.info("Sprint Nakama runtime initialized.");
}
