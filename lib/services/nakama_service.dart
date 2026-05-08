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
