import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game_feedback_preferences.dart';

void main() {
  test('feedback preferences default both channels to enabled', () {
    expect(GameFeedbackPreferences.defaults.soundEffectsEnabled, isTrue);
    expect(GameFeedbackPreferences.defaults.vibrationEnabled, isTrue);
  });

  test('copyWith changes only the requested preference', () {
    expect(
      GameFeedbackPreferences.defaults.copyWith(soundEffectsEnabled: false),
      const GameFeedbackPreferences(
        soundEffectsEnabled: false,
        vibrationEnabled: true,
      ),
    );
    expect(
      GameFeedbackPreferences.defaults.copyWith(vibrationEnabled: false),
      const GameFeedbackPreferences(
        soundEffectsEnabled: true,
        vibrationEnabled: false,
      ),
    );
  });

  test('preference update results distinguish success from failure', () {
    const saved = GameFeedbackPreferenceUpdateResult(
      preference: GameFeedbackPreference.soundEffects,
      status: GameFeedbackPreferenceUpdateStatus.saved,
      requestedValue: false,
      effectiveValue: false,
    );
    const failed = GameFeedbackPreferenceUpdateResult(
      preference: GameFeedbackPreference.vibration,
      status: GameFeedbackPreferenceUpdateStatus.failed,
      requestedValue: false,
      effectiveValue: true,
    );

    expect(saved.succeeded, isTrue);
    expect(failed.succeeded, isFalse);
  });
}
