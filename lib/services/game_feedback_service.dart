import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/game_feedback_preferences.dart';
import 'game_feedback_audio.dart';
import 'game_feedback_cue.dart';
import 'game_feedback_preferences_store.dart';

export 'game_feedback_cue.dart';

typedef GameFeedbackPlayer = Future<void> Function(GameFeedbackCue cue);

/// App-scoped coordinator for non-essential sound and haptic feedback.
///
/// Authoritative gameplay never awaits platform audio or haptics directly. This
/// service loads preferences before accepting cues, suppresses background cues,
/// arbitrates simultaneous semantic events, and contains all platform failures.
class GameFeedbackService extends ChangeNotifier with WidgetsBindingObserver {
  GameFeedbackService({
    GameFeedbackPreferencesStore? preferencesStore,
    GameFeedbackAudioBackend? audioBackend,
    GameFeedbackPlayer? vibrationPlayer,
    GameFeedbackPreferences initialPreferences =
        GameFeedbackPreferences.defaults,
    Duration coalescingWindow = const Duration(milliseconds: 18),
    Duration cueFreshness = const Duration(milliseconds: 300),
    bool initiallyAppActive = true,
  }) : _preferencesStore =
           preferencesStore ?? SharedPreferencesGameFeedbackStore(),
       _audioBackend = audioBackend ?? AudioplayersGameFeedbackAudio(),
       _vibrationPlayer = vibrationPlayer ?? _playSystemHaptic,
       _preferences = initialPreferences,
       _persistedSoundEffectsEnabled = initialPreferences.soundEffectsEnabled,
       _persistedVibrationEnabled = initialPreferences.vibrationEnabled,
       _coalescingWindow = coalescingWindow,
       _cueFreshness = cueFreshness,
       _isAppActive = initiallyAppActive;

  final GameFeedbackPreferencesStore _preferencesStore;
  final GameFeedbackAudioBackend _audioBackend;
  final GameFeedbackPlayer _vibrationPlayer;
  final Duration _coalescingWindow;
  final Duration _cueFreshness;
  final Stopwatch _clock = Stopwatch()..start();

  GameFeedbackPreferences _preferences;
  Future<void>? _initialization;
  Future<void> _soundSaveQueue = Future<void>.value();
  Future<void> _vibrationSaveQueue = Future<void>.value();
  bool _persistedSoundEffectsEnabled;
  bool _persistedVibrationEnabled;
  int _soundRevision = 0;
  int _vibrationRevision = 0;
  bool _initialized = false;
  bool _disposed = false;
  bool _observingLifecycle = false;
  bool _isAppActive;
  _PendingCue? _pendingCue;
  Timer? _cueTimer;
  GameFeedbackCue? _reservedCue;
  Duration? _reservedAt;
  int _reservationRevision = 0;
  GameFeedbackCue? _lastPlayedCue;
  Duration? _lastPlayedAt;

  GameFeedbackPreferences get preferences => _preferences;
  bool get isInitialized => _initialized;
  bool get isAppActive => _isAppActive;
  bool get soundEffectsEnabled => _preferences.soundEffectsEnabled;
  bool get vibrationEnabled => _preferences.vibrationEnabled;

