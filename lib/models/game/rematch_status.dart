enum GameRematchStatus {
  requested('requested'),
  declined('declined'),
  expired('expired'),
  starting('starting'),
  unavailable('unavailable');

  const GameRematchStatus(this.wireValue);

  final String wireValue;
}

class RematchStatusView {
  const RematchStatusView({
    required this.status,
    this.requestedBy,
    this.declinedBy,
    this.expiresInMs,
    this.startsInMs,
    this.roundNumber,
  });

  final GameRematchStatus status;
  final String? requestedBy;
  final String? declinedBy;
  final int? expiresInMs;
  final int? startsInMs;
  final int? roundNumber;

  factory RematchStatusView.fromJson(Map<String, dynamic> json) {
    final statusValue = json['status'];
    final status = GameRematchStatus.values
        .where((candidate) => candidate.wireValue == statusValue)
        .firstOrNull;
    if (status == null) {
      throw FormatException('Unsupported rematch status: $statusValue');
    }

    String? optionalId(String name) {
      final value = json[name];
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('$name must be a non-empty string');
      }
      return value;
    }

    int? optionalNonNegativeInt(String name) {
      final value = json[name];
      if (value == null) return null;
      if (value is! int || value < 0) {
        throw FormatException('$name must be a non-negative integer');
      }
      return value;
    }

    return RematchStatusView(
      status: status,
      requestedBy: optionalId('requestedBy'),
      declinedBy: optionalId('declinedBy'),
      expiresInMs: optionalNonNegativeInt('expiresInMs'),
      startsInMs: optionalNonNegativeInt('startsInMs'),
      roundNumber: optionalNonNegativeInt('roundNumber'),
    );
  }
}
