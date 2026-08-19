enum ProfileStatus { loading, loaded, failed }

class PlayerProfile {
  const PlayerProfile({
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.currentWinStreak,
    required this.bestWinStreak,
    required this.bestTimeMs,
    required this.createdAt,
  });

  final int gamesPlayed;
  final int wins;
  final int losses;
  final int currentWinStreak;
  final int bestWinStreak;
  final int? bestTimeMs;
  final String createdAt;

  double get winRate => gamesPlayed == 0
      ? 0
      : (wins * 100 / gamesPlayed).clamp(0, 100).toDouble();

  factory PlayerProfile.createDefault() {
    return PlayerProfile(
      gamesPlayed: 0,
      wins: 0,
      losses: 0,
      currentWinStreak: 0,
      bestWinStreak: 0,
      bestTimeMs: null,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    return PlayerProfile(
      gamesPlayed: _readInt(json['gamesPlayed']),
      wins: _readInt(json['wins']),
      losses: _readInt(json['losses']),
      currentWinStreak: _readInt(json['currentWinStreak']),
      bestWinStreak: _readInt(json['bestWinStreak']),
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
      'currentWinStreak': currentWinStreak,
      'bestWinStreak': bestWinStreak,
      'bestTimeMs': bestTimeMs,
      'createdAt': createdAt,
    };
  }

  static int _readInt(Object? value) {
    if (value is int) return value < 0 ? 0 : value;
    if (value is num) return value < 0 ? 0 : value.toInt();
    return 0;
  }
}
