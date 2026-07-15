const SPRINT_WINS_LEADERBOARD_ID = "sprint_wins";
const DEFAULT_LEADERBOARD_LIMIT = 50;

type SprintLeaderboardEntry = {
  rank: number;
  userId: string;
  displayName: string;
  wins: number;
  gamesPlayed: number;
  losses: number;
  bestTimeMs: number | null;
};

function ensureSprintWinsLeaderboard(
  nk: nkruntime.Nakama,
  logger: nkruntime.Logger
): void {
  try {
    nk.leaderboardCreate(
      SPRINT_WINS_LEADERBOARD_ID,
      true,
      nkruntime.SortOrder.DESCENDING,
      nkruntime.Operator.SET,
      null,
      {title: "Sprint Wins"},
      true
    );
    logger.info("Created sprint wins leaderboard.");
  } catch (error) {
    // Nakama throws if the leaderboard already exists. That is expected after
    // the first server startup, so startup should continue.
    logger.info("Sprint wins leaderboard already exists or could not be created: %s", error);
  }
}

function writeSprintWinsLeaderboardRecord(
  nk: nkruntime.Nakama,
  userId: string,
  displayName: string,
  profile: StoredPlayerProfile
): void {
  nk.leaderboardRecordWrite(
    SPRINT_WINS_LEADERBOARD_ID,
    userId,
    displayName,
    profile.wins,
    0,
    {
      gamesPlayed: profile.gamesPlayed,
      losses: profile.losses,
      bestTimeMs: profile.bestTimeMs
    },
    nkruntime.OverrideOperator.SET
  );
}

function readLeaderboardLimit(payload: string): number {
  if (!payload) {
    return DEFAULT_LEADERBOARD_LIMIT;
  }

  let decoded: any;
  try {
    decoded = JSON.parse(payload);
  } catch (error) {
    return DEFAULT_LEADERBOARD_LIMIT;
  }

  const requestedLimit = decoded && decoded.limit;
  if (typeof requestedLimit !== "number" || !Number.isFinite(requestedLimit)) {
    return DEFAULT_LEADERBOARD_LIMIT;
  }

  return Math.max(1, Math.min(100, Math.floor(requestedLimit)));
}

function metadataInt(metadata: {[key: string]: any}, key: string): number {
  const value = metadata[key];
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(0, Math.floor(value))
    : 0;
}

function metadataNullableInt(
  metadata: {[key: string]: any},
  key: string
): number | null {
  const value = metadata[key];
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? Math.floor(value)
    : null;
}

function buildLeaderboardEntry(
  record: nkruntime.LeaderboardRecord
): SprintLeaderboardEntry {
  const metadata = record.metadata || {};
  return {
    rank: record.rank,
    userId: record.ownerId,
    displayName: record.username || "Player",
    wins: record.score,
    gamesPlayed: metadataInt(metadata, "gamesPlayed"),
    losses: metadataInt(metadata, "losses"),
    bestTimeMs: metadataNullableInt(metadata, "bestTimeMs")
  };
}

function rpcGetWinsLeaderboard(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw new Error("A session is required to load the leaderboard.");
  }

  const limit = readLeaderboardLimit(payload);
  const result = nk.leaderboardRecordsList(
    SPRINT_WINS_LEADERBOARD_ID,
    [],
    limit
  );
  const records = result.records || [];

  return JSON.stringify(records.map(buildLeaderboardEntry));
}
