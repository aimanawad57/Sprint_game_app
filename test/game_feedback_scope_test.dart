import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game_feedback_preferences.dart';
import 'package:sprint_app/services/game_feedback_audio.dart';
import 'package:sprint_app/services/game_feedback_preferences_store.dart';
import 'package:sprint_app/services/game_feedback_service.dart';
import 'package:sprint_app/widgets/game_feedback_scope.dart';

void main() {
  testWidgets('scope exposes the same app-owned feedback service', (
    tester,
  ) async {
    final service = GameFeedbackService(
      preferencesStore: _Store(),
      audioBackend: _Audio(),
      vibrationPlayer: (_) async {},
    );
    addTearDown(service.dispose);
    GameFeedbackService? found;

    await tester.pumpWidget(
      GameFeedbackScope(
        service: service,
        child: Builder(
          builder: (context) {
            found = GameFeedbackScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(found, same(service));
  });
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
