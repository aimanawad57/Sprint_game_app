function InitModule(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  initializer: nkruntime.Initializer
): void {
  initializer.registerRpc("healthcheck", rpcHealthcheck);
  initializer.registerMatchmakerMatched(matchmakerMatched);
  initializer.registerMatch("sprint_authoritative_match", {
    matchInit: sprintMatchInit,
    matchJoinAttempt: sprintMatchJoinAttempt,
    matchJoin: sprintMatchJoin,
    matchLeave: sprintMatchLeave,
    matchLoop: sprintMatchLoop,
    matchTerminate: sprintMatchTerminate,
    matchSignal: sprintMatchSignal
  });

  logger.info("Sprint Nakama runtime initialized.");
}
