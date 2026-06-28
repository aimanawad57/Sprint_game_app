function matchmakerMatched(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  matches: nkruntime.MatchmakerResult[]
): string {
  const userIds = matches.map((match) => match.presence.userId);

  logger.info(
    "Creating sprint authoritative match for users: %s",
    userIds.join(",")
  );

  return nk.matchCreate("sprint_authoritative_match", {
    expectedUserIds: userIds
  });
}
