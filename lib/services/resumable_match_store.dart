import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ResumableMatchStore {
  Future<String?> read();

  Future<void> save(String matchId);

  Future<void> clear();
}

class SharedPreferencesResumableMatchStore implements ResumableMatchStore {
  SharedPreferencesResumableMatchStore({
    required String userId,
    SharedPreferencesAsync? preferences,
  }) : _key = 'sprint_resumable_match_$userId',
       _preferences = preferences ?? SharedPreferencesAsync();

  final String _key;
  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read() async {
    final value = await _preferences.getString(_key);
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  @override
  Future<void> save(String matchId) {
    final normalized = matchId.trim();
    if (normalized.isEmpty) return clear();
    return _preferences.setString(_key, normalized);
  }

  @override
  Future<void> clear() => _preferences.remove(_key);
}
