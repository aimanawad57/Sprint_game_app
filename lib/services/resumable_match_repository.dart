import 'package:nakama/nakama.dart' as nakama;

import 'nakama_service.dart';
import 'resumable_match_store.dart';

class ResumableMatchRepository {
  ResumableMatchRepository({
    required this.nakamaService,
    required this.session,
    ResumableMatchStore? store,
  }) : store =
           store ??
           SharedPreferencesResumableMatchStore(userId: session.userId);

  final NakamaService nakamaService;
  final nakama.Session session;
  final ResumableMatchStore store;

  /// Reconciles the crash-safe local hint with the authoritative server.
  /// If the server cannot be reached, the local value remains usable.
  Future<String?> restore() async {
    String? localMatchId;
    try {
      localMatchId = await store.read();
    } catch (_) {
      // Local persistence is a recovery aid, never a reason to block the app.
    }

    final String? serverMatchId;
    try {
      serverMatchId = await nakamaService.loadResumableMatch(session);
    } catch (_) {
      return localMatchId;
    }

    if (serverMatchId == null) {
      try {
        await store.clear();
      } catch (_) {
        // The verified server result still wins if local cleanup fails.
      }
      return null;
    }

    try {
      await store.save(serverMatchId);
    } catch (_) {
      // Recovery can proceed from the verified server result even if the
      // local cache cannot be refreshed on this launch.
    }
    return serverMatchId;
  }

  Future<void> save(String matchId) => store.save(matchId);

  Future<void> clear() => store.clear();
}
