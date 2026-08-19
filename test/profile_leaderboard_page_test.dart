import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nakama/nakama.dart' as nakama;
import 'package:sprint_app/models/leaderboard_entry.dart';
import 'package:sprint_app/models/player_profile.dart';
import 'package:sprint_app/screens/leaderboard_page.dart';
import 'package:sprint_app/screens/profile_page.dart';
import 'package:sprint_app/services/nakama_service.dart';

void main() {
  testWidgets('profile shows win rate and both streak values', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfilePage(
          displayName: 'Alice',
          email: 'alice@example.com',
          profile: PlayerProfile(
            gamesPlayed: 8,
            wins: 5,
            losses: 3,
            currentWinStreak: 2,
            bestWinStreak: 4,
            bestTimeMs: 3210,
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
          profileStatus: ProfileStatus.loaded,
        ),
      ),
    );

    expect(find.text('62.5%'), findsOneWidget);
    expect(find.text('Current streak'), findsOneWidget);
    expect(find.text('Best streak'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaderboard explains wins ranking and displays expanded stats', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LeaderboardPage(
          nakamaService: _LeaderboardService(),
          nakamaSession: _session(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ranked by total wins'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(
      find.textContaining('62.5%', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Streak', findRichText: true), findsOneWidget);
    expect(find.textContaining('Best', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _LeaderboardService extends NakamaService {
  @override
  Future<List<LeaderboardEntry>> loadWinsLeaderboard(
    nakama.Session session, {
    int limit = 50,
  }) async {
    return const [
      LeaderboardEntry(
        rank: 1,
        userId: 'player-a',
        displayName: 'Alice',
        wins: 5,
        gamesPlayed: 8,
        losses: 3,
        currentWinStreak: 2,
        bestTimeMs: 3210,
      ),
    ];
  }
}

nakama.Session _session() {
  return nakama.Session(
    token: 'test-token',
    refreshToken: 'test-refresh-token',
    created: false,
    vars: const {},
    userId: 'player-a',
    expiresAt: DateTime.utc(2100),
    refreshExpiresAt: DateTime.utc(2100),
  );
}
