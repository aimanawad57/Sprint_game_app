class PlayerProfile {
  const PlayerProfile({
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.bestTimeMs,
    required this.createdAt,
  });

  final int gamesPlayed;
  final int wins;
  final int losses;
  final int? bestTimeMs;
  final String createdAt;

  factory PlayerProfile.createDefault() {
    return PlayerProfile(
      gamesPlayed: 0,
      wins: 0,
      losses: 0,
      bestTimeMs: null,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    return PlayerProfile(
      gamesPlayed: _readInt(json['gamesPlayed']),
      wins: _readInt(json['wins']),
      losses: _readInt(json['losses']),
      bestTimeMs: json['bestTimeMs'] == null
          ? null
          : _readInt(json['bestTimeMs']),
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gamesPlayed': gamesPlayed,
      'wins': wins,
      'losses': losses,
      'bestTimeMs': bestTimeMs,
      'createdAt': createdAt,
    };
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}
