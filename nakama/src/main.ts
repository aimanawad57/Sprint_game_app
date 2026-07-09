function InitModule(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  initializer: nkruntime.Initializer
): void {
  validateCardCatalog(CARD_CATALOG);

  initializer.registerRpc("healthcheck", rpcHealthcheck);
  initializer.registerRpc("create_match_by_code", rpcCreateMatchByCode);
  initializer.registerRpc("join_match_by_code", rpcJoinMatchByCode);
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

  logger.info("Sprint card catalog validated: %d cards.", CARD_CATALOG.length);
  logger.info("Sprint Nakama runtime initialized.");
}
