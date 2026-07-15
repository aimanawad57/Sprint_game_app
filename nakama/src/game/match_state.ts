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
  pendingMoves: ValidatedSubmitMove[];
  nextPendingMoveSequence: number;
  nextTieBreakerPlayerId: string | null;
  createdAtMs: number;
  lastActivityAtMs: number;
  finishedEmptySinceMs: number | null;
};
