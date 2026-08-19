class GameFeedbackPreferences {
  const GameFeedbackPreferences({
    this.soundEffectsEnabled = true,
    this.vibrationEnabled = true,
  });

  static const defaults = GameFeedbackPreferences();

  final bool soundEffectsEnabled;
  final bool vibrationEnabled;

  GameFeedbackPreferences copyWith({
    bool? soundEffectsEnabled,
    bool? vibrationEnabled,
  }) {
    return GameFeedbackPreferences(
      soundEffectsEnabled: soundEffectsEnabled ?? this.soundEffectsEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GameFeedbackPreferences &&
      soundEffectsEnabled == other.soundEffectsEnabled &&
      vibrationEnabled == other.vibrationEnabled;

  @override
  int get hashCode => Object.hash(soundEffectsEnabled, vibrationEnabled);
}

enum GameFeedbackPreference { soundEffects, vibration }

enum GameFeedbackPreferenceUpdateStatus { saved, unchanged, failed, disposed }

class GameFeedbackPreferenceUpdateResult {
  const GameFeedbackPreferenceUpdateResult({
    required this.preference,
    required this.status,
    required this.requestedValue,
    required this.effectiveValue,
    this.error,
  });

  final GameFeedbackPreference preference;
  final GameFeedbackPreferenceUpdateStatus status;
  final bool requestedValue;
  final bool effectiveValue;
  final Object? error;

  bool get succeeded =>
      status == GameFeedbackPreferenceUpdateStatus.saved ||
      status == GameFeedbackPreferenceUpdateStatus.unchanged;
}
