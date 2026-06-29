import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/game/game_card.dart';
import 'package:sprint_app/models/game/game_state_view.dart';
import 'package:sprint_app/widgets/game_state_panel.dart';

void main() {
  GameStateView buildState({String? winnerId}) {
    return GameStateView(
      stateVersion: 1,
      status: GameMatchStatus.active,
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
    VoidCallback? onBack,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameStatePanel(
            gameState: buildState(winnerId: winnerId),
            onBack: onBack ?? () {},
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
}
