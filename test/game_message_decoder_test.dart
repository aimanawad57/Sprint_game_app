import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game/rematch_status.dart';
import 'package:sprint_app/services/game_message_decoder.dart';

void main() {
  const decoder = GameMessageDecoder();

  Map<String, dynamic> validState() {
    Map<String, dynamic> card(String id) {
      return {'card_id': id, 'color': 'red', 'shape': 'star', 'count': 1};
    }

    return {
      'stateVersion': 1,
      'status': 'active',
      'elapsedTimeMs': 0,
      'myHand': [card('card_001')],
      'myDeckCount': 26,
      'opponentHandCount': 3,
      'opponentDeckCount': 26,
      'centerPiles': {
        'pile_1': {'topCard': card('card_061')},
        'pile_2': {'topCard': card('card_060')},
      },
      'winnerId': null,
      'winnerName': null,
      'endReason': null,
    };
  }

  test('decodes valid UTF-8 JSON bytes into a game state', () {
    final state = decoder.decodeGameState(
      utf8.encode(jsonEncode(validState())),
    );
    expect(state.stateVersion, 1);
    expect(state.myHand.single.cardId, 'card_001');
  });

  test('rejects missing data', () {
    expect(() => decoder.decodeGameState(null), throwsFormatException);
  });

  test('rejects malformed UTF-8', () {
    expect(
      () => decoder.decodeGameState(const [0xC3, 0x28]),
      throwsFormatException,
    );
  });

  test('rejects malformed JSON', () {
    expect(
      () => decoder.decodeGameState(utf8.encode('{not json}')),
      throwsFormatException,
    );
  });

  test('rejects a non-object JSON root', () {
    expect(
      () => decoder.decodeGameState(utf8.encode('[1, 2, 3]')),
      throwsFormatException,
    );
  });

  test('rejects structurally invalid game state JSON', () {
    expect(
      () => decoder.decodeGameState(utf8.encode('{"status":"active"}')),
      throwsFormatException,
    );
  });

  test('decodes a move rejection', () {
    final rejection = decoder.decodeMoveRejected(
      utf8.encode(
        jsonEncode({
          'stateVersion': 2,
          'reason': 'card_does_not_match',
          'card_id': 'card_001',
          'targetPileId': 'pile_1',
        }),
      ),
    );

    expect(rejection.stateVersion, 2);
    expect(rejection.reason.wireValue, 'card_does_not_match');
    expect(rejection.cardId, 'card_001');
  });

  test('rejects an unknown move rejection reason', () {
    expect(
      () => decoder.decodeMoveRejected(
        utf8.encode(jsonEncode({'stateVersion': 2, 'reason': 'not_supported'})),
      ),
      throwsFormatException,
    );
  });

  test('decodes a connection change', () {
    final connection = decoder.decodeConnectionChanged(
      utf8.encode(
        jsonEncode({
          'changes': [
            {'userId': 'player-b', 'status': 'disconnected'},
          ],
          'connectedUserIds': ['player-a'],
          'connectedCount': 1,
          'expectedCount': 2,
          'disconnectDeadlineMs': 130000,
          'serverTimeMs': 100000,
          'disconnectGraceMs': 30000,
        }),
      ),
    );

    expect(connection.allPlayersConnected, isFalse);
    expect(connection.isUserConnected('player-a'), isTrue);
    expect(connection.isUserConnected('player-b'), isFalse);
    expect(connection.changes.single.userId, 'player-b');
    expect(connection.disconnectDeadlineMs, 130000);
    expect(connection.serverTimeMs, 100000);
    expect(connection.disconnectGraceMs, 30000);
  });

  test('ignores malformed optional connection feedback fields', () {
    final connection = decoder.decodeConnectionChanged(
      utf8.encode(
        jsonEncode({
          'changes': <Object>[],
          'connectedUserIds': ['player-a', 'player-b'],
          'connectedCount': 2,
          'expectedCount': 2,
          'disconnectDeadlineMs': -1,
          'serverTimeMs': 'later',
          'disconnectGraceMs': false,
        }),
      ),
    );

    expect(connection.allPlayersConnected, isTrue);
    expect(connection.disconnectDeadlineMs, isNull);
    expect(connection.serverTimeMs, isNull);
    expect(connection.disconnectGraceMs, isNull);
  });

  test('rejects inconsistent connection counts', () {
    expect(
      () => decoder.decodeConnectionChanged(
        utf8.encode(
          jsonEncode({
            'changes': <Object>[],
            'connectedUserIds': ['player-a'],
            'connectedCount': 2,
            'expectedCount': 2,
          }),
        ),
      ),
      throwsFormatException,
    );
  });

  test('decodes requested and starting rematch statuses', () {
    final requested = decoder.decodeRematchStatus(
      utf8.encode(
        jsonEncode({
          'status': 'requested',
          'requestedBy': 'player-a',
          'expiresInMs': 30000,
        }),
      ),
    );
    expect(requested.status, GameRematchStatus.requested);
    expect(requested.requestedBy, 'player-a');
    expect(requested.expiresInMs, 30000);

    final starting = decoder.decodeRematchStatus(
      utf8.encode(
        jsonEncode({
          'status': 'starting',
          'roundNumber': 2,
          'startsInMs': 5000,
          'startsAtMs': 105000,
          'serverTimeMs': 100000,
        }),
      ),
    );
    expect(starting.status, GameRematchStatus.starting);
    expect(starting.roundNumber, 2);
    expect(starting.startsInMs, 5000);
    expect(starting.startsAtMs, 105000);
    expect(starting.serverTimeMs, 100000);

    final preparing = decoder.decodeRematchStatus(
      utf8.encode(jsonEncode({'status': 'preparing', 'roundNumber': 2})),
    );
    expect(preparing.status, GameRematchStatus.preparing);
    expect(preparing.roundNumber, 2);
  });

  test('rejects malformed rematch status payloads', () {
    expect(
      () => decoder.decodeRematchStatus(
        utf8.encode(jsonEncode({'status': 'unknown'})),
      ),
      throwsFormatException,
    );
    expect(
      () => decoder.decodeRematchStatus(
        utf8.encode(jsonEncode({'status': 'starting', 'roundNumber': 2})),
      ),
      throwsFormatException,
    );
  });
}
