function defaultPlayerProfile(nowMs: number = Date.now()): StoredPlayerProfile {
  return {
    gamesPlayed: 0,
    wins: 0,
    losses: 0,
    currentWinStreak: 0,
    bestWinStreak: 0,
    bestTimeMs: null,
    createdAt: new Date(nowMs).toISOString()
  };
}

function rpcGetOrCreateProfile(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  const userId = ctx.userId;
  if (!userId) {
    throw new Error("A session is required to load a player profile.");
  }

  const objects = nk.storageRead([
    {
      collection: PLAYER_PROFILE_COLLECTION,
      key: PLAYER_PROFILE_KEY,
      userId: userId
    }
  ]);
  const existing = objects[0];
  if (existing) {
    return JSON.stringify(readStoredProfile(existing, Date.now()));
  }

  const profile = defaultPlayerProfile();
  nk.storageWrite([
    {
      collection: PLAYER_PROFILE_COLLECTION,
      key: PLAYER_PROFILE_KEY,
      userId: userId,
      value: profile,
      permissionRead: 1,
      permissionWrite: 0
    }
  ]);

  logger.info("Created default sprint profile for user %s", userId);
  return JSON.stringify(profile);
}
