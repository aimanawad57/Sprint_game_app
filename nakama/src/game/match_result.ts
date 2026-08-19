const PLAYER_PROFILE_COLLECTION = "player";
const PLAYER_PROFILE_KEY = "profile";

type StoredPlayerProfile = {
  gamesPlayed: number;
  wins: number;
  losses: number;
  currentWinStreak: number;
  bestWinStreak: number;
  bestTimeMs: number | null;
  createdAt: string;
};

function nonNegativeProfileInt(value: any): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? Math.floor(value)
    : 0;
}

function readStoredProfile(
  object: nkruntime.StorageObject | undefined,
  nowMs: number
): StoredPlayerProfile {
  const value = object?.value || {};
  const bestTimeValue = value.bestTimeMs;
  const currentWinStreak = nonNegativeProfileInt(value.currentWinStreak);
  return {
    gamesPlayed: nonNegativeProfileInt(value.gamesPlayed),
    wins: nonNegativeProfileInt(value.wins),
    losses: nonNegativeProfileInt(value.losses),
    currentWinStreak: currentWinStreak,
    bestWinStreak: Math.max(
      currentWinStreak,
      nonNegativeProfileInt(value.bestWinStreak)
    ),
    bestTimeMs:
      typeof bestTimeValue === "number" &&
      Number.isFinite(bestTimeValue) &&
      bestTimeValue >= 0
        ? Math.floor(bestTimeValue)
        : null,
    createdAt:
      typeof value.createdAt === "string" && value.createdAt.length > 0
        ? value.createdAt
        : new Date(nowMs).toISOString()
  };
}

function buildProfileWrite(
  userId: string,
  profile: StoredPlayerProfile,
  existing: nkruntime.StorageObject | undefined
): nkruntime.StorageWriteRequest {
  const write: nkruntime.StorageWriteRequest = {
    collection: PLAYER_PROFILE_COLLECTION,
    key: PLAYER_PROFILE_KEY,
    userId: userId,
    value: profile,
    permissionRead: existing ? existing.permissionRead : 1,
    permissionWrite: 0
  };
  if (existing) {
    write.version = existing.version;
  }
  return write;
}

function persistPendingMatchResult(
  state: SprintMatchState,
  nk: nkruntime.Nakama
): boolean {
  if (state.resultPersisted || !state.resultPersistencePending) {
    return false;
  }
  if (
    state.status !== MatchStatus.Finished ||
    !state.winnerId ||
    state.endReason === MatchEndReason.Abandoned ||
    state.startedAtMs === null ||
    state.endedAtMs === null
  ) {
    throw new Error("Cannot persist an incomplete sprint match result.");
  }

  const winnerId = state.winnerId;
  const loserId =
    state.playerOrder[0] === winnerId
      ? state.playerOrder[1]
      : state.playerOrder[0];
  if (state.playerOrder.indexOf(winnerId) === -1) {
    throw new Error("Cannot persist a winner outside the sprint match.");
  }

  const objects = nk.storageRead(
    state.playerOrder.map((userId) => ({
      collection: PLAYER_PROFILE_COLLECTION,
      key: PLAYER_PROFILE_KEY,
      userId: userId
    }))
  );
  const objectsByUserId: {[userId: string]: nkruntime.StorageObject} = {};
  objects.forEach((object) => {
    objectsByUserId[object.userId] = object;
  });

  const durationMs = Math.max(0, state.endedAtMs - state.startedAtMs);
  const winnerExisting = objectsByUserId[winnerId];
  const loserExisting = objectsByUserId[loserId];
  const winnerProfile = readStoredProfile(winnerExisting, state.endedAtMs);
  const loserProfile = readStoredProfile(loserExisting, state.endedAtMs);
  winnerProfile.gamesPlayed += 1;
  winnerProfile.wins += 1;
  winnerProfile.currentWinStreak += 1;
  winnerProfile.bestWinStreak = Math.max(
    winnerProfile.bestWinStreak,
    winnerProfile.currentWinStreak
  );
  if (state.endReason !== MatchEndReason.Forfeit) {
    winnerProfile.bestTimeMs =
      winnerProfile.bestTimeMs === null
        ? durationMs
        : Math.min(winnerProfile.bestTimeMs, durationMs);
  }
  loserProfile.gamesPlayed += 1;
  loserProfile.losses += 1;
  loserProfile.currentWinStreak = 0;

  nk.multiUpdate(
    null,
    [
      buildProfileWrite(winnerId, winnerProfile, winnerExisting),
      buildProfileWrite(loserId, loserProfile, loserExisting)
    ],
    null,
    null
  );

  [
    {
      userId: winnerId,
      displayName: state.players[winnerId].displayName || "Player",
      profile: winnerProfile
    },
    {
      userId: loserId,
      displayName: state.players[loserId].displayName || "Player",
      profile: loserProfile
    }
  ].forEach((record) => {
    try {
      writeSprintWinsLeaderboardRecord(
        nk,
        record.userId,
        record.displayName,
        record.profile
      );
    } catch (error) {
      // The profile is the source of truth. A failed leaderboard projection
      // must not block the other player or recount the completed match.
    }
  });

  state.resultPersisted = true;
  state.resultPersistencePending = false;
  return true;
}
