function parseJoinMatchByCodePayload(payload: string): string {
  let decoded: any;
  try {
    decoded = JSON.parse(payload);
  } catch (error) {
    throw new Error("Invalid request payload.");
  }

  const code = decoded && decoded.code;
  if (typeof code !== "string" || code.trim().length === 0) {
    throw new Error("A match code is required.");
  }

  return normalizeMatchCode(code);
}

function rpcJoinMatchByCode(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw new Error("A session is required to join a match.");
  }

  const code = parseJoinMatchByCodePayload(payload);

  const objects = nk.storageRead([
    {collection: MATCH_CODE_COLLECTION, key: code, userId: SYSTEM_USER_ID}
  ]);
  const record = objects[0] && (objects[0].value as MatchCodeRecord);
  if (!record || !record.matchId) {
    throw new Error("Match code not found.");
  }

  logger.info("User %s resolved match code %s to match %s", ctx.userId, code, record.matchId);

  return JSON.stringify({matchId: record.matchId});
}
