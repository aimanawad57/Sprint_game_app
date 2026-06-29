import 'dart:convert';

import '../models/game/game_state_view.dart';

class GameMessageDecoder {
  const GameMessageDecoder();

  GameStateView decodeGameState(List<int>? data) {
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
      return GameStateView.fromJson(Map<String, dynamic>.from(decoded));
    } on TypeError {
      throw const FormatException('Match message JSON must have string keys');
    }
  }
}
