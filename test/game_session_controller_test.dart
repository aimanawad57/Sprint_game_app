import 'package:flutter_test/flutter_test.dart';
import 'package:nakama/nakama.dart' as nakama;
import 'package:sprint_app/controllers/game_session_controller.dart';
import 'package:sprint_app/models/game/game_card.dart';
import 'package:sprint_app/models/game/game_state_view.dart';
import 'package:sprint_app/models/game_feedback_preferences.dart';
import 'package:sprint_app/services/game_feedback_audio.dart';
import 'package:sprint_app/services/game_feedback_preferences_store.dart';
import 'package:sprint_app/services/game_feedback_service.dart';
import 'package:sprint_app/services/nakama_service.dart';
import 'package:sprint_app/services/resumable_match_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('authoritative states drive explicit session phases', () {
    final feedback = _feedbackService();
    final controller = _controller(feedback);
    addTearDown(feedback.dispose);
    addTearDown(controller.dispose);

    expect(controller.phase, GameSessionPhase.idle);

    controller.applyAuthoritativeStateForTesting(_state(version: 1));
    expect(controller.phase, GameSessionPhase.active);

    controller.applyAuthoritativeStateForTesting(
      _state(
        version: 2,
        status: GameMatchStatus.finished,
        endReason: GameMatchEndReason.normal,
      ),
    );
    expect(controller.phase, GameSessionPhase.finished);

    controller.applyAuthoritativeStateForTesting(
      _state(version: 1),
      startsNewRound: true,
    );
    expect(controller.phase, GameSessionPhase.active);
    expect(controller.roundSequence, 1);

    controller.applyAuthoritativeStateForTesting(
      _state(
        version: 3,
        status: GameMatchStatus.finished,
        endReason: GameMatchEndReason.abandoned,
      ),
    );
    expect(controller.phase, GameSessionPhase.abandoned);
  });

  test('older authoritative snapshots cannot move session state backwards', () {
    final feedback = _feedbackService();
    final controller = _controller(feedback);
    addTearDown(feedback.dispose);
    addTearDown(controller.dispose);

    controller.applyAuthoritativeStateForTesting(_state(version: 5));
    controller.applyAuthoritativeStateForTesting(
      _state(
        version: 4,
        status: GameMatchStatus.finished,
        endReason: GameMatchEndReason.normal,
      ),
    );

    expect(controller.phase, GameSessionPhase.active);
    expect(controller.gameState?.stateVersion, 5);
  });

  test('authoritative finish clears the persisted resumable match', () async {
    final feedback = _feedbackService();
    final store = _ResumableStore();
    final controller = _controller(feedback, resumableMatchStore: store);
    addTearDown(feedback.dispose);
    addTearDown(controller.dispose);

    controller.applyAuthoritativeStateForTesting(
      _state(
        version: 1,
        status: GameMatchStatus.finished,
        endReason: GameMatchEndReason.normal,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(store.clearCount, 1);
  });
}

GameSessionController _controller(
  GameFeedbackService feedback, {
  ResumableMatchStore? resumableMatchStore,
}) {
  return GameSessionController(
    nakamaService: NakamaService(),
    session: nakama.Session(
      token: 'test-token',
      refreshToken: 'test-refresh-token',
      created: false,
      vars: const {},
      userId: 'session-user',
      expiresAt: DateTime.utc(2100),
      refreshExpiresAt: DateTime.utc(2100),
    ),
    feedbackService: feedback,
    resumableMatchStore: resumableMatchStore ?? _ResumableStore(),
  );
}

class _ResumableStore implements ResumableMatchStore {
  int clearCount = 0;

  @override
  Future<void> clear() async => clearCount += 1;

  @override
  Future<String?> read() async => null;

  @override
  Future<void> save(String matchId) async {}
}

GameStateView _state({
  required int version,
  GameMatchStatus status = GameMatchStatus.active,
  GameMatchEndReason? endReason,
}) {
  const card = GameCard(
    cardId: 'session-card',
    color: GameCardColor.red,
    shape: GameCardShape.star,
    count: 2,
  );
  return GameStateView(
    stateVersion: version,
    status: status,
    elapsedTimeMs: 1000,
    myHand: status == GameMatchStatus.finished ? const [] : const [card],
    myDeckCount: status == GameMatchStatus.finished ? 0 : 10,
    opponentHandCount: 2,
    opponentDeckCount: 10,
    pile1: const CenterPileView(topCard: card),
    pile2: const CenterPileView(topCard: card),
    winnerId: status == GameMatchStatus.finished ? 'session-user' : null,
    winnerName: status == GameMatchStatus.finished ? 'You' : null,
    endReason: endReason,
  );
}

GameFeedbackService _feedbackService() {
  return GameFeedbackService(
    preferencesStore: _Store(),
    audioBackend: _Audio(),
    vibrationPlayer: (_) async {},
  );
}

class _Store implements GameFeedbackPreferencesStore {
  @override
  Future<GameFeedbackPreferences> load() async =>
      GameFeedbackPreferences.defaults;

  @override
  Future<void> setSoundEffectsEnabled(bool enabled) async {}

  @override
  Future<void> setVibrationEnabled(bool enabled) async {}
}

class _Audio implements GameFeedbackAudioBackend {
  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> playExclusive(
    GameFeedbackCue cue, {
    Duration startWithin = const Duration(milliseconds: 300),
  }) async => true;

  @override
  Future<void> stopAll() async {}
}
