import 'package:flutter/material.dart';

import '../models/game/game_card.dart';
import '../models/game/game_state_view.dart';

class GameStatePanel extends StatelessWidget {
  const GameStatePanel({
    super.key,
    required this.gameState,
    required this.onBack,
  });

  final GameStateView gameState;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Game ready', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        _InfoRow(label: 'Status', value: gameState.status.name),
        _InfoRow(
          label: 'State version',
          value: gameState.stateVersion.toString(),
        ),
        const Divider(height: 32),
        Text('Opponent', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _InfoRow(
          label: 'Hand count',
          value: gameState.opponentHandCount.toString(),
        ),
        _InfoRow(
          label: 'Deck count',
          value: gameState.opponentDeckCount.toString(),
        ),
        const Divider(height: 32),
        Text('Center piles', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _CardTile(label: 'Pile 1', card: gameState.pile1.topCard),
        _CardTile(label: 'Pile 2', card: gameState.pile2.topCard),
        const Divider(height: 32),
        Text('Your cards', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _InfoRow(label: 'Deck count', value: gameState.myDeckCount.toString()),
        for (var index = 0; index < gameState.myHand.length; index++)
          _CardTile(label: 'Card ${index + 1}', card: gameState.myHand[index]),
        if (gameState.winnerId case final winnerId?) ...[
          const Divider(height: 32),
          _InfoRow(label: 'Winner', value: winnerId),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
        ),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.label, required this.card});

  final String label;
  final GameCard card;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text(
          '${card.color.name} • ${card.shape.name} • ${card.count}',
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
