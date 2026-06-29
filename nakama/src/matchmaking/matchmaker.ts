// This creates the authoritative match for the sprint game when the matchmaker finds a match. 
// It uses the expectedUserIds from the matchmaker result to create a new match with those users. 
// The matchCreate function returns the match ID of the newly created match, 
//    which is then returned by this function.

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
