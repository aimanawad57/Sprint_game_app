import 'dart:async';
import 'dart:convert';

import 'package:nakama/nakama.dart' as nakama;

import '../config/nakama_config.dart';
import '../config/game_protocol.dart';
import '../models/created_match_by_code.dart';
import '../models/game/game_move.dart';
import '../models/leaderboard_entry.dart';
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
  final StreamController<void> _realtimeDisconnectController =
      StreamController<void>.broadcast();

  Stream<void> get realtimeDisconnects => _realtimeDisconnectController.stream;

  Future<nakama.Session> authenticateWithGoogle(String idToken) {
    return client.authenticateGoogle(token: idToken);
  }

  Future<nakama.Session> authenticateAsGuest({required String deviceId}) {
    return client.authenticateDevice(deviceId: deviceId, create: true);
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

  Future<CreatedMatchByCode> createMatchByCode(nakama.Session session) async {
    final response = await client.rpc(
      session: session,
      id: 'create_match_by_code',
      payload: '',
    );
    if (response == null) {
      throw Exception('The server did not return a match code.');
    }
    final json = jsonDecode(response) as Map<String, dynamic>;
    return CreatedMatchByCode(
      code: json['code'] as String,
      matchId: json['matchId'] as String,
    );
  }

  Future<String> joinMatchByCode({
    required nakama.Session session,
    required String code,
  }) async {
    final response = await client.rpc(
      session: session,
      id: 'join_match_by_code',
      payload: jsonEncode({'code': code}),
    );
    if (response == null) {
      throw Exception('The server did not return a match.');
    }
    final json = jsonDecode(response) as Map<String, dynamic>;
    return json['matchId'] as String;
  }

  nakama.NakamaWebsocketClient realtimeSocket(nakama.Session session) {
    // A websocket is the realtime connection Nakama uses for matchmaking,
    // match messages, presence, and other live game features.
    final existingSocket = _socket;
    if (existingSocket != null) {
      return existingSocket;
    }

    late final nakama.NakamaWebsocketClient createdSocket;
    createdSocket = nakama.NakamaWebsocketClient.init(
      key: 'sprint-realtime',
      host: nakamaHost,
      port: nakamaHttpPort,
      ssl: nakamaUseSsl,
      token: session.token,
      onDone: () {
        if (identical(_socket, createdSocket)) {
          _socket = null;
          _realtimeDisconnectController.add(null);
        }
      },
    );
    _socket = createdSocket;
    return createdSocket;
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

  void submitMove({
    required nakama.NakamaWebsocketClient socket,
    required String matchId,
    required SubmitMovePayload move,
  }) {
    socket.sendMatchData(
      matchId: matchId,
      opCode: GameClientOpcode.submitMove,
      data: utf8.encode(jsonEncode(move.toJson())),
    );
  }

  void abandonMatch({
    required nakama.NakamaWebsocketClient socket,
    required String matchId,
  }) {
    socket.sendMatchData(
      matchId: matchId,
      opCode: GameClientOpcode.abandonMatch,
      data: const [],
    );
  }

  Future<void> abandonAuthoritativeMatch({
    required nakama.Session session,
    required String matchId,
  }) async {
    final socket = realtimeSocket(session);
    await joinAuthoritativeMatch(socket: socket, matchId: matchId);
    abandonMatch(socket: socket, matchId: matchId);
  }

  Future<void> closeRealtimeSocket() async {
    final socket = _socket;
    _socket = null;

    await socket?.close();
  }

  Future<PlayerProfile> loadOrCreatePlayerProfile(
    nakama.Session session,
  ) async {
    final response = await client.rpc(
      session: session,
      id: 'get_or_create_profile',
      payload: '',
    );
    if (response == null) {
      throw Exception('The server did not return a player profile.');
    }
    final json = jsonDecode(response) as Map<String, dynamic>;
    return PlayerProfile.fromJson(json);
  }

  Future<List<LeaderboardEntry>> loadWinsLeaderboard(
    nakama.Session session, {
    int limit = 50,
  }) async {
    final response = await client.rpc(
      session: session,
      id: 'get_wins_leaderboard',
      payload: jsonEncode({'limit': limit}),
    );
    if (response == null) {
      throw Exception('The server did not return a leaderboard.');
    }

    final json = jsonDecode(response) as List<dynamic>;
    return json
        .map((entry) => LeaderboardEntry.fromJson(entry as Map<String, dynamic>))
        .toList();
  }
}
