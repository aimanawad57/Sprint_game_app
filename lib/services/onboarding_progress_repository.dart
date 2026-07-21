import 'dart:convert';

import 'package:nakama/nakama.dart' as nakama;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/onboarding_progress.dart';
import 'nakama_service.dart';

class OnboardingProgressRepository {
  OnboardingProgressRepository({
    required this.nakamaService,
    required this.session,
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final NakamaService nakamaService;
  final nakama.Session session;
  final SharedPreferencesAsync _preferences;

  String get _progressKey => 'sprint_onboarding_${session.userId}_progress';
  String get _pendingKey => 'sprint_onboarding_${session.userId}_pending';

  Future<OnboardingProgress> readCached() async {
    final encoded = await _preferences.getString(_progressKey);
    if (encoded == null) return const OnboardingProgress();
    try {
      return OnboardingProgress.fromJson(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
      );
    } catch (_) {
      return const OnboardingProgress();
    }
  }

  Future<OnboardingProgress> synchronize() async {
    final cached = await readCached();
    try {
      final remote = await nakamaService.loadOnboardingProgress(session);
      final merged = cached.merge(remote);
      final resolved = merged == remote
          ? remote
          : await nakamaService.mergeOnboardingProgress(session, merged);
      await _save(resolved, pending: false);
      return resolved;
    } catch (_) {
      return cached;
    }
  }

  Future<OnboardingProgress> update(
    OnboardingProgress Function(OnboardingProgress current) change,
  ) async {
    final changed = change(await readCached());
    await _save(changed, pending: true);
    try {
      final remote = await nakamaService.mergeOnboardingProgress(
        session,
        changed,
      );
      final merged = changed.merge(remote);
      await _save(merged, pending: false);
      return merged;
    } catch (_) {
      return changed;
    }
  }

  Future<bool> get hasPendingSync =>
      _preferences.getBool(_pendingKey).then((value) => value ?? false);

  Future<void> _save(OnboardingProgress progress, {required bool pending}) {
    return Future.wait([
      _preferences.setString(_progressKey, jsonEncode(progress.toJson())),
      _preferences.setBool(_pendingKey, pending),
    ]);
  }
}
