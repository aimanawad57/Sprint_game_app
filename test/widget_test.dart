import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game/game_card.dart';
import 'package:sprint_app/models/game/game_move.dart';
import 'package:sprint_app/models/game/game_state_view.dart';
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
  GameStateView buildState({
    String? winnerId,
    String? winnerName,
    GameMatchStatus status = GameMatchStatus.active,
    GameMatchEndReason? endReason,
  }) {
    return GameStateView(
      stateVersion: 1,
      status: status,
      myHand: const [
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
          color: GameCardColor.orange,
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
    );
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    String currentUserId = 'player-a',
    String? winnerId,
    String? winnerName,
    GameMatchStatus status = GameMatchStatus.active,
    GameMatchEndReason? endReason,
    MoveSubmitCallback? onSubmitMove,
    VoidCallback? onBack,
    VoidCallback? onViewProfile,
    bool isSubmitting = false,
    String? feedbackMessage,
    bool movesEnabled = true,
    String? connectionMessage,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameStatePanel(
            gameState: buildState(
              winnerId: winnerId,
              winnerName: winnerName,
              status: status,
              endReason: endReason,
            ),
            currentUserId: currentUserId,
            onSubmitMove: onSubmitMove ?? (_, _) {},
            onBack: onBack ?? () {},
            onViewProfile: onViewProfile,
            isSubmitting: isSubmitting,
            feedbackMessage: feedbackMessage,
            movesEnabled: movesEnabled,
            connectionMessage: connectionMessage,
          ),
        ),
      ),
    );
  }

  testWidgets('displays public state and the private hand', (tester) async {
    await pumpPanel(tester);

    expect(find.text('active'), findsOneWidget);
    expect(find.text('State version'), findsOneWidget);

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

  testWidgets('displays the winner username instead of the raw winner id', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      winnerId: 'player-a',
      winnerName: 'Alice',
    );
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
