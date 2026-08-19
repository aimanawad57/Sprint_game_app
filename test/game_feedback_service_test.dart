import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game_feedback_preferences.dart';
import 'package:sprint_app/services/game_feedback_audio.dart';
import 'package:sprint_app/services/game_feedback_preferences_store.dart';
import 'package:sprint_app/services/game_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryPreferencesStore store;
  late _FakeAudioBackend audio;
  late List<GameFeedbackCue> vibrations;
  late GameFeedbackService service;

  GameFeedbackService buildService({
    bool initiallyAppActive = true,
    Duration coalescingWindow = Duration.zero,
    Duration cueFreshness = const Duration(milliseconds: 300),
    GameFeedbackPlayer? vibrationPlayer,
  }) {
    return GameFeedbackService(
      preferencesStore: store,
      audioBackend: audio,
      vibrationPlayer: vibrationPlayer ?? (cue) async => vibrations.add(cue),
      initiallyAppActive: initiallyAppActive,
      coalescingWindow: coalescingWindow,
      cueFreshness: cueFreshness,
    );
  }

  setUp(() {
    store = _MemoryPreferencesStore();
    audio = _FakeAudioBackend();
    vibrations = [];
    service = buildService();
  });

  tearDown(() => service.dispose());

  test(
    'initialize loads persisted preferences and preloads enabled audio',
    () async {
      store.value = const GameFeedbackPreferences(
        soundEffectsEnabled: true,
        vibrationEnabled: false,
      );

      await service.initialize();
      await service.initialize();

      expect(service.isInitialized, isTrue);
      expect(service.preferences, store.value);
      expect(store.loadCount, 1);
      expect(audio.initializeCount, 1);
    },
  );

  test('preference readiness does not wait for palette prewarming', () async {
    audio.initializeGate = Completer<void>();

    await service.initialize().timeout(const Duration(milliseconds: 100));

    expect(service.isInitialized, isTrue);
    expect(audio.initializeCount, 1);
    audio.initializeGate!.complete();
  });

  test('disabled persisted sound does not preload audio', () async {
    store.value = const GameFeedbackPreferences(
      soundEffectsEnabled: false,
      vibrationEnabled: true,
    );

    await service.initialize();

    expect(audio.initializeCount, 0);
  });

  test('a cue waits for persisted preferences before emitting', () async {
    store.value = const GameFeedbackPreferences(
      soundEffectsEnabled: false,
      vibrationEnabled: false,
    );
    store.loadGate = Completer<void>();

    final cue = service.selection();
    await Future<void>.delayed(Duration.zero);
    expect(audio.played, isEmpty);
    expect(vibrations, isEmpty);

    store.loadGate!.complete();
    await cue;

    expect(audio.played, isEmpty);
    expect(vibrations, isEmpty);
  });

  test('a cue delayed by slow preference loading is dropped', () async {
    service.dispose();
    service = buildService(cueFreshness: const Duration(milliseconds: 10));
    store.loadGate = Completer<void>();

    final cue = service.selection();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    store.loadGate!.complete();
    await cue;

    expect(audio.played, isEmpty);
    expect(vibrations, isEmpty);
  });

  test('load failure safely retains enabled defaults', () async {
    store.loadError = StateError('storage unavailable');

    await service.initialize();

    expect(service.preferences, GameFeedbackPreferences.defaults);
    expect(service.isInitialized, isTrue);
  });

  test('sound and vibration settings control independent channels', () async {
    store.value = const GameFeedbackPreferences(
      soundEffectsEnabled: false,
      vibrationEnabled: true,
    );
    await service.selection();
    expect(audio.played, isEmpty);
    expect(vibrations, [GameFeedbackCue.selection]);

    service.dispose();
    store = _MemoryPreferencesStore(
      const GameFeedbackPreferences(
        soundEffectsEnabled: true,
        vibrationEnabled: false,
      ),
    );
    audio = _FakeAudioBackend();
    vibrations = [];
    service = buildService();
    await service.selection();

    expect(audio.played, [GameFeedbackCue.selection]);
    expect(vibrations, isEmpty);
  });

  test('every public semantic action emits its distinct sound cue', () async {
    final triggers =
        <GameFeedbackCue, Future<void> Function(GameFeedbackService)>{
          GameFeedbackCue.selection: (value) => value.selection(),
          GameFeedbackCue.illegalMove: (value) => value.illegalMove(),
          GameFeedbackCue.acceptedMove: (value) => value.acceptedMove(),
          GameFeedbackCue.opponentMove: (value) => value.opponentMove(),
          GameFeedbackCue.pileReset: (value) => value.pileReset(),
          GameFeedbackCue.countdownTick: (value) => value.countdown(3),
          GameFeedbackCue.countdownGo: (value) => value.countdown(0),
          GameFeedbackCue.win: (value) => value.win(),
          GameFeedbackCue.loss: (value) => value.loss(),
          GameFeedbackCue.neutralEnd: (value) => value.neutralEnd(),
          GameFeedbackCue.reconnecting: (value) =>
              value.reconnect(GameReconnectFeedback.reconnecting),
          GameFeedbackCue.reconnected: (value) =>
              value.reconnect(GameReconnectFeedback.restored),
        };

    for (final entry in triggers.entries) {
      final caseAudio = _FakeAudioBackend();
      final caseService = GameFeedbackService(
        preferencesStore: _MemoryPreferencesStore(
          const GameFeedbackPreferences(
            soundEffectsEnabled: true,
            vibrationEnabled: false,
          ),
        ),
        audioBackend: caseAudio,
        vibrationPlayer: (_) async {},
        coalescingWindow: Duration.zero,
      );

      await entry.value(caseService);
      expect(caseAudio.played, [entry.key], reason: entry.key.name);
      caseService.dispose();
    }
  });

  test('higher-priority terminal cue replaces a pending move cue', () async {
    await service.initialize();

    await Future.wait([service.acceptedMove(), service.win()]);

    expect(audio.played, [GameFeedbackCue.win]);
    expect(vibrations, [GameFeedbackCue.win]);
  });

  test(
    'same semantic cue is coalesced inside one arbitration window',
    () async {
      await service.initialize();

      await Future.wait([service.selection(), service.selection()]);

      expect(audio.played, [GameFeedbackCue.selection]);
      expect(vibrations, [GameFeedbackCue.selection]);
    },
  );

  test(
    'terminal priority hold suppresses immediately following decoration',
    () async {
      await service.win();
      await service.selection();

      expect(audio.played, [GameFeedbackCue.win]);
      expect(vibrations, [GameFeedbackCue.win]);
    },
  );

  test('an in-flight terminal cue reserves priority over lower cues', () async {
    store.value = const GameFeedbackPreferences(
      soundEffectsEnabled: true,
      vibrationEnabled: false,
    );
    await service.initialize();
    audio.playGate = Completer<void>();

    final terminal = service.win();
    await Future<void>.delayed(Duration.zero);
    final decoration = service.selection();
    await Future<void>.delayed(Duration.zero);

    expect(audio.played, [GameFeedbackCue.win]);
    audio.playGate!.complete();
    await Future.wait([terminal, decoration]);
  });

  test(
    'an audio cue that never starts does not reserve priority hold',
    () async {
      store.value = const GameFeedbackPreferences(
        soundEffectsEnabled: true,
        vibrationEnabled: false,
      );
      audio.playResult = false;
      await service.win();

      audio.playResult = true;
      await service.selection();

      expect(audio.played, [GameFeedbackCue.win, GameFeedbackCue.selection]);
    },
  );

  test('countdown maps 3-2-1 to tick and zero to GO', () async {
    await service.countdown(4);
    await service.countdown(3);
    await service.countdown(0);

    expect(audio.played, [
      GameFeedbackCue.countdownTick,
      GameFeedbackCue.countdownGo,
    ]);
    expect(vibrations, audio.played);
  });

  test('neutral end has its own terminal cue', () async {
    await service.neutralEnd();

    expect(audio.played, [GameFeedbackCue.neutralEnd]);
    expect(vibrations, [GameFeedbackCue.neutralEnd]);
  });

  test('restored reconnect cue replaces the reconnecting cue', () async {
    await service.reconnect(GameReconnectFeedback.reconnecting);
    await service.reconnect(GameReconnectFeedback.restored);

    expect(audio.played, [
      GameFeedbackCue.reconnecting,
      GameFeedbackCue.reconnected,
    ]);
    expect(vibrations, audio.played);
  });

  test('opponent movement is audible without vibrating', () async {
    await service.opponentMove();

    expect(audio.played, [GameFeedbackCue.opponentMove]);
    expect(vibrations, isEmpty);
  });

  test('inactive lifecycle suppresses cues until resumed', () async {
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await service.selection();
    expect(audio.played, isEmpty);

    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await service.selection();
    expect(audio.played, [GameFeedbackCue.selection]);
  });

  test('inactive lifecycle stops active audio immediately', () async {
    await service.selection();
    expect(audio.played, [GameFeedbackCue.selection]);

    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);

    expect(audio.stopAllCount, 1);
  });

  test('going inactive cancels pending cue futures safely', () async {
    service.dispose();
    service = buildService(coalescingWindow: const Duration(milliseconds: 100));
    final pending = service.win();
    await Future<void>.delayed(Duration.zero);

    service.didChangeAppLifecycleState(AppLifecycleState.paused);

    await expectLater(pending, completes);
    expect(audio.played, isEmpty);
  });

  test('audio and haptic failures never escape into gameplay', () async {
    audio.playError = StateError('audio unavailable');
    service.dispose();
    service = buildService(
      vibrationPlayer: (_) =>
          Future<void>.error(StateError('haptics unavailable')),
    );

    await expectLater(service.illegalMove(), completes);
  });

  test('sound persistence failure rolls back and returns a result', () async {
    store.soundError = StateError('disk full');

    final result = await service.setSoundEffectsEnabled(false);

    expect(result.status, GameFeedbackPreferenceUpdateStatus.failed);
    expect(result.preference, GameFeedbackPreference.soundEffects);
    expect(result.requestedValue, isFalse);
    expect(result.effectiveValue, isTrue);
    expect(result.error, isA<StateError>());
    expect(service.soundEffectsEnabled, isTrue);
    expect(store.soundWrites, [false]);
    expect(store.vibrationWrites, isEmpty);
  });

  test('older failed sound write cannot roll back a newer value', () async {
    await service.initialize();
    final olderWriteGate = Completer<void>();
    store.soundWriteGates.add(olderWriteGate);
    store.soundWriteErrors[0] = StateError('first write failed');

    final olderRequest = service.setSoundEffectsEnabled(false);
    await Future<void>.delayed(Duration.zero);
    expect(store.soundWrites, [false]);
    expect(service.soundEffectsEnabled, isFalse);

    final newerRequest = service.setSoundEffectsEnabled(true);
    await Future<void>.delayed(Duration.zero);
    expect(store.soundWrites, [
      false,
    ], reason: 'same-channel persistence remains serialized');
    expect(service.soundEffectsEnabled, isTrue);

    olderWriteGate.complete();
    final olderResult = await olderRequest;
    final newerResult = await newerRequest;

    expect(olderResult.status, GameFeedbackPreferenceUpdateStatus.failed);
    expect(olderResult.effectiveValue, isTrue);
    expect(newerResult.status, GameFeedbackPreferenceUpdateStatus.saved);
    expect(newerResult.effectiveValue, isTrue);
    expect(store.soundWrites, [false, true]);
    expect(store.value.soundEffectsEnabled, isTrue);
    expect(service.soundEffectsEnabled, isTrue);
  });

  test('vibration is persisted independently and reports success', () async {
    final result = await service.setVibrationEnabled(false);

    expect(result.status, GameFeedbackPreferenceUpdateStatus.saved);
    expect(result.succeeded, isTrue);
    expect(service.vibrationEnabled, isFalse);
    expect(store.vibrationWrites, [false]);
    expect(store.soundWrites, isEmpty);
  });

  test('unchanged preference avoids a storage write', () async {
    final result = await service.setSoundEffectsEnabled(true);

    expect(result.status, GameFeedbackPreferenceUpdateStatus.unchanged);
    expect(result.succeeded, isTrue);
    expect(store.soundWrites, isEmpty);
  });
}

