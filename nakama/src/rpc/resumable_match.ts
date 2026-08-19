const RESUMABLE_MATCH_COLLECTION = "sprint_active_match";
const RESUMABLE_MATCH_KEY = "current";

type ResumableMatchPointer = {
  matchId: string;
  updatedAtMs: number;
};

function assignedSprintPlayerIds(state: SprintMatchState): string[] {
  return state.playerOrder.filter((userId) => userId.length > 0);
}

function publishResumableMatchPointers(
  nk: nkruntime.Nakama,
  matchId: string,
  playerIds: string[],
  nowMs: number = Date.now()
): void {
  if (!matchId || playerIds.length === 0) return;
  const value: ResumableMatchPointer = {matchId: matchId, updatedAtMs: nowMs};
  nk.storageWrite(
    playerIds.map((userId) => ({
      collection: RESUMABLE_MATCH_COLLECTION,
      key: RESUMABLE_MATCH_KEY,
      userId: userId,
      value: value,
      permissionRead: 0,
      permissionWrite: 0
    }))
  );
}

function clearResumableMatchPointers(
  nk: nkruntime.Nakama,
  matchId: string,
  playerIds: string[]
): void {
  if (!matchId || playerIds.length === 0) return;
  const reads = playerIds.map((userId) => ({
    collection: RESUMABLE_MATCH_COLLECTION,
    key: RESUMABLE_MATCH_KEY,
    userId: userId
  }));
  const matchingPointers = nk.storageRead(reads).filter((object) => {
    return object.value && object.value.matchId === matchId;
  });
  if (matchingPointers.length === 0) return;
  nk.storageDelete(
    matchingPointers.map((object) => ({
      collection: RESUMABLE_MATCH_COLLECTION,
      key: RESUMABLE_MATCH_KEY,
      userId: object.userId,
      version: object.version
    }))
  );
}

function synchronizeResumableMatchPointers(
  ctx: nkruntime.Context | null,
  nk: nkruntime.Nakama | null,
  state: SprintMatchState,
  logger: nkruntime.Logger
): void {
  const matchId = ctx && ctx.matchId;
  if (!nk || !matchId) return;
  const shouldPublish = state.status !== MatchStatus.Finished;
  if (shouldPublish === state.resumablePointersPublished) return;

  try {
    const playerIds = assignedSprintPlayerIds(state);
    if (shouldPublish) {
      publishResumableMatchPointers(nk, matchId, playerIds);
    } else {
      clearResumableMatchPointers(nk, matchId, playerIds);
    }
    state.resumablePointersPublished = shouldPublish;
  } catch (error) {
    logger.warn("Could not synchronize resumable match pointers: %s", error);
  }
}

function readResumableMatchPointer(
  nk: nkruntime.Nakama,
  userId: string
): nkruntime.StorageObject | null {
  const objects = nk.storageRead([
    {
      collection: RESUMABLE_MATCH_COLLECTION,
      key: RESUMABLE_MATCH_KEY,
      userId: userId
    }
  ]);
  return objects.length > 0 ? objects[0] : null;
}

function rpcGetResumableMatch(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw new Error("A session is required to restore a match.");
  }

  const pointer = readResumableMatchPointer(nk, ctx.userId);
  const matchId = pointer && pointer.value && pointer.value.matchId;
  if (typeof matchId !== "string" || matchId.length === 0) {
    return JSON.stringify({matchId: null});
  }

  if (!nk.matchGet(matchId)) {
    clearResumableMatchPointers(nk, matchId, [ctx.userId]);
    return JSON.stringify({matchId: null});
  }

  const response = JSON.parse(
    nk.matchSignal(
      matchId,
      JSON.stringify({type: "resumable_match_lookup", userId: ctx.userId})
    )
  );
  if (!response || response.resumable !== true) {
    clearResumableMatchPointers(nk, matchId, [ctx.userId]);
    return JSON.stringify({matchId: null});
  }

  return JSON.stringify({matchId: matchId});
}
