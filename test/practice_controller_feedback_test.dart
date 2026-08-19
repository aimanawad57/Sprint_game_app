import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/gameplay/game_rules.dart';
import 'package:sprint_app/models/game/game_move.dart';
import 'package:sprint_app/models/game/game_state_transition.dart';
import 'package:sprint_app/practice/practice_controller.dart';

void main() {
  test(
    'confirmed player move emits an animation-ready self transition',
    () async {
      final controller = PracticeController(random: Random(7));
      addTearDown(controller.dispose);
      final eventFuture = controller.events.firstWhere(
        (event) => event.type == PracticeEventType.cardPlayed,
      );
      final state = controller.state;
      final playable = state.myHand
          .map(
            (card) => (
              card,
              legalTargets(card, state.pile1.topCard, state.pile2.topCard),
            ),
          )
          .firstWhere((candidate) => candidate.$2.isNotEmpty);
      final target = playable.$2.first;

      expect(controller.play(playable.$1.cardId, target), isTrue);
      final event = await eventFuture;

      expect(event.transition, isNotNull);
      expect(event.transition!.actor, GameStateTransitionActor.self);
      expect(event.transition!.card, same(playable.$1));
      expect(event.transition!.targetPileId, target);
      expect(target, anyOf(GamePileId.pile1, GamePileId.pile2));
    },
  );

  test('bot move emits an animation-ready opponent transition', () async {
    final controllers = <PracticeController>[
      for (var seed = 0; seed < 16; seed++)
        PracticeController(
          random: Random(seed),
          botThinkDelay: const Duration(milliseconds: 1),
        ),
    ];
    late final PracticeEvent event;
    try {
      event = await Future.any([
        for (final controller in controllers)
          controller.events.firstWhere(
            (event) =>
                event.type == PracticeEventType.cardPlayed &&
                event.transition?.actor == GameStateTransitionActor.opponent,
          ),
      ]).timeout(const Duration(seconds: 1));
    } finally {
      for (final controller in controllers) {
        controller.dispose();
      }
    }

    expect(event.transition, isNotNull);
    expect(event.transition!.type, GameStateTransitionType.cardPlayed);
    expect(
      event.transition!.targetPileId,
      anyOf(GamePileId.pile1, GamePileId.pile2),
    );
  });
}
