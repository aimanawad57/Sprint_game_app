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

type PlayerMatchState = {
  userId: string;
  displayName: string;
  hand: Card[];
  deck: Card[];
  connected: boolean;
  disconnectedAtMs: number | null;
  // Network round-trip estimate (ms) derived from this player's own moves:
  // receivedAt - lastBroadcastAt - reactionTime. Used to size the fairness
  // window adaptively. Null until the first timeable move is observed.
  rttEstimateMs: number | null;
};

type SprintMatchState = {
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
  // Server-clock timestamp of the most recent full-state broadcast. Anchors
  // reaction-time fairness: a move's client-reported reaction time is added
  // to this to reconstruct when the player actually reacted.
  lastBroadcastAtMs: number | null;
  pendingMoves: ValidatedSubmitMove[];
  nextPendingMoveSequence: number;
  nextTieBreakerPlayerId: string | null;
  createdAtMs: number;
  lastActivityAtMs: number;
  finishedEmptySinceMs: number | null;
};
