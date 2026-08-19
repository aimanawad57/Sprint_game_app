import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_feedback_preferences.dart';

abstract interface class GameFeedbackPreferencesStore {
  Future<GameFeedbackPreferences> load();

  Future<void> setSoundEffectsEnabled(bool enabled);

  Future<void> setVibrationEnabled(bool enabled);
}

class SharedPreferencesGameFeedbackStore
    implements GameFeedbackPreferencesStore {
  SharedPreferencesGameFeedbackStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const soundEffectsEnabledKey =
      'sprint_game_feedback_sound_effects_enabled';
  static const vibrationEnabledKey = 'sprint_game_feedback_vibration_enabled';

  final SharedPreferencesAsync _preferences;

  @override
  Future<GameFeedbackPreferences> load() async {
    final values = await Future.wait<bool?>([
      _preferences.getBool(soundEffectsEnabledKey),
      _preferences.getBool(vibrationEnabledKey),
    ]);
    return GameFeedbackPreferences(
      soundEffectsEnabled: values[0] ?? true,
      vibrationEnabled: values[1] ?? true,
    );
  }

  @override
  Future<void> setSoundEffectsEnabled(bool enabled) {
    return _preferences.setBool(soundEffectsEnabledKey, enabled);
  }

  @override
  Future<void> setVibrationEnabled(bool enabled) {
    return _preferences.setBool(vibrationEnabledKey, enabled);
  }
}
