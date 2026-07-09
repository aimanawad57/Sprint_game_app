const UNASSIGNED_PLAYER_ID = "";

enum MatchStatus {
  Waiting = "waiting",
  Active = "active",
  Finished = "finished"
}

type PlayerMatchState = {
  userId: string;
  displayName: string;
  hand: Card[];
  deck: Card[];
  connected: boolean;
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
  startedAtMs: number | null;
  endedAtMs: number | null;
  resultPersistencePending: boolean;
  resultPersisted: boolean;
};
