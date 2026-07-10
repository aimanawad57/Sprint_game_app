import 'package:flutter/material.dart';

import '../models/game/game_card.dart';
import '../models/game/game_move.dart';
import '../models/game/game_state_view.dart';
import 'game_card_shape.dart';

typedef MoveSubmitCallback = void Function(String cardId, GamePileId pileId);

class GameStatePanel extends StatefulWidget {
  const GameStatePanel({
    super.key,
    required this.gameState,
    required this.currentUserId,
    required this.onSubmitMove,
    required this.onBack,
    this.onViewProfile,
    this.isSubmitting = false,
    this.feedbackMessage,
    this.movesEnabled = true,
    this.connectionMessage,
  });

  final GameStateView gameState;
  final String currentUserId;
  final MoveSubmitCallback onSubmitMove;
  final VoidCallback onBack;
  final VoidCallback? onViewProfile;
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
    final resultMessage = _finishedResultMessage(gameState);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          gameFinished ? 'Game finished' : 'Game ready',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        if (gameFinished) ...[
          _GameResultPanel(message: resultMessage),
          const SizedBox(height: 16),
        ],
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
          gameFinished
              ? 'The match has ended. Move controls are disabled.'
              : !widget.movesEnabled
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
        if (gameState.winnerId != null) ...[
          const Divider(height: 32),
          _InfoRow(label: 'Winner', value: _winnerDisplayName(gameState)),
        ],
        const SizedBox(height: 24),
        if (gameFinished && widget.onViewProfile != null) ...[
          FilledButton.icon(
            onPressed: widget.onViewProfile,
            icon: const Icon(Icons.person),
            label: const Text('View profile'),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: widget.onBack,
          icon: Icon(gameFinished ? Icons.home : Icons.arrow_back),
          label: Text(gameFinished ? 'Back to main menu' : 'Back'),
        ),
      ],
    );
  }

  String _finishedResultMessage(GameStateView gameState) {
    final winnerId = gameState.winnerId;
    if (winnerId == null) {
      return 'Match finished';
    }

    if (gameState.endReason == GameMatchEndReason.forfeit) {
      return winnerId == widget.currentUserId
          ? 'Opponent disconnected, You Won!'
          : 'You lost by disconnect timeout.';
    }

    return winnerId == widget.currentUserId ? 'You won' : 'You lost';
  }

  String _winnerDisplayName(GameStateView gameState) {
    final winnerName = gameState.winnerName;
    if (winnerName != null) {
      return winnerName;
    }

    return gameState.winnerId == widget.currentUserId ? 'You' : 'Opponent';
  }
}

class _GameResultPanel extends StatelessWidget {
  const _GameResultPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.emoji_events, color: colors.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
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
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: selected ? colors.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: colors.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    GameCardFace(card: card),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected)
                    Icon(Icons.check_circle, color: colors.primary),
                  Text(
                    '${card.color.name} • ${card.shape.name} • ${card.count}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
