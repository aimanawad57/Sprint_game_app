import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
      'myHand': [card('card_001')],
      'myDeckCount': 27,
      'opponentHandCount': 3,
      'opponentDeckCount': 27,
      'centerPiles': {
        'pile_1': {'topCard': card('card_061')},
        'pile_2': {'topCard': card('card_062')},
      },
      'winnerId': null,
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
}
