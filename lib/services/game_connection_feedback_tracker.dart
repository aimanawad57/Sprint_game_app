enum GameConnectionFeedbackChange { none, reconnecting, restored }

/// Filters lobby/initial connection chatter out of gameplay reconnect cues.
class GameConnectionFeedbackTracker {
  bool? _lastConnected;
  bool _hasActiveConnectedBaseline = false;

  bool get hasActiveConnectedBaseline => _hasActiveConnectedBaseline;

  GameConnectionFeedbackChange observe({
    required bool connected,
    required bool matchActive,
  }) {
    final previous = _lastConnected;
    _lastConnected = connected;

    if (!_hasActiveConnectedBaseline) {
      if (matchActive && connected) _hasActiveConnectedBaseline = true;
      return GameConnectionFeedbackChange.none;
    }
    if (!matchActive || previous == null || previous == connected) {
      return GameConnectionFeedbackChange.none;
    }
    return connected
        ? GameConnectionFeedbackChange.restored
        : GameConnectionFeedbackChange.reconnecting;
  }

  void markActiveSnapshot({required bool connected}) {
    _lastConnected = connected;
    if (connected) _hasActiveConnectedBaseline = true;
  }

  void reset() {
    _lastConnected = null;
    _hasActiveConnectedBaseline = false;
  }
}
