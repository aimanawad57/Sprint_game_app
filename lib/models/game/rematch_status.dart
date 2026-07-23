enum GameRematchStatus {
  requested('requested'),
  preparing('preparing'),
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
    this.startsAtMs,
    this.serverTimeMs,
    this.roundNumber,
  });

  final GameRematchStatus status;
  final String? requestedBy;
  final String? declinedBy;
  final int? expiresInMs;
  final int? startsInMs;
  final int? startsAtMs;
  final int? serverTimeMs;
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

    final view = RematchStatusView(
      status: status,
      requestedBy: optionalId('requestedBy'),
      declinedBy: optionalId('declinedBy'),
      expiresInMs: optionalNonNegativeInt('expiresInMs'),
      startsInMs: optionalNonNegativeInt('startsInMs'),
      startsAtMs: optionalNonNegativeInt('startsAtMs'),
      serverTimeMs: optionalNonNegativeInt('serverTimeMs'),
      roundNumber: optionalNonNegativeInt('roundNumber'),
    );
    if (status == GameRematchStatus.starting &&
        view.startsAtMs == null &&
        view.startsInMs == null) {
      throw const FormatException(
        'A starting round requires startsAtMs or startsInMs',
      );
    }
    return view;
  }
}
