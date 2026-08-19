import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nakama/nakama.dart' as nakama;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sprint_app/models/game_feedback_preferences.dart';
import 'package:sprint_app/screens/tutorial_page.dart';
import 'package:sprint_app/services/game_feedback_audio.dart';
import 'package:sprint_app/services/game_feedback_preferences_store.dart';
import 'package:sprint_app/services/game_feedback_service.dart';
import 'package:sprint_app/services/nakama_service.dart';
import 'package:sprint_app/services/onboarding_progress_repository.dart';
import 'package:sprint_app/widgets/game_feedback_scope.dart';
import 'package:sprint_app/widgets/game_state_panel.dart';

Finder _tutorialScrollable() => find
    .descendant(
      of: find.byKey(const ValueKey('gameStatePanelScroll')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _reveal(
  WidgetTester tester,
  Finder finder, {
  required double scrollDelta,
}) async {
  await tester.scrollUntilVisible(
    finder,
    scrollDelta,
    scrollable: _tutorialScrollable(),
  );
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _play(
  WidgetTester tester, {
  required String cardId,
  required String pileKey,
}) async {
  final card = find.byKey(ValueKey(cardId));
  await _reveal(tester, card, scrollDelta: 200);
  await tester.tap(card);
  await tester.pump();

  final pile = find.byKey(ValueKey(pileKey));
  await _reveal(tester, pile, scrollDelta: -200);
  await tester.tap(pile);
  await tester.pump(const Duration(milliseconds: 450));
}

void main() {
  testWidgets('step 4 records the required invalid move and can advance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    final repository = OnboardingProgressRepository(
      nakamaService: NakamaService(),
      session: nakama.Session(
        token: 'test-token',
        refreshToken: 'test-refresh-token',
        created: false,
        vars: const {},
        userId: 'tutorial-test-user',
        expiresAt: DateTime.utc(2100),
        refreshExpiresAt: DateTime.utc(2100),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: TutorialPage(repository: repository)),
    );

    await _play(tester, cardId: 'tutorial_red_tree_4', pileKey: 'centerPile1');
    await _play(tester, cardId: 'tutorial_blue_star_4', pileKey: 'centerPile1');
    await _play(
      tester,
      cardId: 'tutorial_green_flag_2',
      pileKey: 'centerPile1',
    );

    expect(find.text('Tutorial 4/6'), findsOneWidget);

    await _play(
      tester,
      cardId: 'tutorial_purple_circle_5',
      pileKey: 'centerPile2',
    );

    expect(find.text('Tutorial 4/6'), findsOneWidget);
    expect(
      find.text(
        'Correct observation: it matches no color, shape, or count. '
        'Now play the red card.',
      ),
      findsOneWidget,
    );

    await _play(tester, cardId: 'tutorial_red_tree_4', pileKey: 'centerPile1');

    expect(find.text('Tutorial 5/6'), findsOneWidget);
  });

  testWidgets('successful lesson uses the shared flight and move sound', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final audio = _RecordingAudio();
    final feedbackService = GameFeedbackService(
      preferencesStore: _FeedbackStore(),
      audioBackend: audio,
      vibrationPlayer: (_) async {},
      coalescingWindow: Duration.zero,
    );
    addTearDown(feedbackService.dispose);
    await feedbackService.initialize();
    final repository = OnboardingProgressRepository(
      nakamaService: NakamaService(),
      session: nakama.Session(
        token: 'test-token',
        refreshToken: 'test-refresh-token',
        created: false,
        vars: const {},
        userId: 'tutorial-feedback-user',
        expiresAt: DateTime.utc(2100),
        refreshExpiresAt: DateTime.utc(2100),
      ),
    );

    await tester.pumpWidget(
      GameFeedbackScope(
        service: feedbackService,
        child: MaterialApp(home: TutorialPage(repository: repository)),
      ),
    );

    final card = find.byKey(const ValueKey('tutorial_red_tree_4'));
    await _reveal(tester, card, scrollDelta: 200);
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 1));

    final pile = find.byKey(const ValueKey('centerPile1'));
    await _reveal(tester, pile, scrollDelta: -200);
    await tester.tap(pile);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final panel = tester.widget<GameStatePanel>(find.byType(GameStatePanel));
    expect(panel.gameState.stateVersion, 2);
    expect(panel.transitions, hasLength(1));
    expect(
      find.byKey(const ValueKey('transitionFlight-0-2-0')),
      findsOneWidget,
    );
    expect(audio.played, contains(GameFeedbackCue.acceptedMove));
  });
}

class _FeedbackStore implements GameFeedbackPreferencesStore {
  @override
  Future<GameFeedbackPreferences> load() async =>
      GameFeedbackPreferences.defaults;

  @override
  Future<void> setSoundEffectsEnabled(bool enabled) async {}

  @override
  Future<void> setVibrationEnabled(bool enabled) async {}
}

class _RecordingAudio implements GameFeedbackAudioBackend {
  final List<GameFeedbackCue> played = <GameFeedbackCue>[];

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> playExclusive(
    GameFeedbackCue cue, {
    Duration startWithin = const Duration(milliseconds: 300),
  }) async {
    played.add(cue);
    return true;
  }

  @override
  Future<void> stopAll() async {}
}