class _MemoryPreferencesStore implements GameFeedbackPreferencesStore {
  _MemoryPreferencesStore([this.value = GameFeedbackPreferences.defaults]);

  GameFeedbackPreferences value;
  Completer<void>? loadGate;
  Object? loadError;
  Object? soundError;
  Object? vibrationError;
  final List<Completer<void>> soundWriteGates = [];
  final Map<int, Object> soundWriteErrors = {};
  int loadCount = 0;
  final List<bool> soundWrites = [];
  final List<bool> vibrationWrites = [];

  @override
  Future<GameFeedbackPreferences> load() async {
    loadCount += 1;
    await loadGate?.future;
    if (loadError case final error?) throw error;
    return value;
  }

  @override
  Future<void> setSoundEffectsEnabled(bool enabled) async {
    final writeIndex = soundWrites.length;
    soundWrites.add(enabled);
    if (writeIndex < soundWriteGates.length) {
      await soundWriteGates[writeIndex].future;
    }
    if (soundWriteErrors[writeIndex] case final error?) throw error;
    if (soundError case final error?) throw error;
    value = value.copyWith(soundEffectsEnabled: enabled);
  }

  @override
  Future<void> setVibrationEnabled(bool enabled) async {
    vibrationWrites.add(enabled);
    if (vibrationError case final error?) throw error;
    value = value.copyWith(vibrationEnabled: enabled);
  }
}

class _FakeAudioBackend implements GameFeedbackAudioBackend {
  int initializeCount = 0;
  int disposeCount = 0;
  int stopAllCount = 0;
  Object? initializeError;
  Object? playError;
  bool playResult = true;
  Completer<void>? initializeGate;
  Completer<void>? playGate;
  final List<GameFeedbackCue> played = [];
  final List<Duration> startWindows = [];

  @override
  Future<void> initialize() async {
    initializeCount += 1;
    await initializeGate?.future;
    if (initializeError case final error?) throw error;
  }

  @override
  Future<bool> playExclusive(
    GameFeedbackCue cue, {
    Duration startWithin = const Duration(milliseconds: 300),
  }) async {
    if (playError case final error?) throw error;
    played.add(cue);
    startWindows.add(startWithin);
    await playGate?.future;
    return playResult;
  }

  @override
  Future<void> stopAll() async {
    stopAllCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}
