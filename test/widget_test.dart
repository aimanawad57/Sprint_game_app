import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/gameplay/game_rules.dart';
import 'package:sprint_app/models/game/game_card.dart';
import 'package:sprint_app/models/game/game_move.dart';
import 'package:sprint_app/models/game/game_state_transition.dart';
import 'package:sprint_app/models/game/game_state_view.dart';
import 'package:sprint_app/models/game/rematch_status.dart';
import 'package:sprint_app/widgets/disconnected_match_banner.dart';
import 'package:sprint_app/widgets/game_state_panel.dart';

Finder _gameScrollable() => find
    .descendant(
      of: find.byKey(const ValueKey('gameStatePanelScroll')),
      matching: find.byType(Scrollable),
    )
    .first;

// scrollUntilVisible tolerates a target that isn't built yet (it blind-drags
// the outer list first), but only positions it approximately. ensureVisible
// requires the element to already exist, but then walks every ancestor
// scrollable (including the nested horizontal hand row) to reveal it
// precisely. Combining both handles cards nested inside the hand row.
Future<void> revealAndSettle(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: _gameScrollable());
  await tester.ensureVisible(finder);
  // A plain pump (not pumpAndSettle) flushes the now-complete scroll
  // animation without waiting on unrelated perpetual animations elsewhere
  // in the tree, e.g. the isSubmitting spinner.
  await tester.pump();
}

