import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game/game_card.dart';
import 'package:sprint_app/models/game/game_move.dart';
import 'package:sprint_app/models/game/game_state_view.dart';
import 'package:sprint_app/widgets/disconnected_match_banner.dart';
import 'package:sprint_app/widgets/game_state_panel.dart';

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
    expect(find.text('Hand count'), findsOneWidget);

    for (final cardText in <String>[
      'orange • diamond • 4',
      'purple • house • 5',
      'red • star • 1',
      'blue • tree • 2',
      'green • circle • 3',
    ]) {
      await tester.scrollUntilVisible(find.text(cardText), 150);
      expect(find.text(cardText), findsOneWidget);
    }

    expect(find.text('Deck count'), findsOneWidget);
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
    await tester.scrollUntilVisible(find.text('Alice'), 200);

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
    expect(
      find.text('The match has ended. Move controls are disabled.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Back to main menu'), 200);
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

    await tester.scrollUntilVisible(find.text('View profile'), 200);
    await tester.tap(find.text('View profile'));

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
    await tester.scrollUntilVisible(find.text('Bob'), 200);
    expect(find.text('Bob'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Back to main menu'), 200);
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
    await tester.scrollUntilVisible(find.text('Back'), 200);
    await tester.tap(find.text('Back'));

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

    final handCard = find.text('red • star • 1');
    await tester.scrollUntilVisible(handCard, 150);
    await tester.tap(handCard);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    final pile = find.text('Pile 1');
    await tester.ensureVisible(pile);
    await tester.pumpAndSettle();
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
    await tester.scrollUntilVisible(
      find.text('Waiting for the server...'),
      150,
    );
    expect(find.text('Waiting for the server...'), findsOneWidget);
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
    final handCard = find.text('red • star • 1');
    await tester.scrollUntilVisible(handCard, 150);
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
    expect(
      find.text('Moves are paused until both players are connected.'),
      findsOneWidget,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    final handCard = find.byKey(const ValueKey('card_001'));
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
