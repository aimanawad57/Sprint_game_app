import 'package:flutter/material.dart';

import '../models/game/game_card.dart';
import '../models/game/game_move.dart';
import '../models/game/game_state_view.dart';

typedef MoveSubmitCallback = void Function(String cardId, GamePileId pileId);

class GameStatePanel extends StatefulWidget {
  const GameStatePanel({
    super.key,
    required this.gameState,
    required this.onSubmitMove,
    required this.onBack,
    this.isSubmitting = false,
    this.feedbackMessage,
    this.movesEnabled = true,
    this.connectionMessage,
  });

  final GameStateView gameState;
  final MoveSubmitCallback onSubmitMove;
  final VoidCallback onBack;
  final bool isSubmitting;
  final String? feedbackMessage;
  final bool movesEnabled;
  final String? connectionMessage;

  @override
  State<GameStatePanel> createState() => _GameStatePanelState();
}

class _GameStatePanelState extends State<GameStatePanel> {
  String? _selectedCardId;

  bool get _canPlay {
    return widget.gameState.status == GameMatchStatus.active &&
        !widget.isSubmitting &&
        widget.movesEnabled;
  }

  @override
  void didUpdateWidget(covariant GameStatePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedCardStillExists = widget.gameState.myHand.any(
      (card) => card.cardId == _selectedCardId,
    );
    if (!selectedCardStillExists ||
        oldWidget.gameState.stateVersion != widget.gameState.stateVersion) {
      _selectedCardId = null;
    }
  }

  void _selectCard(String cardId) {
    if (!_canPlay) return;
    setState(() {
      _selectedCardId = _selectedCardId == cardId ? null : cardId;
    });
  }

  void _submitToPile(GamePileId pileId) {
    final selectedCardId = _selectedCardId;
    if (!_canPlay || selectedCardId == null) return;
    widget.onSubmitMove(selectedCardId, pileId);
  }

  @override
  Widget build(BuildContext context) {
    final gameState = widget.gameState;
    final gameFinished = gameState.status == GameMatchStatus.finished;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          gameFinished ? 'Game finished' : 'Game ready',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        _InfoRow(label: 'Status', value: gameState.status.name),
        _InfoRow(
          label: 'State version',
          value: gameState.stateVersion.toString(),
        ),
        if (widget.connectionMessage case final message?) ...[
          const SizedBox(height: 8),
          _ConnectionPanel(message: message),
        ],
        if (widget.feedbackMessage case final feedback?) ...[
          const SizedBox(height: 8),
          _FeedbackPanel(message: feedback),
        ],
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
        const SizedBox(height: 4),
        Text(
          !widget.movesEnabled
              ? 'Moves are paused until both players are connected.'
              : _selectedCardId == null
              ? 'Select one of your cards, then select a center pile.'
              : 'Now select the center pile where you want to play it.',
        ),
        const SizedBox(height: 12),
        _CardTile(
          label: 'Pile 1',
          card: gameState.pile1.topCard,
          onTap: _canPlay && _selectedCardId != null
              ? () => _submitToPile(GamePileId.pile1)
              : null,
        ),
        _CardTile(
          label: 'Pile 2',
          card: gameState.pile2.topCard,
          onTap: _canPlay && _selectedCardId != null
              ? () => _submitToPile(GamePileId.pile2)
              : null,
        ),
        const Divider(height: 32),
        Text('Your cards', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _InfoRow(label: 'Deck count', value: gameState.myDeckCount.toString()),
        for (var index = 0; index < gameState.myHand.length; index++)
          _CardTile(
            key: ValueKey(gameState.myHand[index].cardId),
            label: 'Card ${index + 1}',
            card: gameState.myHand[index],
            selected: gameState.myHand[index].cardId == _selectedCardId,
            onTap: _canPlay
                ? () => _selectCard(gameState.myHand[index].cardId)
                : null,
          ),
        if (widget.isSubmitting) ...[
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Waiting for the server...'),
            ],
          ),
        ],
        if (gameState.winnerId case final winnerId?) ...[
          const Divider(height: 32),
          _InfoRow(label: 'Winner', value: winnerId),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
        ),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    super.key,
    required this.label,
    required this.card,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final GameCard card;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        title: Text(label),
        subtitle: Text(
          '${card.color.name} • ${card.shape.name} • ${card.count}',
        ),
        trailing: selected ? const Icon(Icons.check_circle) : null,
        onTap: onTap,
      ),
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  const _FeedbackPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
      ),
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.wifi_off, color: colors.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onSecondaryContainer),
              ),
            ),
          ],
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
