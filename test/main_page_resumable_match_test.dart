import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nakama/nakama.dart' as nakama;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sprint_app/models/onboarding_progress.dart';
import 'package:sprint_app/models/player_profile.dart';
import 'package:sprint_app/screens/main_page.dart';
import 'package:sprint_app/services/nakama_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('startup discovers a resumable match and blocks new play', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          email: 'alice@example.com',
          displayName: 'Alice',
          nakamaService: _MainPageService('live-match'),
          nakamaSession: _session(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You were disconnected from the match'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    final playButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Play'),
    );
    expect(playButton.onPressed, isNull);
  });

  testWidgets('startup enables play when the server has no live match', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          email: 'alice@example.com',
          displayName: 'Alice',
          nakamaService: _MainPageService(null),
          nakamaSession: _session(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You were disconnected from the match'), findsNothing);
    final playButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Play'),
    );
    expect(playButton.onPressed, isNotNull);
  });
}

class _MainPageService extends NakamaService {
  _MainPageService(this.resumableMatchId);

  final String? resumableMatchId;

  @override
  Future<void> checkBackend(nakama.Session session) async {}

  @override
  Future<String?> loadResumableMatch(nakama.Session session) async =>
      resumableMatchId;

  @override
  Future<PlayerProfile> loadOrCreatePlayerProfile(
    nakama.Session session,
  ) async => const PlayerProfile(
    gamesPlayed: 0,
    wins: 0,
    losses: 0,
    currentWinStreak: 0,
    bestWinStreak: 0,
    bestTimeMs: null,
    createdAt: '2026-01-01T00:00:00.000Z',
  );

  @override
  Future<OnboardingProgress> loadOnboardingProgress(
    nakama.Session session,
  ) async => const OnboardingProgress(tutorialCompletedVersion: 1);
}

nakama.Session _session() => nakama.Session(
  token: 'test-token',
  refreshToken: 'test-refresh-token',
  created: false,
  vars: const {},
  userId: 'player-a',
  expiresAt: DateTime.utc(2100),
  refreshExpiresAt: DateTime.utc(2100),
);
