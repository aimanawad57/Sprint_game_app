enum GameConnectionStatus {
  connected('connected'),
  disconnected('disconnected');

  const GameConnectionStatus(this.wireValue);

  final String wireValue;
}

class GameConnectionChange {
  const GameConnectionChange({required this.userId, required this.status});

  final String userId;
  final GameConnectionStatus status;

  factory GameConnectionChange.fromJson(Map<String, dynamic> json) {
    final userId = json['userId'];
    if (userId is! String || userId.trim().isEmpty) {
      throw const FormatException('userId must be a non-empty string');
    }

    final statusValue = json['status'];
    if (statusValue is! String) {
      throw const FormatException('status must be a string');
    }

    GameConnectionStatus? status;
    for (final candidate in GameConnectionStatus.values) {
      if (candidate.wireValue == statusValue) {
        status = candidate;
        break;
      }
    }
    if (status == null) {
      throw FormatException('Unsupported connection status: $statusValue');
    }

    return GameConnectionChange(userId: userId, status: status);
  }
}

class GameConnectionView {
  GameConnectionView({
    required List<GameConnectionChange> changes,
    required List<String> connectedUserIds,
    required this.connectedCount,
    required this.expectedCount,
    this.disconnectDeadlineMs,
    this.serverTimeMs,
    this.disconnectGraceMs,
  }) : changes = List.unmodifiable(changes),
       connectedUserIds = List.unmodifiable(connectedUserIds);

  final List<GameConnectionChange> changes;
  final List<String> connectedUserIds;
  final int connectedCount;
  final int expectedCount;
  final int? disconnectDeadlineMs;
  final int? serverTimeMs;
  final int? disconnectGraceMs;

  bool get allPlayersConnected => connectedCount == expectedCount;

  bool isUserConnected(String userId) => connectedUserIds.contains(userId);

  factory GameConnectionView.fromJson(Map<String, dynamic> json) {
    final changesJson = json['changes'];
    final connectedUserIdsJson = json['connectedUserIds'];
    if (changesJson is! List) {
      throw const FormatException('changes must be a list');
    }
    if (connectedUserIdsJson is! List) {
      throw const FormatException('connectedUserIds must be a list');
    }

    final changes = changesJson.map((value) {
      return GameConnectionChange.fromJson(
        _requiredStringMap(value, 'changes item'),
      );
    }).toList();

    final connectedUserIds = connectedUserIdsJson.map((value) {
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException(
          'connectedUserIds must contain non-empty strings',
        );
      }
      return value;
    }).toList();

    final connectedCount = _nonNegativeInt(
      json['connectedCount'],
      'connectedCount',
    );
    final expectedCount = _nonNegativeInt(
      json['expectedCount'],
      'expectedCount',
    );
    if (expectedCount == 0 || connectedCount > expectedCount) {
      throw const FormatException(
        'connection counts must describe a valid non-empty match',
      );
    }
    if (connectedUserIds.length != connectedCount) {
      throw const FormatException(
        'connectedUserIds length must equal connectedCount',
      );
    }

    int? optionalFeedbackInt(String name) {
      final value = json[name];
      if (value == null) return null;
      return value is int && value >= 0 ? value : null;
    }

    return GameConnectionView(
      changes: changes,
      connectedUserIds: connectedUserIds,
      connectedCount: connectedCount,
      expectedCount: expectedCount,
      disconnectDeadlineMs: optionalFeedbackInt('disconnectDeadlineMs'),
      serverTimeMs: optionalFeedbackInt('serverTimeMs'),
      disconnectGraceMs: optionalFeedbackInt('disconnectGraceMs'),
    );
  }
}

Map<String, dynamic> _requiredStringMap(Object? value, String fieldName) {
  if (value is! Map) {
    throw FormatException('$fieldName must be an object');
  }
  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    throw FormatException('$fieldName must have string keys');
  }
}

int _nonNegativeInt(Object? value, String fieldName) {
  if (value is! int || value < 0) {
    throw FormatException('$fieldName must be a non-negative integer');
  }
  return value;
}
