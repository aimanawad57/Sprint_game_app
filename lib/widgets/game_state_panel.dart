import 'dart:math' as math;

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

    return ColoredBox(
      color: Colors.white,
      child: ListView(
        key: const ValueKey('gameStatePanelScroll'),
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
          _OpponentArea(
            handCount: gameState.opponentHandCount,
            deckCount: gameState.opponentDeckCount,
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
          Center(
            child: _Table(
              children: [
                _PileStack(
                  key: const ValueKey('centerPile1'),
                  topCard: gameState.pile1.topCard,
                  onTap: _canPlay && _selectedCardId != null
                      ? () => _submitToPile(GamePileId.pile1)
                      : null,
                ),
                _PileStack(
                  key: const ValueKey('centerPile2'),
                  topCard: gameState.pile2.topCard,
                  onTap: _canPlay && _selectedCardId != null
                      ? () => _submitToPile(GamePileId.pile2)
                      : null,
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          Text('Your cards', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          _HandRow(
            hand: gameState.myHand,
            deckCount: gameState.myDeckCount,
            selectedCardId: _selectedCardId,
            onSelectCard: _canPlay ? _selectCard : null,
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
      ),
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

const double _cardWidth = 88;
const double _cardHeight = 120;

class _PileStack extends StatelessWidget {
  const _PileStack({super.key, required this.topCard, this.onTap});

  final GameCard topCard;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const stackOffset = 5.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: _cardWidth + stackOffset * 2,
        height: _cardHeight + stackOffset * 2,
        child: Stack(
          children: [
            const Positioned(
              left: stackOffset * 2,
              top: stackOffset * 2,
              child: _CardBack(),
            ),
            const Positioned(
              left: stackOffset,
              top: stackOffset,
              child: _CardBack(),
            ),
            Positioned(left: 0, top: 0, child: _CardFront(card: topCard)),
          ],
        ),
      ),
    );
  }
}

// Hand-row cards (and the deck pile beside them) shrink to fit the
// available width so the whole row — hand + deck — is always visible on
// one line, never requiring a horizontal scroll.
const double _handSpacing = 6;
const double _handCardMinWidth = 64;
const double _handCardMaxWidth = 84;

Size _handCardSizeFor(double availableWidth, int itemCount) {
  final totalSpacing = _handSpacing * (itemCount - 1);
  final rawWidth = (availableWidth - totalSpacing) / itemCount;
  final width = rawWidth.clamp(_handCardMinWidth, _handCardMaxWidth);
  return Size(width, width * _cardHeight / _cardWidth);
}

class _HandRow extends StatelessWidget {
  const _HandRow({
    required this.hand,
    required this.deckCount,
    required this.selectedCardId,
    required this.onSelectCard,
  });

  final List<GameCard> hand;
  final int deckCount;
  final String? selectedCardId;
  final ValueChanged<String>? onSelectCard;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardSize = _handCardSizeFor(constraints.maxWidth, hand.length + 1);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final card in hand) ...[
              _HandCardTile(
                key: ValueKey(card.cardId),
                card: card,
                width: cardSize.width,
                height: cardSize.height,
                selected: card.cardId == selectedCardId,
                onTap: onSelectCard == null
                    ? null
                    : () => onSelectCard!(card.cardId),
              ),
              const SizedBox(width: _handSpacing),
            ],
            _DeckPile(
              key: const ValueKey('myDeck'),
              count: deckCount,
              width: cardSize.width,
              height: cardSize.height,
            ),
          ],
        );
      },
    );
  }
}

class _OpponentArea extends StatelessWidget {
  const _OpponentArea({required this.handCount, required this.deckCount});

  final int handCount;
  final int deckCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardSize = _handCardSizeFor(constraints.maxWidth, handCount + 1);
        return Row(
          key: const ValueKey('opponentHand'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < handCount; index++) ...[
              _CardBack(width: cardSize.width, height: cardSize.height),
              const SizedBox(width: _handSpacing),
            ],
            _DeckPile(
              key: const ValueKey('opponentDeck'),
              count: deckCount,
              width: cardSize.width,
              height: cardSize.height,
            ),
          ],
        );
      },
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF6B4426),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF462C18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: children,
      ),
    );
  }
}

class _HandCardTile extends StatelessWidget {
  const _HandCardTile({
    super.key,
    required this.card,
    this.selected = false,
    this.onTap,
    this.width = _cardWidth,
    this.height = _cardHeight,
  });

  final GameCard card;
  final bool selected;
  final VoidCallback? onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: selected ? colors.primaryContainer : colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(child: GameCardFace(card: card, maxWidth: width - 20)),
            if (selected)
              Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  Icons.check_circle,
                  color: colors.primary,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeckPile extends StatelessWidget {
  const _DeckPile({
    super.key,
    required this.count,
    this.width = _cardWidth,
    this.height = _cardHeight,
  });

  final int count;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          _CardBack(width: width, height: height),
          Positioned(
            bottom: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Text(
                '$count',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  const _CardFront({required this.card});

  final GameCard card;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: _cardWidth,
      height: _cardHeight,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Center(
        child: GameCardFace(card: card, maxWidth: _cardWidth - 20),
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({this.width = _cardWidth, this.height = _cardHeight});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: const CustomPaint(painter: _CardBackPainter()),
    );
  }
}

// A woven card-back cover, drawn as two sets of crossed diagonal stripes,
// so hidden cards read as a real card cover instead of a blank tile.
class _CardBackPainter extends CustomPainter {
  const _CardBackPainter();

  static const _baseColor = Color(0xFF3B6D11);
  static const _stripeColor = Color(0xFF639922);
  static const _stripeWidth = 2.0;
  static const _stripeSpacing = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _baseColor);

    final stripePaint = Paint()
      ..color = _stripeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stripeWidth;

    final span = size.longestSide * 1.5;
    final center = size.center(Offset.zero);

    for (final angle in [math.pi / 3, -math.pi / 3]) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      for (double x = -span; x <= span; x += _stripeSpacing) {
        canvas.drawLine(Offset(x, -span), Offset(x, span), stripePaint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CardBackPainter oldDelegate) => false;
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
