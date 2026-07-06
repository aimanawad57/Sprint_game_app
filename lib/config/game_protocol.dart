abstract final class GameClientOpcode {
  static const int submitMove = 1;
}

abstract final class GameServerOpcode {
  static const int matchStarted = 10;
  static const int stateUpdate = 11;
  static const int moveRejected = 12;
  static const int stuckReset = 13;
  static const int gameEnded = 14;
  static const int connectionChanged = 15;
}
