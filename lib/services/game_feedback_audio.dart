import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'game_feedback_cue.dart';

/// Exclusive playback contract used by [GameFeedbackService].
///
/// A new cue replaces the current cue, and [stopAll] also invalidates any cue
/// that is still waiting for its asset to preload.
abstract interface class GameFeedbackAudioBackend {
  Future<void> initialize();

  /// Returns true only when the cue actually reached platform playback.
  Future<bool> playExclusive(
    GameFeedbackCue cue, {
    Duration startWithin = const Duration(milliseconds: 300),
  });

  Future<void> stopAll();

  Future<void> dispose();
}

@visibleForTesting
abstract interface class GameFeedbackAudioPool {
  Future<StopFunction> start({required double volume});

  Future<void> dispose();
}

@visibleForTesting
typedef GameFeedbackAudioPoolFactory =
    Future<GameFeedbackAudioPool> Function(
      GameFeedbackCue cue,
      String assetPath,
    );

/// Preloaded, low-latency playback for the short original game cue palette.
class AudioplayersGameFeedbackAudio implements GameFeedbackAudioBackend {
  AudioplayersGameFeedbackAudio({GameFeedbackAudioPoolFactory? poolFactory})
    : _poolFactory = poolFactory ?? _createPool;

  static const Map<GameFeedbackCue, String> assetPaths = {
    GameFeedbackCue.selection: 'audio/game/selection.wav',
    GameFeedbackCue.illegalMove: 'audio/game/illegal_move.wav',
    GameFeedbackCue.acceptedMove: 'audio/game/accepted_move.wav',
    GameFeedbackCue.opponentMove: 'audio/game/opponent_move.wav',
    GameFeedbackCue.pileReset: 'audio/game/pile_reset.wav',
    GameFeedbackCue.countdownTick: 'audio/game/countdown_tick.wav',
    GameFeedbackCue.countdownGo: 'audio/game/countdown_go.wav',
    GameFeedbackCue.win: 'audio/game/win.wav',
    GameFeedbackCue.loss: 'audio/game/loss.wav',
    GameFeedbackCue.neutralEnd: 'audio/game/neutral_end.wav',
    GameFeedbackCue.reconnecting: 'audio/game/reconnecting.wav',
    GameFeedbackCue.reconnected: 'audio/game/reconnected.wav',
  };

  @visibleForTesting
  static const Map<GameFeedbackCue, Duration> cueDurations = {
    GameFeedbackCue.selection: Duration(milliseconds: 80),
    GameFeedbackCue.illegalMove: Duration(milliseconds: 190),
    GameFeedbackCue.acceptedMove: Duration(milliseconds: 180),
    GameFeedbackCue.opponentMove: Duration(milliseconds: 150),
    GameFeedbackCue.pileReset: Duration(milliseconds: 430),
    GameFeedbackCue.countdownTick: Duration(milliseconds: 80),
    GameFeedbackCue.countdownGo: Duration(milliseconds: 350),
    GameFeedbackCue.win: Duration(milliseconds: 730),
    GameFeedbackCue.loss: Duration(milliseconds: 570),
    GameFeedbackCue.neutralEnd: Duration(milliseconds: 460),
    GameFeedbackCue.reconnecting: Duration(milliseconds: 390),
    GameFeedbackCue.reconnected: Duration(milliseconds: 430),
  };

  final GameFeedbackAudioPoolFactory _poolFactory;
  final Map<GameFeedbackCue, GameFeedbackAudioPool> _pools = {};
  final Map<GameFeedbackCue, Future<GameFeedbackAudioPool?>> _poolPreparations =
      {};
  final Stopwatch _clock = Stopwatch()..start();
  Future<void> _operationQueue = Future<void>.value();
  _ActivePlayback? _activePlayback;
  int _playGeneration = 0;
  bool _disposed = false;

  /// Starts every preload concurrently. Callers do not need to await this
  /// before requesting a cue; [playExclusive] can await just that cue's pool.
  @override
  Future<void> initialize() {
    if (_disposed) return Future<void>.value();
    return Future.wait<void>([
      for (final cue in assetPaths.keys) _preparePool(cue).then<void>((_) {}),
    ]);
  }

  Future<GameFeedbackAudioPool?> _preparePool(GameFeedbackCue cue) {
    final ready = _pools[cue];
    if (ready != null) return Future<GameFeedbackAudioPool?>.value(ready);
    final pending = _poolPreparations[cue];
    if (pending != null) return pending;

    late final Future<GameFeedbackAudioPool?> preparation;
    preparation = _createAndCachePool(cue).whenComplete(() {
      if (identical(_poolPreparations[cue], preparation)) {
        _poolPreparations.remove(cue);
      }
    });
    _poolPreparations[cue] = preparation;
    return preparation;
  }

