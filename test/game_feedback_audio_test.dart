import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/services/game_feedback_audio.dart';
import 'package:sprint_app/services/game_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every semantic cue has a healthy bundled PCM WAV asset', () async {
    expect(
      AudioplayersGameFeedbackAudio.assetPaths.keys.toSet(),
      GameFeedbackCue.values.toSet(),
    );
    expect(
      AudioplayersGameFeedbackAudio.cueDurations.keys.toSet(),
      GameFeedbackCue.values.toSet(),
    );

    for (final entry in AudioplayersGameFeedbackAudio.assetPaths.entries) {
      final cue = entry.key;
      final path = entry.value;
      final wav = await rootBundle.load('assets/$path');
      expect(wav.lengthInBytes, greaterThan(44), reason: path);
      expect(_ascii(wav, 0, 4), 'RIFF', reason: path);
      expect(_ascii(wav, 8, 4), 'WAVE', reason: path);
      expect(_ascii(wav, 36, 4), 'data', reason: path);
      expect(wav.getUint16(20, Endian.little), 1, reason: '$path PCM format');
      expect(wav.getUint16(22, Endian.little), 1, reason: '$path channels');
      expect(
        wav.getUint32(24, Endian.little),
        44100,
        reason: '$path sample rate',
      );
      expect(wav.getUint16(34, Endian.little), 16, reason: '$path bit depth');

      final blockAlign = wav.getUint16(32, Endian.little);
      final dataBytes = wav.getUint32(40, Endian.little);
      expect(wav.lengthInBytes, 44 + dataBytes, reason: '$path data size');
      final sampleCount = dataBytes ~/ blockAlign;
      final durationMs = sampleCount * 1000 / 44100;
      final expectedDurationMs =
          AudioplayersGameFeedbackAudio.cueDurations[cue]!.inMicroseconds /
          1000;
      expect(
        (durationMs - expectedDurationMs).abs(),
        lessThan(0.1),
        reason: '$path playback timer must not trim or overrun the asset',
      );

      var peak = 0;
      var clippedSamples = 0;
      var sumSquares = 0.0;
      for (var offset = 44; offset < 44 + dataBytes; offset += blockAlign) {
        final sample = wav.getInt16(offset, Endian.little);
        final magnitude = sample.abs();
        if (magnitude > peak) peak = magnitude;
        if (magnitude >= 32760) clippedSamples += 1;
        final normalized = sample / 32768;
        sumSquares += normalized * normalized;
      }
      final rms = math.sqrt(sumSquares / sampleCount);
      expect(peak, greaterThan(4000), reason: '$path must be audible');
      expect(peak, lessThan(32000), reason: '$path needs clipping headroom');
      expect(rms, greaterThan(0.05), reason: '$path must not be mostly silent');
      expect(clippedSamples, 0, reason: '$path must not clip');
      expect(wav.getInt16(44, Endian.little).abs(), lessThanOrEqualTo(32));
      expect(
        wav.getInt16(44 + dataBytes - blockAlign, Endian.little).abs(),
        lessThanOrEqualTo(512),
        reason: '$path should fade out without an audible click',
      );
    }
  });

  test('palette pools prewarm concurrently', () async {
    final gate = Completer<void>();
    final requested = <GameFeedbackCue>[];
    final backend = AudioplayersGameFeedbackAudio(
      poolFactory: (cue, _) async {
        requested.add(cue);
        await gate.future;
        return _FakePool(cue, _PlaybackProbe());
      },
    );

    final initialization = backend.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(requested.toSet(), GameFeedbackCue.values.toSet());
    gate.complete();
    await initialization;
    await backend.dispose();
  });

  test('a transient preload failure is retried and recovers', () async {
    final attempts = <GameFeedbackCue, int>{};
    final probe = _PlaybackProbe();
    final backend = AudioplayersGameFeedbackAudio(
      poolFactory: (cue, _) async {
        attempts[cue] = (attempts[cue] ?? 0) + 1;
        if (cue == GameFeedbackCue.selection && attempts[cue] == 1) {
          throw StateError('temporary decoder startup failure');
        }
        return _FakePool(cue, probe);
      },
    );

    await backend.initialize();
    expect(attempts[GameFeedbackCue.selection], 1);

    await backend.initialize();
    expect(attempts[GameFeedbackCue.selection], 2);
    for (final cue in GameFeedbackCue.values) {
      expect(attempts[cue], cue == GameFeedbackCue.selection ? 2 : 1);
    }

    expect(await backend.playExclusive(GameFeedbackCue.selection), isTrue);
    expect(probe.started, [GameFeedbackCue.selection]);
    await backend.dispose();
  });

  test(
    'exclusive playback stops the old cue before starting another',
    () async {
      final probe = _PlaybackProbe();
      final backend = AudioplayersGameFeedbackAudio(
        poolFactory: (cue, _) async => _FakePool(cue, probe),
      );

      await backend.playExclusive(GameFeedbackCue.selection);
      await backend.playExclusive(GameFeedbackCue.win);

      expect(probe.started, [GameFeedbackCue.selection, GameFeedbackCue.win]);
      expect(probe.stopped, [GameFeedbackCue.selection]);
      expect(probe.activeCount, 1);
      expect(probe.maximumActiveCount, 1);

      await backend.stopAll();
      expect(probe.stopped, [GameFeedbackCue.selection, GameFeedbackCue.win]);
      expect(probe.activeCount, 0);
      await backend.dispose();
    },
  );

  test('a cue whose pool misses its start window never plays late', () async {
    final gate = Completer<GameFeedbackAudioPool>();
    final probe = _PlaybackProbe();
    final backend = AudioplayersGameFeedbackAudio(
      poolFactory: (_, _) => gate.future,
    );

    await backend.playExclusive(
      GameFeedbackCue.selection,
      startWithin: const Duration(milliseconds: 10),
    );
    expect(probe.started, isEmpty);

    gate.complete(_FakePool(GameFeedbackCue.selection, probe));
    await Future<void>.delayed(Duration.zero);
    expect(probe.started, isEmpty);
    await backend.dispose();
  });

  test('stopAll invalidates a cue that is still preloading', () async {
    final gate = Completer<GameFeedbackAudioPool>();
    final probe = _PlaybackProbe();
    final backend = AudioplayersGameFeedbackAudio(
      poolFactory: (_, _) => gate.future,
    );

    final pending = backend.playExclusive(GameFeedbackCue.countdownGo);
    await Future<void>.delayed(Duration.zero);
    await backend.stopAll();
    gate.complete(_FakePool(GameFeedbackCue.countdownGo, probe));
    await pending;

    expect(probe.started, isEmpty);
    await backend.dispose();
  });

  test('dispose does not wait for or revive a pending preload', () async {
    final gate = Completer<GameFeedbackAudioPool>();
    final probe = _PlaybackProbe();
    final backend = AudioplayersGameFeedbackAudio(
      poolFactory: (_, _) => gate.future,
    );

    final pending = backend.playExclusive(GameFeedbackCue.win);
    await Future<void>.delayed(Duration.zero);
    await backend.dispose().timeout(const Duration(milliseconds: 100));
    gate.complete(_FakePool(GameFeedbackCue.win, probe));
    await pending;
    await Future<void>.delayed(Duration.zero);

    expect(probe.started, isEmpty);
    expect(probe.disposed, [GameFeedbackCue.win]);
  });
}

String _ascii(ByteData data, int offset, int length) {
  return String.fromCharCodes([
    for (var index = 0; index < length; index += 1)
      data.getUint8(offset + index),
  ]);
}

class _PlaybackProbe {
  final List<GameFeedbackCue> started = [];
  final List<GameFeedbackCue> stopped = [];
  final List<GameFeedbackCue> disposed = [];
  int activeCount = 0;
  int maximumActiveCount = 0;
}

class _FakePool implements GameFeedbackAudioPool {
  _FakePool(this.cue, this.probe);

  final GameFeedbackCue cue;
  final _PlaybackProbe probe;
  bool _disposed = false;

  @override
  Future<StopFunction> start({required double volume}) async {
    if (_disposed) throw StateError('pool disposed');
    probe.started.add(cue);
    probe.activeCount += 1;
    if (probe.activeCount > probe.maximumActiveCount) {
      probe.maximumActiveCount = probe.activeCount;
    }
    var stopped = false;
    return () async {
      if (stopped) return;
      stopped = true;
      probe.stopped.add(cue);
      probe.activeCount -= 1;
    };
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    probe.disposed.add(cue);
  }
}
