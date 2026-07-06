import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game/game_card.dart';
import 'package:sprint_app/models/game/game_move.dart';
import 'package:sprint_app/models/game/game_state_view.dart';
import 'package:sprint_app/widgets/game_state_panel.dart';

void main() {
  GameStateView buildState({
    String? winnerId,
    GameMatchStatus status = GameMatchStatus.active,
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
          shape: GameCardShape.heart,
          count: 2,
        ),
        GameCard(
          cardId: 'card_003',
          color: GameCardColor.green,
          shape: GameCardShape.circle,
          count: 3,
        ),
      ],
      myDeckCount: 27,
      opponentHandCount: 3,
      opponentDeckCount: 27,
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
          cardId: 'card_062',
          color: GameCardColor.purple,
          shape: GameCardShape.spiral,
          count: 5,
        ),
      ),
      winnerId: winnerId,
    );
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    String? winnerId,
    GameMatchStatus status = GameMatchStatus.active,
    MoveSubmitCallback? onSubmitMove,
    VoidCallback? onBack,
    bool isSubmitting = false,
    String? feedbackMessage,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameStatePanel(
            gameState: buildState(winnerId: winnerId, status: status),
            onSubmitMove: onSubmitMove ?? (_, _) {},
            onBack: onBack ?? () {},
            isSubmitting: isSubmitting,
            feedbackMessage: feedbackMessage,
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
      'purple • spiral • 5',
      'red • star • 1',
      'blue • heart • 2',
      'green • circle • 3',
    ]) {
      await tester.scrollUntilVisible(find.text(cardText), 150);
      expect(find.text(cardText), findsOneWidget);
    }

    expect(find.text('Deck count'), findsOneWidget);
    expect(find.text('Winner'), findsNothing);
  });

  testWidgets('displays a winner when supplied', (tester) async {
    await pumpPanel(tester, winnerId: 'player-a');
    await tester.scrollUntilVisible(find.text('player-a'), 200);

    expect(find.text('Winner'), findsOneWidget);
    expect(find.text('player-a'), findsOneWidget);
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
    await tester.scrollUntilVisible(pile, -150);
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
    await tester.tap(handCard);
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(submissionCount, 0);
  });
}
