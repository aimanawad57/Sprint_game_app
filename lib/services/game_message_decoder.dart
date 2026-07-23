import 'dart:convert';

import '../models/game/game_connection.dart';
import '../models/game/game_move.dart';
import '../models/game/game_state_view.dart';
import '../models/game/rematch_status.dart';

class GameMessageDecoder {
  const GameMessageDecoder();

  GameStateView decodeGameState(List<int>? data) {
    return GameStateView.fromJson(_decodeJsonObject(data));
  }

  MoveRejectedView decodeMoveRejected(List<int>? data) {
    return MoveRejectedView.fromJson(_decodeJsonObject(data));
  }

  GameConnectionView decodeConnectionChanged(List<int>? data) {
    return GameConnectionView.fromJson(_decodeJsonObject(data));
  }

  RematchStatusView decodeRematchStatus(List<int>? data) {
    return RematchStatusView.fromJson(_decodeJsonObject(data));
  }

  Map<String, dynamic> _decodeJsonObject(List<int>? data) {
    if (data == null) {
      throw const FormatException('Match message data is missing');
    }

    late final String payload;
    try {
      payload = utf8.decode(data, allowMalformed: false);
    } on FormatException catch (error) {
      throw FormatException('Match message is not valid UTF-8: $error');
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException catch (error) {
      throw FormatException('Match message is not valid JSON: $error');
    }

    if (decoded is! Map) {
      throw const FormatException('Match message JSON must be an object');
    }

    try {
      return Map<String, dynamic>.from(decoded);
    } on TypeError {
      throw const FormatException('Match message JSON must have string keys');
    }
  }
}
