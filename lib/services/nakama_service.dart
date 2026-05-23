import 'dart:convert';

import 'package:nakama/nakama.dart' as nakama;

import '../config/nakama_config.dart';
import '../models/player_profile.dart';

class NakamaService {
  NakamaService()
    : client = nakama.getNakamaClient(
        host: nakamaHost,
        grpcPort: nakamaGrpcPort,
        serverKey: nakamaServerKey,
        ssl: nakamaUseSsl,
      );

  final nakama.NakamaBaseClient client;
  nakama.NakamaWebsocketClient? _socket;

  Future<nakama.Session> authenticateWithGoogle(String idToken) {
    return client.authenticateGoogle(token: idToken);
  }

  Future<void> updateDisplayName({
    required nakama.Session session,
    required String displayName,
  }) {
    return client.updateAccount(session: session, displayName: displayName);
  }

  Future<void> checkBackend(nakama.Session session) async {
    await client.rpc(session: session, id: 'healthcheck', payload: '');
  }

  nakama.NakamaWebsocketClient realtimeSocket(nakama.Session session) {
    // A websocket is the realtime connection Nakama uses for matchmaking,
    // match messages, presence, and other live game features.
    return _socket ??= nakama.NakamaWebsocketClient.init(
      key: 'sprint-realtime',
      host: nakamaHost,
      port: nakamaHttpPort,
      ssl: nakamaUseSsl,
      token: session.token,
    );
  }

  Future<nakama.MatchmakerTicket> joinQuickplayQueue(
    nakama.NakamaWebsocketClient socket,
  ) {
    return socket.addMatchmaker(
      minCount: 2,
      maxCount: 2,
      query: sprintMatchmakerQuery,
      stringProperties: const {'mode': sprintMatchmakerMode},
    );
  }

  Future<void> leaveQuickplayQueue({
    required nakama.NakamaWebsocketClient socket,
    required String ticket,
  }) {
    return socket.removeMatchmaker(ticket);
  }

  Future<nakama.Match> joinAuthoritativeMatch({
    required nakama.NakamaWebsocketClient socket,
    required String matchId,
  }) {
    return socket.joinMatch(matchId);
  }

  Future<void> leaveAuthoritativeMatch({
    required nakama.NakamaWebsocketClient socket,
    required String matchId,
  }) {
    return socket.leaveMatch(matchId);
  }

  Future<void> closeRealtimeSocket() async {
    final socket = _socket;
    _socket = null;

    await socket?.close();
  }

  Future<PlayerProfile> loadOrCreatePlayerProfile(
    nakama.Session session,
  ) async {
    final objects = await client.readStorageObjects(
      session: session,
      objectIds: const [
        nakama.StorageObjectId(
          collection: playerProfileCollection,
          key: playerProfileKey,
        ),
      ],
    );

    if (objects.isNotEmpty) {
      final json = jsonDecode(objects.first.value) as Map<String, dynamic>;
      return PlayerProfile.fromJson(json);
    }

    final profile = PlayerProfile.createDefault();

    await client.writeStorageObjects(
      session: session,
      objects: [
        nakama.StorageObjectWrite(
          collection: playerProfileCollection,
          key: playerProfileKey,
          value: jsonEncode(profile.toJson()),
          permissionRead: nakama.StorageReadPermission.ownerRead,
          permissionWrite: nakama.StorageWritePermission.ownerWrite,
        ),
      ],
    );

    return profile;
  }
}
