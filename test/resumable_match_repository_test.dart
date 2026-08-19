import 'package:flutter_test/flutter_test.dart';
import 'package:nakama/nakama.dart' as nakama;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sprint_app/services/nakama_service.dart';
import 'package:sprint_app/services/resumable_match_repository.dart';
import 'package:sprint_app/services/resumable_match_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared preferences store persists independently per user', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final first = SharedPreferencesResumableMatchStore(userId: 'player-a');
    final second = SharedPreferencesResumableMatchStore(userId: 'player-b');

    await first.save('match-a');
    await second.save('match-b');
    expect(await first.read(), 'match-a');
    expect(await second.read(), 'match-b');

    await first.clear();
    expect(await first.read(), isNull);
    expect(await second.read(), 'match-b');
  });

  test('server match replaces a stale local hint', () async {
    final store = _MemoryStore('old-match');
    final repository = ResumableMatchRepository(
      nakamaService: _NakamaService(result: 'live-match'),
      session: _session(),
      store: store,
    );

    expect(await repository.restore(), 'live-match');
    expect(await store.read(), 'live-match');
  });

  test('authoritative empty result clears stale local data', () async {
    final store = _MemoryStore('gone-match');
    final repository = ResumableMatchRepository(
      nakamaService: _NakamaService(result: null),
      session: _session(),
      store: store,
    );

    expect(await repository.restore(), isNull);
    expect(await store.read(), isNull);
  });

  test('offline startup falls back to the locally persisted match', () async {
    final repository = ResumableMatchRepository(
      nakamaService: _NakamaService(error: Exception('offline')),
      session: _session(),
      store: _MemoryStore('cached-match'),
    );

    expect(await repository.restore(), 'cached-match');
  });

  test('verified server result wins even when local refresh fails', () async {
    final repository = ResumableMatchRepository(
      nakamaService: _NakamaService(result: 'live-match'),
      session: _session(),
      store: _FailingWriteStore('old-match'),
    );

    expect(await repository.restore(), 'live-match');
  });
}

class _MemoryStore implements ResumableMatchStore {
  _MemoryStore(this.value);

  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> save(String matchId) async => value = matchId;
}

class _NakamaService extends NakamaService {
  _NakamaService({this.result, this.error});

  final String? result;
  final Object? error;

  @override
  Future<String?> loadResumableMatch(nakama.Session session) async {
    if (error case final error?) throw error;
    return result;
  }
}

class _FailingWriteStore extends _MemoryStore {
  _FailingWriteStore(super.value);

  @override
  Future<void> save(String matchId) => Future.error(Exception('disk full'));
}

nakama.Session _session() {
  return nakama.Session(
    token: 'test-token',
    refreshToken: 'test-refresh-token',
    created: false,
    vars: const {},
    userId: 'player-a',
    expiresAt: DateTime.utc(2100),
    refreshExpiresAt: DateTime.utc(2100),
  );
}
