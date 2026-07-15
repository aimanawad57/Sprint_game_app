import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/leaderboard_entry.dart';

void main() {
  test('leaderboard entry reads server JSON safely', () {
    final entry = LeaderboardEntry.fromJson({
      'rank': 1,
      'userId': 'player-a',
      'displayName': 'Alice',
      'wins': 7,
      'gamesPlayed': 10,
      'losses': 3,
      'bestTimeMs': 4200,
    });

    expect(entry.rank, 1);
    expect(entry.userId, 'player-a');
    expect(entry.displayName, 'Alice');
    expect(entry.wins, 7);
    expect(entry.gamesPlayed, 10);
    expect(entry.losses, 3);
    expect(entry.bestTimeMs, 4200);
  });

  test('leaderboard entry handles missing optional values', () {
    final entry = LeaderboardEntry.fromJson({});

    expect(entry.rank, 0);
    expect(entry.userId, '');
    expect(entry.displayName, 'Player');
    expect(entry.wins, 0);
    expect(entry.gamesPlayed, 0);
    expect(entry.losses, 0);
    expect(entry.bestTimeMs, isNull);
  });
}
