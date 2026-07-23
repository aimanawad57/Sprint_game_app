enum PileId {
  Pile1 = "pile_1",
  Pile2 = "pile_2"
}

enum ClientOpcode {
  SubmitMove = 1,
  AbandonMatch = 2,
  RematchDecision = 3
}

enum ServerOpcode {
  MatchStarted = 10,
  StateUpdate = 11,
  MoveRejected = 12,
  StuckReset = 13,
  GameEnded = 14,
  ConnectionChanged = 15,
  RematchStatus = 16
}

type RematchStatus =
  | "requested"
  | "declined"
  | "expired"
  | "starting"
  | "unavailable";

type RematchStatusPayload = {
  status: RematchStatus;
  requestedBy?: string;
  declinedBy?: string;
  expiresInMs?: number;
  startsInMs?: number;
  roundNumber?: number;
};

enum MoveRejectionReason {
  InvalidPayload = "invalid_payload",
  MatchNotActive = "match_not_active",
  PlayerNotInMatch = "player_not_in_match",
  CardNotInHand = "card_not_in_hand",
  InvalidTargetPile = "invalid_target_pile",
  CardDoesNotMatch = "card_does_not_match",
  PlayerDisconnected = "player_disconnected",
  StaleMove = "stale_move",
  GameFinished = "game_finished"
}

enum ConnectionStatus {
  Connected = "connected",
  Disconnected = "disconnected"
}

type ConnectionChange = {
  userId: string;
  status: ConnectionStatus;
};

type ConnectionChangedPayload = {
  changes: ConnectionChange[];
  connectedUserIds: string[];
  connectedCount: number;
  expectedCount: number;
};

type PlayerStateView = {
  stateVersion: number;
  status: MatchStatus;
  elapsedTimeMs: number;
  myHand: Card[];
  myDeckCount: number;
  opponentHandCount: number;
  opponentDeckCount: number;
  centerPiles: {
    pile_1: {topCard: Card};
    pile_2: {topCard: Card};
  };
  winnerId: string | null;
  winnerName: string | null;
  endReason: MatchEndReason | null;
};