  Future<GameFeedbackAudioPool?> _createAndCachePool(
    GameFeedbackCue cue,
  ) async {
    if (_disposed) return null;
    final assetPath = assetPaths[cue];
    if (assetPath == null) return null;
    try {
      final pool = await _poolFactory(cue, assetPath);
      if (_disposed) {
        await _disposePoolSafely(pool);
        return null;
      }
      _pools[cue] = pool;
      return pool;
    } catch (error) {
      debugPrint('Could not preload ${cue.name} game audio: $error');
      return null;
    }
  }

  @override
  Future<bool> playExclusive(
    GameFeedbackCue cue, {
    Duration startWithin = const Duration(milliseconds: 300),
  }) async {
    if (_disposed || startWithin <= Duration.zero) return false;

    final generation = ++_playGeneration;
    final requestedAt = _clock.elapsed;
    final poolFuture = _preparePool(cue);
    final pool = await _awaitPoolUntil(poolFuture, startWithin);
    if (pool == null || !_canStart(generation, requestedAt, startWithin)) {
      return false;
    }

    var started = false;
    await _serialize(() async {
      if (!_canStart(generation, requestedAt, startWithin)) return;
      await _stopActiveLocked();
      if (!_canStart(generation, requestedAt, startWithin)) return;

      StopFunction stop;
      try {
        stop = await pool.start(volume: _volumeFor(cue));
      } catch (_) {
        return;
      }

      if (!_canStart(generation, requestedAt, startWithin)) {
        await _stopSafely(stop);
        return;
      }

      final playback = _ActivePlayback(stop);
      _activePlayback = playback;
      started = true;
      playback.timer = Timer(
        cueDurations[cue] ?? const Duration(milliseconds: 500),
        () => unawaited(_expirePlayback(playback)),
      );
    });
    return started;
  }

  Future<GameFeedbackAudioPool?> _awaitPoolUntil(
    Future<GameFeedbackAudioPool?> poolFuture,
    Duration timeout,
  ) async {
    try {
      return await poolFuture.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  bool _canStart(int generation, Duration requestedAt, Duration startWithin) {
    return !_disposed &&
        generation == _playGeneration &&
        _clock.elapsed - requestedAt < startWithin;
  }

  @override
  Future<void> stopAll() {
    _playGeneration += 1;
    return _serialize(_stopActiveLocked);
  }

  Future<void> _stopActiveLocked() async {
    final playback = _activePlayback;
    _activePlayback = null;
    playback?.timer?.cancel();
    if (playback != null) await _stopSafely(playback.stop);
  }

  Future<void> _expirePlayback(_ActivePlayback playback) {
    return _serialize(() async {
      if (!identical(_activePlayback, playback)) return;
      _activePlayback = null;
      playback.timer?.cancel();
      await _stopSafely(playback.stop);
    });
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _operationQueue.then<void>(
      (_) => operation(),
      onError: (_, _) => operation(),
    );
    _operationQueue = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  static double _volumeFor(GameFeedbackCue cue) => switch (cue) {
    GameFeedbackCue.selection || GameFeedbackCue.countdownTick => 0.52,
    GameFeedbackCue.acceptedMove => 0.48,
    GameFeedbackCue.opponentMove => 0.62,
    GameFeedbackCue.illegalMove || GameFeedbackCue.reconnecting => 0.68,
    GameFeedbackCue.pileReset || GameFeedbackCue.reconnected => 0.72,
    GameFeedbackCue.countdownGo ||
    GameFeedbackCue.loss ||
    GameFeedbackCue.neutralEnd => 0.78,
    GameFeedbackCue.win => 0.84,
  };

  static Future<void> _stopSafely(StopFunction stop) async {
    try {
      await stop();
    } catch (_) {
      // A short cue may already have stopped on platforms that report completion.
    }
  }

  static Future<void> _disposePoolSafely(GameFeedbackAudioPool pool) async {
    try {
      await pool.dispose();
    } catch (_) {
      // Audio cleanup must not surface through gameplay or app lifecycle calls.
    }
  }

  static Future<GameFeedbackAudioPool> _createPool(
    GameFeedbackCue cue,
    String assetPath,
  ) async {
    final pool = await AudioPool.createFromAsset(
      path: assetPath,
      minPlayers: 1,
      maxPlayers: 1,
      playerMode: PlayerMode.lowLatency,
    );
    return _AudioplayersPool(pool);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _playGeneration += 1;
    await _serialize(_stopActiveLocked);

    // Do not hold lifecycle teardown behind platform asset decoding. A pool
    // that finishes later observes [_disposed] in [_preparePool] and disposes
    // itself without ever becoming playable.
    final pools = _pools.values.toSet().toList(growable: false);
    _pools.clear();
    await Future.wait<void>([
      for (final pool in pools) _disposePoolSafely(pool),
    ]);
  }
}

class _AudioplayersPool implements GameFeedbackAudioPool {
  const _AudioplayersPool(this.pool);

  final AudioPool pool;

  @override
  Future<StopFunction> start({required double volume}) {
    return pool.start(volume: volume);
  }

  @override
  Future<void> dispose() => pool.dispose();
}

class _ActivePlayback {
  _ActivePlayback(this.stop);

  final StopFunction stop;
  Timer? timer;
}