  /// Loads persisted settings exactly once.
  ///
  /// Audio prewarming starts after preferences are known, but deliberately does
  /// not hold readiness behind platform decoding of the complete cue palette.
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    GameFeedbackPreferences loaded;
    try {
      loaded = await _preferencesStore.load();
    } catch (_) {
      loaded = _preferences;
    }
    if (_disposed) return;
    _preferences = loaded;
    _persistedSoundEffectsEnabled = loaded.soundEffectsEnabled;
    _persistedVibrationEnabled = loaded.vibrationEnabled;
    if (loaded.soundEffectsEnabled) {
      unawaited(_prepareAudioSafely());
    }
    _initialized = true;
    notifyListeners();
  }

  void attachToAppLifecycle() {
    if (_disposed || _observingLifecycle) return;
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _observingLifecycle = true;
    _setAppActive(
      binding.lifecycleState == null ||
          binding.lifecycleState == AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setAppActive(state == AppLifecycleState.resumed);
  }

  void _setAppActive(bool active) {
    if (_disposed || active == _isAppActive) return;
    _isAppActive = active;
    if (!active) {
      _cancelPendingCue();
      _clearReservation();
      unawaited(_safely(_audioBackend.stopAll));
    }
  }

  Future<GameFeedbackPreferenceUpdateResult> setSoundEffectsEnabled(
    bool enabled,
  ) async {
    await initialize();
    if (_disposed) {
      return _disposedResult(GameFeedbackPreference.soundEffects, enabled);
    }
    if (_preferences.soundEffectsEnabled == enabled) {
      return _unchangedResult(GameFeedbackPreference.soundEffects, enabled);
    }

    final revision = ++_soundRevision;
    _preferences = _preferences.copyWith(soundEffectsEnabled: enabled);
    if (!enabled) unawaited(_safely(_audioBackend.stopAll));
    notifyListeners();
    final operation = _soundSaveQueue.then<void>((_) async {
      await _preferencesStore.setSoundEffectsEnabled(enabled);
      _persistedSoundEffectsEnabled = enabled;
    });
    _soundSaveQueue = operation.then<void>((_) {}, onError: (_, _) {});

    try {
      await operation;
      if (!_disposed && enabled) unawaited(_prepareAudioSafely());
      return GameFeedbackPreferenceUpdateResult(
        preference: GameFeedbackPreference.soundEffects,
        status: GameFeedbackPreferenceUpdateStatus.saved,
        requestedValue: enabled,
        effectiveValue: _preferences.soundEffectsEnabled,
      );
    } catch (error) {
      if (!_disposed && revision == _soundRevision) {
        _preferences = _preferences.copyWith(
          soundEffectsEnabled: _persistedSoundEffectsEnabled,
        );
        notifyListeners();
      }
      return GameFeedbackPreferenceUpdateResult(
        preference: GameFeedbackPreference.soundEffects,
        status: GameFeedbackPreferenceUpdateStatus.failed,
        requestedValue: enabled,
        effectiveValue: _preferences.soundEffectsEnabled,
        error: error,
      );
    }
  }

  Future<GameFeedbackPreferenceUpdateResult> setVibrationEnabled(
    bool enabled,
  ) async {
    await initialize();
    if (_disposed) {
      return _disposedResult(GameFeedbackPreference.vibration, enabled);
    }
    if (_preferences.vibrationEnabled == enabled) {
      return _unchangedResult(GameFeedbackPreference.vibration, enabled);
    }

    final revision = ++_vibrationRevision;
    _preferences = _preferences.copyWith(vibrationEnabled: enabled);
    notifyListeners();
    final operation = _vibrationSaveQueue.then<void>((_) async {
      await _preferencesStore.setVibrationEnabled(enabled);
      _persistedVibrationEnabled = enabled;
    });
    _vibrationSaveQueue = operation.then<void>((_) {}, onError: (_, _) {});

    try {
      await operation;
      return GameFeedbackPreferenceUpdateResult(
        preference: GameFeedbackPreference.vibration,
        status: GameFeedbackPreferenceUpdateStatus.saved,
        requestedValue: enabled,
        effectiveValue: _preferences.vibrationEnabled,
      );
    } catch (error) {
      if (!_disposed && revision == _vibrationRevision) {
        _preferences = _preferences.copyWith(
          vibrationEnabled: _persistedVibrationEnabled,
        );
        notifyListeners();
      }
      return GameFeedbackPreferenceUpdateResult(
        preference: GameFeedbackPreference.vibration,
        status: GameFeedbackPreferenceUpdateStatus.failed,
        requestedValue: enabled,
        effectiveValue: _preferences.vibrationEnabled,
        error: error,
      );
    }
  }

  GameFeedbackPreferenceUpdateResult _unchangedResult(
    GameFeedbackPreference preference,
    bool value,
  ) {
    return GameFeedbackPreferenceUpdateResult(
      preference: preference,
      status: GameFeedbackPreferenceUpdateStatus.unchanged,
      requestedValue: value,
      effectiveValue: value,
    );
  }

  GameFeedbackPreferenceUpdateResult _disposedResult(
    GameFeedbackPreference preference,
    bool value,
  ) {
    return GameFeedbackPreferenceUpdateResult(
      preference: preference,
      status: GameFeedbackPreferenceUpdateStatus.disposed,
      requestedValue: value,
      effectiveValue: preference == GameFeedbackPreference.soundEffects
          ? _preferences.soundEffectsEnabled
          : _preferences.vibrationEnabled,
    );
  }

  Future<void> selection() => _emit(GameFeedbackCue.selection);
  Future<void> illegalMove() => _emit(GameFeedbackCue.illegalMove);
  Future<void> acceptedMove() => _emit(GameFeedbackCue.acceptedMove);
  Future<void> opponentMove() => _emit(GameFeedbackCue.opponentMove);
  Future<void> pileReset() => _emit(GameFeedbackCue.pileReset);

  Future<void> countdown(int secondsRemaining) {
    if (secondsRemaining == 0) return _emit(GameFeedbackCue.countdownGo);
    if (secondsRemaining >= 1 && secondsRemaining <= 3) {
      return _emit(GameFeedbackCue.countdownTick);
    }
    return Future<void>.value();
  }

  Future<void> win() => _emit(GameFeedbackCue.win);
  Future<void> loss() => _emit(GameFeedbackCue.loss);
  Future<void> neutralEnd() => _emit(GameFeedbackCue.neutralEnd);

  Future<void> reconnect(GameReconnectFeedback state) => _emit(switch (state) {
    GameReconnectFeedback.reconnecting => GameFeedbackCue.reconnecting,
    GameReconnectFeedback.restored => GameFeedbackCue.reconnected,
  });

  Future<void> _emit(GameFeedbackCue cue) async {
    final emittedAt = _clock.elapsed;
    await initialize();
    if (_disposed || !_isAppActive) return;
    if (!soundEffectsEnabled && !vibrationEnabled) return;
    if (_isStale(emittedAt)) return;

    final completion = Completer<void>();
    final pending = _pendingCue;
    if (pending == null) {
      _pendingCue = _PendingCue(cue, emittedAt, completion);
      if (_coalescingWindow == Duration.zero) {
        scheduleMicrotask(_flushPendingCue);
      } else {
        _cueTimer = Timer(_coalescingWindow, _flushPendingCue);
      }
    } else {
      pending.completions.add(completion);
      if (cue.priority > pending.cue.priority) {
        pending
          ..cue = cue
          ..emittedAt = emittedAt;
      }
    }
    await completion.future;
  }

  Future<void> _flushPendingCue() async {
    _cueTimer = null;
    final pending = _pendingCue;
    _pendingCue = null;
    if (pending == null) return;

    if (_disposed ||
        !_isAppActive ||
        _isStale(pending.emittedAt) ||
        _shouldSuppress(pending.cue)) {
      pending.complete();
      return;
    }

    final reservationRevision = ++_reservationRevision;
    _reservedCue = pending.cue;
    _reservedAt = _clock.elapsed;

    final work = <Future<bool>>[];
    final remaining = _cueFreshness - (_clock.elapsed - pending.emittedAt);
    if (soundEffectsEnabled) {
      if (remaining > Duration.zero) {
        work.add(
          _safelyBool(
            () => _audioBackend.playExclusive(
              pending.cue,
              startWithin: remaining,
            ),
          ),
        );
      }
    }
    if (vibrationEnabled &&
        pending.cue.usesVibration &&
        remaining > Duration.zero) {
      work.add(
        _safelyBool(() async {
          await _vibrationPlayer(pending.cue);
          return true;
        }, timeout: remaining),
      );
    }
    final played = work.isNotEmpty && (await Future.wait(work)).contains(true);
    if (reservationRevision == _reservationRevision) {
      if (played && !_disposed && _isAppActive) {
        _lastPlayedCue = pending.cue;
        _lastPlayedAt = _clock.elapsed;
      }
      _reservedCue = null;
      _reservedAt = null;
    }
    pending.complete();
  }

  bool _shouldSuppress(GameFeedbackCue cue) {
    if (_suppressedBy(cue, _reservedCue, _reservedAt)) return true;
    return _suppressedBy(cue, _lastPlayedCue, _lastPlayedAt);
  }

  bool _suppressedBy(
    GameFeedbackCue cue,
    GameFeedbackCue? anchorCue,
    Duration? anchorAt,
  ) {
    if (anchorCue == null || anchorAt == null) return false;
    final elapsed = _clock.elapsed - anchorAt;
    if (cue == anchorCue && elapsed < cue.repeatCooldown) return true;
    return cue.priority < anchorCue.priority &&
        elapsed < anchorCue.priorityHold;
  }

  bool _isStale(Duration emittedAt) {
    return _cueFreshness <= Duration.zero ||
        _clock.elapsed - emittedAt >= _cueFreshness;
  }

  void _cancelPendingCue() {
    _cueTimer?.cancel();
    _cueTimer = null;
    final pending = _pendingCue;
    _pendingCue = null;
    pending?.complete();
  }

  void _clearReservation() {
    _reservationRevision += 1;
    _reservedCue = null;
    _reservedAt = null;
  }

  Future<void> _prepareAudioSafely() => _safely(_audioBackend.initialize);

  static Future<void> _safely(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Feedback is decorative and must never interrupt authoritative gameplay.
    }
  }

  static Future<bool> _safelyBool(
    Future<bool> Function() action, {
    Duration? timeout,
  }) async {
    try {
      final operation = action();
      return await (timeout == null
          ? operation
          : operation.timeout(timeout, onTimeout: () => false));
    } catch (_) {
      return false;
    }
  }

  static Future<void> _playSystemHaptic(GameFeedbackCue cue) {
    return switch (cue) {
      GameFeedbackCue.selection => HapticFeedback.selectionClick(),
      GameFeedbackCue.illegalMove => HapticFeedback.vibrate(),
      GameFeedbackCue.acceptedMove ||
      GameFeedbackCue.countdownTick ||
      GameFeedbackCue.reconnected => HapticFeedback.lightImpact(),
      GameFeedbackCue.pileReset ||
      GameFeedbackCue.countdownGo ||
      GameFeedbackCue.loss ||
      GameFeedbackCue.neutralEnd ||
      GameFeedbackCue.reconnecting => HapticFeedback.mediumImpact(),
      GameFeedbackCue.win => HapticFeedback.heavyImpact(),
      GameFeedbackCue.opponentMove => Future<void>.value(),
    };
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    _cancelPendingCue();
    _clearReservation();
    unawaited(_shutdownAudio());
    super.dispose();
  }

  Future<void> _shutdownAudio() async {
    await _safely(_audioBackend.stopAll);
    await _safely(_audioBackend.dispose);
  }
}

