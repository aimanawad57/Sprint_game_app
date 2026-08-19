import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/player_profile.dart';

void main() {
  test('player profile parses streaks and calculates win rate', () {
    final profile = PlayerProfile.fromJson({
      'gamesPlayed': 8,
      'wins': 5,
      'losses': 3,
      'currentWinStreak': 2,
      'bestWinStreak': 4,
      'bestTimeMs': 3210,
      'createdAt': '2026-01-01T00:00:00.000Z',
    });

    expect(profile.winRate, 62.5);
    expect(profile.currentWinStreak, 2);
    expect(profile.bestWinStreak, 4);
    expect(profile.toJson()['currentWinStreak'], 2);
    expect(profile.toJson()['bestWinStreak'], 4);
  });

  test('legacy and malformed profile values use safe defaults', () {
    final legacy = PlayerProfile.fromJson({
      'gamesPlayed': 0,
      'wins': -2,
      'losses': -1,
    });

    expect(legacy.winRate, 0);
    expect(legacy.wins, 0);
    expect(legacy.losses, 0);
    expect(legacy.currentWinStreak, 0);
    expect(legacy.bestWinStreak, 0);
  });
}
