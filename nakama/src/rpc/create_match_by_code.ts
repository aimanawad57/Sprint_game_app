const MAX_MATCH_CODE_GENERATION_ATTEMPTS = 5;

function findUnusedMatchCode(nk: nkruntime.Nakama): string {
  for (let attempt = 0; attempt < MAX_MATCH_CODE_GENERATION_ATTEMPTS; attempt += 1) {
    const candidate = generateMatchCode();
    const existing = nk.storageRead([
      {collection: MATCH_CODE_COLLECTION, key: candidate, userId: SYSTEM_USER_ID}
    ]);
    if (existing.length === 0) {
      return candidate;
    }
  }

  throw new Error("Could not generate a unique match code; please try again.");
}

function rpcCreateMatchByCode(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  const creatorId = ctx.userId;
  if (!creatorId) {
    throw new Error("A session is required to create a match.");
  }

  const code = findUnusedMatchCode(nk);
  const matchId = nk.matchCreate("sprint_authoritative_match", {
    mode: "code",
    creatorId: creatorId
  });

  const record: MatchCodeRecord = {
    matchId: matchId,
    creatorId: creatorId,
    createdAtMs: Date.now()
  };

  nk.storageWrite([
    {
      collection: MATCH_CODE_COLLECTION,
      key: code,
      userId: SYSTEM_USER_ID,
      value: record,
      permissionRead: 0,
      permissionWrite: 0
    }
  ]);

  logger.info("Created sprint match %s with code %s for user %s", matchId, code, creatorId);

  return JSON.stringify({code: code, matchId: matchId});
}
