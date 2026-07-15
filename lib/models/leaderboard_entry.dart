class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.wins,
    required this.gamesPlayed,
    required this.losses,
    required this.bestTimeMs,
  });

  final int rank;
  final String userId;
  final String displayName;
  final int wins;
  final int gamesPlayed;
  final int losses;
  final int? bestTimeMs;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: _readInt(json['rank']),
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Player',
      wins: _readInt(json['wins']),
      gamesPlayed: _readInt(json['gamesPlayed']),
      losses: _readInt(json['losses']),
      bestTimeMs: json['bestTimeMs'] == null
          ? null
          : _readInt(json['bestTimeMs']),
    );
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}