void main() {
  GameStateTransition transition({
    required String cardId,
    required GameStateTransitionActor actor,
    required GamePileId pileId,
  }) {
    return GameStateTransition(
      type: GameStateTransitionType.cardPlayed,
      actor: actor,
      card: GameCard(
        cardId: cardId,
        color: GameCardColor.red,
        shape: GameCardShape.star,
        count: 1,
      ),
      targetPileId: pileId,
    );
  }

  GameStateView buildState({
    int stateVersion = 1,
    String? winnerId,
    String? winnerName,
    GameMatchStatus status = GameMatchStatus.active,
    GameMatchEndReason? endReason,
    int elapsedTimeMs = 0,
    List<GameCard>? myHand,
    List<GameStateTransition> transitions = const <GameStateTransition>[],
    int? myRttEstimateMs,
  }) {
    return GameStateView(
      stateVersion: stateVersion,
      status: status,
      elapsedTimeMs: elapsedTimeMs,
      myHand:
          myHand ??
          const [
            GameCard(
              cardId: 'card_001',
              color: GameCardColor.red,
              shape: GameCardShape.star,
              count: 1,
            ),
            GameCard(
              cardId: 'card_002',
              color: GameCardColor.blue,
              shape: GameCardShape.tree,
              count: 2,
            ),
            GameCard(
              cardId: 'card_003',
              color: GameCardColor.green,
              shape: GameCardShape.circle,
              count: 3,
            ),
          ],
      myDeckCount: 26,
      opponentHandCount: 3,
      opponentDeckCount: 26,
      pile1: const CenterPileView(
        topCard: GameCard(
          cardId: 'card_061',
          color: GameCardColor.red,
          shape: GameCardShape.diamond,
          count: 4,
        ),
      ),
      pile2: const CenterPileView(
        topCard: GameCard(
          cardId: 'card_060',
          color: GameCardColor.purple,
          shape: GameCardShape.house,
          count: 5,
        ),
      ),
      winnerId: winnerId,
      winnerName: winnerName,
      endReason: endReason,
      transitions: transitions,
      myRttEstimateMs: myRttEstimateMs,
    );
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    int stateVersion = 1,
    String currentUserId = 'player-a',
    String? winnerId,
    String? winnerName,
    GameMatchStatus status = GameMatchStatus.active,
    GameMatchEndReason? endReason,
    int elapsedTimeMs = 0,
    MoveSubmitCallback? onSubmitMove,
    VoidCallback? onBack,
    VoidCallback? onViewProfile,
    RematchStatusView? rematchStatus,
    RematchDecisionCallback? onRematchDecision,
    bool isRematchSubmitting = false,
    bool isSubmitting = false,
    String? feedbackMessage,
    bool movesEnabled = true,
    String? connectionMessage,
    List<GameCard>? myHand,
    String? pendingCardId,
    List<GameStateTransition> transitions = const <GameStateTransition>[],
    int transitionSequence = 0,
    int transitionRoundSequence = 0,
    int pileResetSequence = 0,
    bool pileResetActive = false,
    int? disconnectDeadlineMs,
    int? connectionServerTimeMs,
    int? myRttEstimateMs,
    int rttSampleSequence = 0,
    VoidCallback? onIllegalMoveFeedback,
    MoveSubmitCallback? onIllegalMoveAttempt,
    VoidCallback? onResultPresentationStarted,
    int? localReconnectRemainingSeconds,
    bool localReconnectExpired = false,
    VoidCallback? onRetryReconnect,
    VoidCallback? onReturnToMenu,
    bool disableAnimations = false,
    bool settleResultPresentation = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: GameStatePanel(
              gameState: buildState(
                stateVersion: stateVersion,
                winnerId: winnerId,
                winnerName: winnerName,
                status: status,
                endReason: endReason,
                elapsedTimeMs: elapsedTimeMs,
                myHand: myHand,
                transitions: transitions,
                myRttEstimateMs: myRttEstimateMs,
              ),
              currentUserId: currentUserId,
              onSubmitMove: onSubmitMove ?? (_, _) {},
              onBack: onBack ?? () {},
              onViewProfile: onViewProfile,
              rematchStatus: rematchStatus,
              onRematchDecision: onRematchDecision,
              isRematchSubmitting: isRematchSubmitting,
              isSubmitting: isSubmitting,
              feedbackMessage: feedbackMessage,
              movesEnabled: movesEnabled,
              connectionMessage: connectionMessage,
              pendingCardId: pendingCardId,
              transitions: transitions,
              transitionSequence: transitionSequence,
              transitionRoundSequence: transitionRoundSequence,
              pileResetSequence: pileResetSequence,
              pileResetActive: pileResetActive,
              disconnectDeadlineMs: disconnectDeadlineMs,
              connectionServerTimeMs: connectionServerTimeMs,
              myRttEstimateMs: myRttEstimateMs,
              rttSampleSequence: rttSampleSequence,
              onIllegalMoveFeedback: onIllegalMoveFeedback,
              onIllegalMoveAttempt: onIllegalMoveAttempt,
              onResultPresentationStarted: onResultPresentationStarted,
              localReconnectRemainingSeconds: localReconnectRemainingSeconds,
              localReconnectExpired: localReconnectExpired,
              onRetryReconnect: onRetryReconnect,
              onReturnToMenu: onReturnToMenu,
            ),
          ),
        ),
      ),
    );
    if (status == GameMatchStatus.finished && settleResultPresentation) {
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pump();
    }
  }

  testWidgets('displays public state and the private hand', (tester) async {
    await pumpPanel(tester);

    expect(find.text('Game Ongoing'), findsOneWidget);
    expect(find.text('State version'), findsNothing);

    final opponentDeck = find.byKey(const ValueKey('opponentDeck'));
    await revealAndSettle(tester, opponentDeck);
    expect(opponentDeck, findsOneWidget);
    expect(find.byKey(const ValueKey('opponentHand')), findsOneWidget);

    final pile1 = find.byKey(const ValueKey('centerPile1'));
    await revealAndSettle(tester, pile1);
    expect(pile1, findsOneWidget);
    expect(find.byKey(const ValueKey('centerPile2')), findsOneWidget);

    for (final cardId in <String>['card_001', 'card_002', 'card_003']) {
      final card = find.byKey(ValueKey(cardId));
      await revealAndSettle(tester, card);
      expect(card, findsOneWidget);
    }

    final myDeck = find.byKey(const ValueKey('myDeck'));
    await revealAndSettle(tester, myDeck);
    expect(myDeck, findsOneWidget);
    expect(find.text('Winner'), findsNothing);
  });

  testWidgets('advances the active match time from the server anchor', (
    tester,
  ) async {
    await pumpPanel(tester, elapsedTimeMs: 37250);
    expect(find.text('37 s'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('38 s'), findsOneWidget);
  });

  testWidgets('does not regress time on an ordinary state update', (
    tester,
  ) async {
    await pumpPanel(tester, elapsedTimeMs: 5000);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('6 s'), findsOneWidget);

    await pumpPanel(tester, elapsedTimeMs: 5500);
    expect(find.text('6 s'), findsOneWidget);
  });

  testWidgets('uses a newer authoritative time after the panel is recreated', (
    tester,
  ) async {
    await pumpPanel(tester, elapsedTimeMs: 2000);
    expect(find.text('2 s'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpPanel(tester, elapsedTimeMs: 9400);
    expect(find.text('9 s'), findsOneWidget);
  });

  testWidgets('freezes at the authoritative finished duration', (tester) async {
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      elapsedTimeMs: 42750,
    );
    expect(find.text('42 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('42 s'), findsOneWidget);
  });

  testWidgets('cancels the active ticker when the panel is disposed', (
    tester,
  ) async {
    await pumpPanel(tester, elapsedTimeMs: 1000);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
  });

  testWidgets('displays the winner username instead of the raw winner id', (
    tester,
  ) async {
    await pumpPanel(tester, winnerId: 'player-a', winnerName: 'Alice');
    await revealAndSettle(tester, find.text('Alice'));

    expect(find.text('Winner'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('player-a'), findsNothing);
  });

  testWidgets('shows a winning result when the current user wins', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      winnerId: 'player-a',
      winnerName: 'Alice',
      currentUserId: 'player-a',
    );

    expect(find.text('Game finished'), findsOneWidget);
    expect(find.text('You won'), findsOneWidget);
    final endedMessage = find.text(
      'The match has ended. Move controls are disabled.',
    );
    await revealAndSettle(tester, endedMessage);
    expect(endedMessage, findsOneWidget);
    await revealAndSettle(tester, find.text('Back to main menu'));
    expect(find.text('Back to main menu'), findsOneWidget);
  });

  testWidgets('invokes the view profile callback after the game finishes', (
    tester,
  ) async {
    var pressed = false;
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      winnerId: 'player-a',
      winnerName: 'Alice',
      onViewProfile: () => pressed = true,
    );

    final viewProfile = find.text('View profile');
    await revealAndSettle(tester, viewProfile);
    await tester.tap(viewProfile);

    expect(pressed, isTrue);
  });

  testWidgets('rematch button sends acceptance after a finished round', (
    tester,
  ) async {
    bool? decision;
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      winnerId: 'player-a',
      endReason: GameMatchEndReason.normal,
      onRematchDecision: (accept) => decision = accept,
    );

    final rematch = find.byKey(const ValueKey('acceptRematchButton'));
    await revealAndSettle(tester, rematch);
    await tester.tap(rematch);
    expect(decision, isTrue);
  });

  testWidgets('opponent rematch request offers accept and decline', (
    tester,
  ) async {
    final decisions = <bool>[];
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      winnerId: 'player-a',
      endReason: GameMatchEndReason.normal,
      rematchStatus: const RematchStatusView(
        status: GameRematchStatus.requested,
        requestedBy: 'player-b',
        expiresInMs: 30000,
      ),
      onRematchDecision: decisions.add,
    );

    expect(find.text('Your opponent wants a rematch.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('acceptRematchButton')));
    expect(decisions, [true]);
  });

  testWidgets('requested, expired, and starting rematch states are clear', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      winnerId: 'player-a',
      endReason: GameMatchEndReason.normal,
      rematchStatus: const RematchStatusView(
        status: GameRematchStatus.requested,
        requestedBy: 'player-a',
      ),
      onRematchDecision: (_) {},
    );
    expect(find.text('Waiting for your opponent…'), findsOneWidget);
    expect(find.byKey(const ValueKey('acceptRematchButton')), findsNothing);

    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      winnerId: 'player-a',
      endReason: GameMatchEndReason.normal,
      rematchStatus: const RematchStatusView(status: GameRematchStatus.expired),
    );
    expect(find.text('The rematch request expired.'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoundCountdownOverlay(durationMs: 5000, roundNumber: 2),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('rematchCountdown')), findsOneWidget);
    final countdownValue = find.byKey(const ValueKey('rematchCountdownValue'));
    expect(countdownValue, findsOneWidget);
    expect(tester.widget<Text>(countdownValue).data, '5');
    expect(find.text('ROUND 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Text>(countdownValue).data, '4');
  });

  testWidgets(
    'first round countdown hides its round label and uses its backdrop',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RoundCountdownOverlay(durationMs: 5000, roundNumber: 1),
          ),
        ),
      );

      expect(find.text('ROUND 1'), findsNothing);
      expect(
        find.byKey(const ValueKey('initialCountdownBackground')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('rematchCountdownValue')),
        findsOneWidget,
      );
      final semantics = tester.getSemantics(
        find.byKey(const ValueKey('initialCountdownBackground')),
      );
      expect(semantics.label, 'Match starts in 5 seconds');
    },
  );

  testWidgets('preparing rematch confirms both players are ready', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      winnerId: 'player-a',
      endReason: GameMatchEndReason.normal,
      rematchStatus: const RematchStatusView(
        status: GameRematchStatus.preparing,
        roundNumber: 2,
      ),
    );

    expect(
      find.text('Both players are ready. Preparing the next round…'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('acceptRematchButton')), findsNothing);
  });

  testWidgets('countdown adopts a resynchronized server deadline', (
    tester,
  ) async {
    Future<void> pumpCountdown({
      required int startsAtMs,
      required int serverTimeMs,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoundCountdownOverlay(
              durationMs: 5000,
              startsAtMs: startsAtMs,
              serverTimeMs: serverTimeMs,
              roundNumber: 1,
            ),
          ),
        ),
      );
    }

    await pumpCountdown(startsAtMs: 105000, serverTimeMs: 100000);
    final value = find.byKey(const ValueKey('rematchCountdownValue'));
    expect(tester.widget<Text>(value).data, '5');

    await pumpCountdown(startsAtMs: 202000, serverTimeMs: 200000);
    expect(tester.widget<Text>(value).data, '2');
  });

  testWidgets('countdown emits every value and GO once', (tester) async {
    final cues = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RoundCountdownOverlay(
          durationMs: 5000,
          roundNumber: 1,
          onCountdownChanged: cues.add,
        ),
      ),
    );
    expect(cues, [5]);

    for (var value = 4; value >= 0; value--) {
      await tester.pump(const Duration(seconds: 1));
      expect(cues.last, value);
    }
    expect(cues, [5, 4, 3, 2, 1, 0]);

    await tester.pump(const Duration(seconds: 2));
    expect(cues, [5, 4, 3, 2, 1, 0], reason: 'GO must not repeat');
  });

  testWidgets('countdown handles skipped ticks and resync without replay', (
    tester,
  ) async {
    final cues = <int>[];
    Future<void> pumpCountdown({
      required int startsAtMs,
      required int serverTimeMs,
      int? networkRttMs,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: RoundCountdownOverlay(
            durationMs: 5000,
            startsAtMs: startsAtMs,
            serverTimeMs: serverTimeMs,
            networkRttMs: networkRttMs,
            roundNumber: 1,
            onCountdownChanged: cues.add,
          ),
        ),
      );
    }

    await pumpCountdown(startsAtMs: 105000, serverTimeMs: 100000);
    await tester.pump(const Duration(seconds: 2));
    expect(cues, [5, 3]);

    await pumpCountdown(startsAtMs: 105000, serverTimeMs: 102000);
    await tester.pump();
    expect(cues, [5, 3], reason: 'a resync must not replay visible cues');

    await tester.pump(const Duration(seconds: 3));
    expect(cues, [5, 3, 0], reason: 'a skipped tick still emits GO once');
    await tester.pump(const Duration(seconds: 1));
    expect(cues, [5, 3, 0]);

    await pumpCountdown(
      startsAtMs: 205000,
      serverTimeMs: 200000,
      networkRttMs: 100000,
    );
    final value = find.byKey(const ValueKey('rematchCountdownValue'));
    expect(
      tester.widget<Text>(value).data,
      '5',
      reason: 'half-RTT compensation is capped at 500ms',
    );
    expect(cues.last, 5, reason: 'a new deadline resets cue deduplication');
  });

  testWidgets('selected cards do not reveal which pile is legal', (
    tester,
  ) async {
    await pumpPanel(tester);
    final handCard = find.byKey(const ValueKey('card_001'));
    await revealAndSettle(tester, handCard);
    await tester.tap(handCard);
    await tester.pump();

    expect(find.byKey(const ValueKey('legalTargetIcon')), findsNothing);
    expect(find.byKey(const ValueKey('illegalTargetIcon')), findsNothing);
    expect(find.text('NO MATCH'), findsNothing);

    final cardSemantics = tester.getSemantics(handCard);
    expect(cardSemantics.label, contains('red, 1 star'));
    expect(cardSemantics.value, 'Selected');
    final pile1Semantics = tester.getSemantics(
      find.byKey(const ValueKey('pile1Semantics')),
    );
    final pile2Semantics = tester.getSemantics(
      find.byKey(const ValueKey('pile2Semantics')),
    );
    expect(pile1Semantics.value, 'Center pile');
    expect(pile2Semantics.value, 'Center pile');
    expect(pile1Semantics.hint, 'Double tap to try the selected card');
    expect(pile2Semantics.hint, pile1Semantics.hint);
    expect(pile1Semantics.hint, isNot(contains(illegalMoveHint)));
  });

  testWidgets('illegal pile taps explain the rule and never submit', (
    tester,
  ) async {
    var submissions = 0;
    var feedbackCues = 0;
    String? rejectedCardId;
    GamePileId? rejectedPileId;
    await pumpPanel(
      tester,
      onSubmitMove: (_, _) => submissions += 1,
      onIllegalMoveFeedback: () => feedbackCues += 1,
      onIllegalMoveAttempt: (cardId, pileId) {
        rejectedCardId = cardId;
        rejectedPileId = pileId;
      },
    );
    final illegalCard = find.byKey(const ValueKey('card_002'));
    await revealAndSettle(tester, illegalCard);
    await tester.tap(illegalCard);
    final pile1 = find.byKey(const ValueKey('centerPile1'));
    await revealAndSettle(tester, pile1);
    await tester.tap(pile1);
    await tester.pump();

    expect(submissions, 0);
    expect(feedbackCues, 1);
    expect(rejectedCardId, 'card_002');
    expect(rejectedPileId, GamePileId.pile1);
    expect(find.byKey(const ValueKey('rejectedTargetIcon')), findsOneWidget);
    expect(find.text(illegalMoveHint), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('pile1Semantics'))).value,
      'Move rejected',
    );
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('moveFeedbackSemantics')),
    );
    expect(semantics.label, illegalMoveHint);
    expect(semantics.flagsCollection.isLiveRegion, isTrue);
  });

  testWidgets(
    'transition batches are measured, serialized, and survive empties',
    (tester) async {
      final first = transition(
        cardId: 'played-1',
        actor: GameStateTransitionActor.opponent,
        pileId: GamePileId.pile1,
      );
      final second = transition(
        cardId: 'played-2',
        actor: GameStateTransitionActor.self,
        pileId: GamePileId.pile2,
      );
      await pumpPanel(tester);
      await pumpPanel(
        tester,
        stateVersion: 2,
        transitions: [first],
        transitionSequence: 11,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        find.byKey(const ValueKey('transitionFlight-0-2-0')),
        findsOneWidget,
      );

      await pumpPanel(
        tester,
        stateVersion: 3,
        transitions: [second],
        transitionSequence: 12,
      );
      await pumpPanel(
        tester,
        stateVersion: 4,
        transitions: const <GameStateTransition>[],
        transitionSequence: 13,
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        find.byKey(const ValueKey('transitionFlight-0-2-0')),
        findsOneWidget,
        reason: 'a newer batch must not interrupt the active flight',
      );

      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        find.byKey(const ValueKey('transitionFlight-0-3-0')),
        findsOneWidget,
        reason: 'an empty snapshot must not erase a queued batch',
      );

      await tester.pump(const Duration(milliseconds: 360));
      await tester.pump();
      await pumpPanel(
        tester,
        stateVersion: 3,
        transitions: [second],
        transitionSequence: 99,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('transitionFlight-0-3-0')),
        findsNothing,
        reason: 'the same round and state version must not replay',
      );

      await pumpPanel(
        tester,
        stateVersion: 3,
        transitions: [second],
        transitionRoundSequence: 1,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        find.byKey(const ValueKey('transitionFlight-1-3-0')),
        findsOneWidget,
        reason: 'the same state version in a new round is a new batch',
      );
    },
  );

  testWidgets('overflowing transition batches compress into a landing pulse', (
    tester,
  ) async {
    await pumpPanel(tester);
    for (var sequence = 1; sequence <= 8; sequence++) {
      await pumpPanel(
        tester,
        stateVersion: sequence + 1,
        transitions: [
          transition(
            cardId: 'queued-$sequence',
            actor: GameStateTransitionActor.opponent,
            pileId: GamePileId.pile1,
          ),
        ],
        transitionSequence: sequence,
      );
    }
    await tester.pump();
    expect(
      find.byKey(const ValueKey('landingPulse-1')),
      findsOneWidget,
      reason: 'a dropped visual batch still confirms its authoritative landing',
    );
  });

  testWidgets('reduced motion replaces card flight with static feedback', (
    tester,
  ) async {
    final move = transition(
      cardId: 'played-reduced',
      actor: GameStateTransitionActor.opponent,
      pileId: GamePileId.pile1,
    );
    await pumpPanel(
      tester,
      transitions: [move],
      transitionSequence: 20,
      disableAnimations: true,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('reducedMotionMoveFeedback')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('transitionFlight-0-1-0')), findsNothing);
    await tester.pump(const Duration(milliseconds: 340));
    expect(
      find.byKey(const ValueKey('reducedMotionMoveFeedback')),
      findsNothing,
    );
  });

  testWidgets('pile reset feedback is nonmodal and does not block a move', (
    tester,
  ) async {
    String? submittedCard;
    await pumpPanel(
      tester,
      pileResetActive: true,
      pileResetSequence: 1,
      onSubmitMove: (cardId, _) => submittedCard = cardId,
    );
    expect(find.byKey(const ValueKey('pileResetPresentation')), findsOneWidget);

    final card = find.byKey(const ValueKey('card_001'));
    await revealAndSettle(tester, card);
    await tester.tap(card);
    final pile = find.byKey(const ValueKey('centerPile1'));
    await revealAndSettle(tester, pile);
    await tester.tap(pile);
    expect(submittedCard, 'card_001');
  });

  testWidgets(
    'result presentation waits for the final move and then unmounts',
    (tester) async {
      var presentationStarts = 0;
      final finalMove = transition(
        cardId: 'winning-card',
        actor: GameStateTransitionActor.self,
        pileId: GamePileId.pile1,
      );
      await pumpPanel(tester);
      await pumpPanel(
        tester,
        stateVersion: 2,
        status: GameMatchStatus.finished,
        winnerId: 'player-a',
        transitions: [finalMove],
        transitionSequence: 30,
        onResultPresentationStarted: () => presentationStarts += 1,
        settleResultPresentation: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('resultPresentation')), findsNothing);
      expect(presentationStarts, 0);

      await tester.pump(const Duration(milliseconds: 170));
      await tester.pump();
      expect(find.byKey(const ValueKey('resultPresentation')), findsOneWidget);
      expect(presentationStarts, 1);
      expect(
        tester
            .widget<AbsorbPointer>(
              find.byKey(const ValueKey('resultPresentationBlocker')),
            )
            .absorbing,
        isTrue,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pump();
      expect(find.byKey(const ValueKey('resultPresentation')), findsNothing);
      expect(presentationStarts, 1);
    },
  );

  testWidgets('initial reduced-motion result reports presentation once', (
    tester,
  ) async {
    var presentationStarts = 0;
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      winnerId: 'player-a',
      disableAnimations: true,
      settleResultPresentation: false,
      onResultPresentationStarted: () => presentationStarts += 1,
    );
    expect(find.byKey(const ValueKey('resultPresentation')), findsOneWidget);
    expect(presentationStarts, 1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(presentationStarts, 1);
  });

  testWidgets('finished state without a winner has a neutral result', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      settleResultPresentation: false,
      disableAnimations: true,
    );
    expect(find.text('MATCH COMPLETE'), findsOneWidget);
    expect(find.text('DEFEAT'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(find.byKey(const ValueKey('resultPresentation')), findsNothing);
  });

  testWidgets('shows a losing result when the opponent wins', (tester) async {
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      winnerId: 'player-b',
      winnerName: 'Bob',
      currentUserId: 'player-a',
    );

    expect(find.text('Game finished'), findsOneWidget);
    expect(find.text('You lost'), findsOneWidget);
    await revealAndSettle(tester, find.text('Bob'));
    expect(find.text('Bob'), findsOneWidget);
    await revealAndSettle(tester, find.text('Back to main menu'));
    expect(find.text('Back to main menu'), findsOneWidget);
  });

  testWidgets('shows a forfeit win message when opponent disconnected', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      winnerId: 'player-a',
      winnerName: 'Alice',
      currentUserId: 'player-a',
      endReason: GameMatchEndReason.forfeit,
    );

    expect(find.text('Opponent disconnected, You Won!'), findsOneWidget);
    expect(find.text('You won'), findsNothing);
    expect(find.byKey(const ValueKey('acceptRematchButton')), findsNothing);
    expect(
      find.text('Play another round with the same opponent?'),
      findsNothing,
    );
  });

  testWidgets('shows a forfeit loss message after disconnect timeout', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      winnerId: 'player-b',
      winnerName: 'Bob',
      currentUserId: 'player-a',
      endReason: GameMatchEndReason.forfeit,
    );

    expect(find.text('You lost by disconnect timeout.'), findsOneWidget);
    expect(find.text('You lost'), findsNothing);
    expect(find.byKey(const ValueKey('acceptRematchButton')), findsNothing);
  });

  testWidgets('invokes the back callback', (tester) async {
    var pressed = false;
    await pumpPanel(tester, onBack: () => pressed = true);
    final back = find.text('Back');
    await revealAndSettle(tester, back);
    await tester.tap(back);

    expect(pressed, isTrue);
  });

  testWidgets('submits the selected card to the selected pile', (tester) async {
    String? submittedCardId;
    GamePileId? submittedPileId;
    await pumpPanel(
      tester,
      onSubmitMove: (cardId, pileId) {
        submittedCardId = cardId;
        submittedPileId = pileId;
      },
    );

    final handCard = find.byKey(const ValueKey('card_001'));
    await revealAndSettle(tester, handCard);
    await tester.tap(handCard);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    final pile = find.byKey(const ValueKey('centerPile1'));
    await revealAndSettle(tester, pile);
    await tester.tap(pile);

    expect(submittedCardId, 'card_001');
    expect(submittedPileId, GamePileId.pile1);
  });

  testWidgets('keeps the selected card across an opponent state update', (
    tester,
  ) async {
    String? submittedCardId;
    await pumpPanel(
      tester,
      stateVersion: 1,
      onSubmitMove: (cardId, _) => submittedCardId = cardId,
    );

    final handCard = find.byKey(const ValueKey('card_001'));
    await revealAndSettle(tester, handCard);
    await tester.tap(handCard);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await pumpPanel(
      tester,
      stateVersion: 2,
      onSubmitMove: (cardId, _) => submittedCardId = cardId,
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    final pile = find.byKey(const ValueKey('centerPile1'));
    await revealAndSettle(tester, pile);
    await tester.tap(pile);
    expect(submittedCardId, 'card_001');
  });

  testWidgets('clears selection when the card leaves the hand', (tester) async {
    await pumpPanel(tester, stateVersion: 1);

    final handCard = find.byKey(const ValueKey('card_001'));
    await revealAndSettle(tester, handCard);
    await tester.tap(handCard);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await pumpPanel(
      tester,
      stateVersion: 2,
      myHand: const [
        GameCard(
          cardId: 'card_002',
          color: GameCardColor.blue,
          shape: GameCardShape.tree,
          count: 2,
        ),
        GameCard(
          cardId: 'card_003',
          color: GameCardColor.green,
          shape: GameCardShape.circle,
          count: 3,
        ),
      ],
    );

    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(
      find.text('Select one of your cards, then select a center pile.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the selected card again deselects it', (tester) async {
    await pumpPanel(tester);

    final handCard = find.byKey(const ValueKey('card_001'));
    await revealAndSettle(tester, handCard);
    await tester.tap(handCard);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(handCard);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('shows pending and rejection feedback', (tester) async {
    await pumpPanel(
      tester,
      isSubmitting: true,
      feedbackMessage: 'That card does not match the center card.',
    );

    expect(
      find.text('That card does not match the center card.'),
      findsOneWidget,
    );
    final waiting = find.text('Waiting for the server...');
    await revealAndSettle(tester, waiting);
    expect(waiting, findsOneWidget);
  });

  testWidgets('does not allow moves after the game finishes', (tester) async {
    var submissionCount = 0;
    await pumpPanel(
      tester,
      status: GameMatchStatus.finished,
      winnerId: 'player-a',
      onSubmitMove: (_, _) => submissionCount++,
    );

    expect(find.text('Game finished'), findsOneWidget);
    final handCard = find.byKey(const ValueKey('card_001'));
    await revealAndSettle(tester, handCard);
    await tester.tap(handCard, warnIfMissed: false);
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(submissionCount, 0);
  });

  testWidgets('shows disconnect status and disables moves', (tester) async {
    var submissionCount = 0;
    await pumpPanel(
      tester,
      movesEnabled: false,
      connectionMessage: 'Opponent disconnected. Waiting for reconnection...',
      onSubmitMove: (_, _) => submissionCount++,
    );

    expect(
      find.text('Opponent disconnected. Waiting for reconnection...'),
      findsOneWidget,
    );
    final pausedMessage = find.text(
      'Moves are paused until both players are connected.',
    );
    await revealAndSettle(tester, pausedMessage);
    expect(pausedMessage, findsOneWidget);

    final handCard = find.byKey(const ValueKey('card_001'));
    await revealAndSettle(tester, handCard);
    expect(handCard, findsOneWidget);
    await tester.tap(handCard);
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(submissionCount, 0);
  });

  testWidgets('opponent reconnect countdown uses RTT and stops at zero', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      movesEnabled: false,
      connectionMessage: 'Opponent disconnected. Waiting for reconnection...',
      disconnectDeadlineMs: 101100,
      connectionServerTimeMs: 100000,
      myRttEstimateMs: 200,
    );
    expect(find.text('1 second until the match is forfeited'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1050));
    expect(find.text('0 seconds until the match is forfeited'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('local reconnect overlay exposes retry and menu recovery', (
    tester,
  ) async {
    var retried = false;
    var returned = false;
    await pumpPanel(
      tester,
      movesEnabled: false,
      localReconnectRemainingSeconds: 7,
    );
    expect(find.text('Reconnecting… 7 s'), findsOneWidget);

    await pumpPanel(
      tester,
      movesEnabled: false,
      localReconnectRemainingSeconds: 0,
      localReconnectExpired: true,
      onRetryReconnect: () => retried = true,
      onReturnToMenu: () => returned = true,
    );
    await tester.tap(find.byKey(const ValueKey('retryReconnectButton')));
    await tester.tap(find.byKey(const ValueKey('returnToMenuButton')));
    expect(retried, isTrue);
    expect(returned, isTrue);
  });

  testWidgets('RTT warning is smoothed, recovers, and expires when stale', (
    tester,
  ) async {
    await pumpPanel(tester, myRttEstimateMs: 250, rttSampleSequence: 1);
    expect(
      find.byKey(const ValueKey('degradedConnectionIndicator')),
      findsNothing,
    );
    await pumpPanel(tester, myRttEstimateMs: 250, rttSampleSequence: 2);
    expect(
      find.byKey(const ValueKey('degradedConnectionIndicator')),
      findsOneWidget,
    );
    expect(find.text('250 ms'), findsOneWidget);
    final degradedSemantics = tester.getSemantics(
      find.byKey(const ValueKey('degradedConnectionIndicator')),
    );
    expect(degradedSemantics.label, contains('250 milliseconds'));

    for (var sequence = 3; sequence <= 6; sequence++) {
      await pumpPanel(
        tester,
        myRttEstimateMs: 100,
        rttSampleSequence: sequence,
      );
    }
    expect(
      find.byKey(const ValueKey('degradedConnectionIndicator')),
      findsNothing,
    );

    await pumpPanel(tester, myRttEstimateMs: 500, rttSampleSequence: 7);
    expect(find.text('Poor'), findsOneWidget);
    expect(find.byKey(const ValueKey('degradedConnectionRtt')), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(
      find.byKey(const ValueKey('degradedConnectionIndicator')),
      findsNothing,
      reason: 'old latency samples must not leave a permanent warning',
    );
  });

  testWidgets('fresh poor RTT bypasses smoothing immediately', (tester) async {
    await pumpPanel(tester, myRttEstimateMs: 90, rttSampleSequence: 1);
    await pumpPanel(tester, myRttEstimateMs: 95, rttSampleSequence: 2);
    await pumpPanel(tester, myRttEstimateMs: 500, rttSampleSequence: 3);
    expect(find.text('Poor'), findsOneWidget);
  });

  testWidgets('header remains compact on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPanel(tester);
    expect(find.text('Game Ongoing'), findsOneWidget);
    expect(find.text('State version'), findsNothing);
    expect(
      find.byKey(const ValueKey('gameFeedbackSettingsButton')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet layout supports normal and reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPanel(tester);
    expect(find.text('Game Ongoing'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpPanel(
      tester,
      transitions: [
        transition(
          cardId: 'tablet-reduced-card',
          actor: GameStateTransitionActor.opponent,
          pileId: GamePileId.pile2,
        ),
      ],
      transitionSequence: 120,
      disableAnimations: true,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('reducedMotionMoveFeedback')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('all presentation controllers can be disposed mid-animation', (
    tester,
  ) async {
    final move = transition(
      cardId: 'dispose-card',
      actor: GameStateTransitionActor.opponent,
      pileId: GamePileId.pile1,
    );
    await pumpPanel(
      tester,
      transitions: [move],
      transitionSequence: 99,
      pileResetActive: true,
      pileResetSequence: 4,
    );
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      const MaterialApp(
        home: RoundCountdownOverlay(durationMs: 5000, roundNumber: 1),
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disconnected match banner shows reconnect and abandon actions', (
    tester,
  ) async {
    var reconnectPressed = false;
    var abandonPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DisconnectedMatchBanner(
            onReconnect: () => reconnectPressed = true,
            onAbandon: () => abandonPressed = true,
            isAbandoning: false,
          ),
        ),
      ),
    );

    expect(find.text('You were disconnected from the match'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Abandon'), findsOneWidget);

    await tester.tap(find.text('Reconnect'));
    await tester.tap(find.text('Abandon'));

    expect(reconnectPressed, isTrue);
    expect(abandonPressed, isTrue);
  });
}
