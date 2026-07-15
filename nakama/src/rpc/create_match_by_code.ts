const MAX_MATCH_CODE_GENERATION_ATTEMPTS = 5;

// Claims a code by writing a reservation record with version "*", which
// Nakama's storage engine only accepts if no object currently exists at that
// key. This makes the claim atomic: two concurrent requests that randomly
// generate the same code can no longer both believe they own it, because at
// most one of their conditional writes can succeed. The loser's write
// throws and this function just tries another candidate. matchId is null
// until rpcCreateMatchByCode finishes creating the match and finalizes the
// record below.
function reserveMatchCode(nk: nkruntime.Nakama, creatorId: string): string {
  for (let attempt = 0; attempt < MAX_MATCH_CODE_GENERATION_ATTEMPTS; attempt += 1) {
    const candidate = generateMatchCode();
    const reservation: MatchCodeRecord = {
      matchId: null,
      creatorId: creatorId,
      createdAtMs: Date.now()
    };

    try {
      nk.storageWrite([
        {
          collection: MATCH_CODE_COLLECTION,
          key: candidate,
          userId: SYSTEM_USER_ID,
          value: reservation,
          version: "*",
          permissionRead: 0,
          permissionWrite: 0
        }
      ]);
      return candidate;
    } catch (error) {
      // Someone else's write already claimed this exact code first; retry.
      continue;
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

  const code = reserveMatchCode(nk, creatorId);
  const matchId = nk.matchCreate("sprint_authoritative_match", {
    mode: "code",
    creatorId: creatorId,
    code: code
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
