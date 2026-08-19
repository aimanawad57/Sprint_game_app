const UNASSIGNED_PLAYER_ID = "";

enum MatchStatus {
  Waiting = "waiting",
  Active = "active",
  Finished = "finished"
}

enum MatchEndReason {
  Normal = "normal",
  Forfeit = "forfeit",
  Abandoned = "abandoned"
}

type RematchResponse = "pending" | "accepted" | "declined";
type RematchPhase =
  | "idle"
  | "requested"
  | "awaiting_persistence"
  | "countdown"
  | "declined"
  | "expired"
  | "unavailable";

type PlayerMatchState = {
  userId: string;
  displayName: string;
  hand: Card[];
  deck: Card[];
  connected: boolean;
  disconnectedAtMs: number | null;
  // Network round-trip estimate (ms) derived from this player's own moves:
  // receivedAt - lastStateSentAt - reactionTime. Stored as an EMA and used to
  // size the fairness window adaptively. Null until the first timeable move.
  rttEstimateMs: number | null;
  // Increments for every fresh raw RTT sample, even if the rounded EMA does not
  // change, so the viewer can distinguish fresh data from a repeated snapshot.
  rttSampleSequence: number;
  // Per-player fairness anchor. A targeted reconnect snapshot must update only
  // the recipient, not move the other player's reaction-time origin.
  lastStateSentAtMs: number | null;
};

type SprintMatchState = {
  roundNumber: number;
  rematchResponses: {[userId: string]: RematchResponse};
  rematchPhase: RematchPhase;
  rematchRequestedAtMs: number | null;
  roundStartsAtMs: number | null;
  rematchExpired: boolean;
  rematchUnavailable: boolean;
  status: MatchStatus;
  playerOrder: [string, string];
  players: {[userId: string]: PlayerMatchState};
  presences: {[userId: string]: nkruntime.Presence};
  centerPiles: {
    pile_1: Card[];
    pile_2: Card[];
  };
  stateVersion: number;
  winnerId: string | null;
  endReason: MatchEndReason | null;
  startedAtMs: number | null;
  endedAtMs: number | null;
  resultPersistencePending: boolean;
  resultPersisted: boolean;
  matchCode: string | null;
  pendingMoves: ValidatedSubmitMove[];
  nextPendingMoveSequence: number;
  nextTieBreakerPlayerId: string | null;
  createdAtMs: number;
  lastActivityAtMs: number;
  finishedEmptySinceMs: number | null;
  // True while per-player recovery pointers project this live match. The
  // projection is retried on later ticks when storage is temporarily down.
  resumablePointersPublished: boolean;
};