class _PendingCue {
  _PendingCue(this.cue, this.emittedAt, Completer<void> completion)
    : completions = [completion];

  GameFeedbackCue cue;
  Duration emittedAt;
  final List<Completer<void>> completions;

  void complete() {
    for (final completion in completions) {
      if (!completion.isCompleted) completion.complete();
    }
  }
}

extension on GameFeedbackCue {
  int get priority => switch (this) {
    GameFeedbackCue.selection => 0,
    GameFeedbackCue.opponentMove => 1,
    GameFeedbackCue.acceptedMove || GameFeedbackCue.countdownTick => 2,
    GameFeedbackCue.illegalMove => 3,
    GameFeedbackCue.pileReset || GameFeedbackCue.reconnecting => 5,
    GameFeedbackCue.reconnected => 6,
    GameFeedbackCue.countdownGo => 7,
    GameFeedbackCue.win ||
    GameFeedbackCue.loss ||
    GameFeedbackCue.neutralEnd => 8,
  };

  bool get usesVibration => this != GameFeedbackCue.opponentMove;

  Duration get repeatCooldown => switch (this) {
    GameFeedbackCue.selection => const Duration(milliseconds: 65),
    GameFeedbackCue.acceptedMove ||
    GameFeedbackCue.opponentMove => const Duration(milliseconds: 90),
    GameFeedbackCue.countdownTick => const Duration(milliseconds: 250),
    GameFeedbackCue.illegalMove => const Duration(milliseconds: 180),
    GameFeedbackCue.reconnected => const Duration(milliseconds: 400),
    GameFeedbackCue.pileReset ||
    GameFeedbackCue.reconnecting => const Duration(milliseconds: 600),
    GameFeedbackCue.countdownGo => const Duration(milliseconds: 500),
    GameFeedbackCue.win ||
    GameFeedbackCue.loss ||
    GameFeedbackCue.neutralEnd => const Duration(milliseconds: 1500),
  };

  Duration get priorityHold => switch (this) {
    GameFeedbackCue.selection ||
    GameFeedbackCue.acceptedMove ||
    GameFeedbackCue.opponentMove ||
    GameFeedbackCue.countdownTick => const Duration(milliseconds: 100),
    GameFeedbackCue.illegalMove => const Duration(milliseconds: 220),
    GameFeedbackCue.reconnected => const Duration(milliseconds: 350),
    GameFeedbackCue.pileReset ||
    GameFeedbackCue.reconnecting => const Duration(milliseconds: 600),
    GameFeedbackCue.countdownGo => const Duration(milliseconds: 500),
    GameFeedbackCue.win ||
    GameFeedbackCue.loss ||
    GameFeedbackCue.neutralEnd => const Duration(milliseconds: 1400),
  };
}
