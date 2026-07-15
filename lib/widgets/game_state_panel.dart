import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/game/game_card.dart';
import '../models/game/game_move.dart';
import '../models/game/game_state_view.dart';
import 'game_card_shape.dart';

typedef MoveSubmitCallback = void Function(String cardId, GamePileId pileId);

const _sprintBlue = Color(0xFF2C3192);
const _sprintMuted = Color(0xFF59607F);
const _sprintLavender = Color(0xFFE9E8F6);
const _sprintLavenderDeep = Color(0xFFD7D4EE);
const _sprintYellow = Color(0xFFFFDD2D);
const _sprintOrange = Color(0xFFFFB23F);

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
    if (!selectedCardStillExists) {
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
    final instruction = gameFinished
        ? 'The match has ended. Move controls are disabled.'
        : !widget.movesEnabled
        ? 'Moves are paused until both players are connected.'
        : _selectedCardId == null
        ? 'Select one of your cards, then select a center pile.'
        : 'Now select the center pile where you want to play it.';

    return ColoredBox(
      color: _sprintLavender,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _ArenaPainter())),
          SafeArea(
            child: ListView(
              key: const ValueKey('gameStatePanelScroll'),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              children: [
                _ArenaHeader(
                  title: gameFinished ? 'Game finished' : 'Game Ongoing',
                  status: gameState.status.name,
                  stateVersion: gameState.stateVersion,
                  matchStatus: gameState.status,
                  elapsedTimeMs: gameState.elapsedTimeMs,
                ),
                const SizedBox(height: 14),
                if (gameFinished) ...[
                  _GameResultPanel(message: resultMessage),
                  const SizedBox(height: 12),
                ],
                if (widget.connectionMessage case final message?) ...[
                  _ConnectionPanel(message: message),
                  const SizedBox(height: 10),
                ],
                if (widget.feedbackMessage case final feedback?) ...[
                  _FeedbackPanel(message: feedback),
                  const SizedBox(height: 10),
                ],
                _OpponentLane(
                  handCount: gameState.opponentHandCount,
                  deckCount: gameState.opponentDeckCount,
                ),
                const SizedBox(height: 14),
                _CenterTable(
                  instruction: instruction,
                  selected: _selectedCardId != null,
                  children: [
                    _PileStack(
                      key: const ValueKey('centerPile1'),
                      label: 'Pile 1',
                      topCard: gameState.pile1.topCard,
                      onTap: _canPlay && _selectedCardId != null
                          ? () => _submitToPile(GamePileId.pile1)
                          : null,
                    ),
                    _PileStack(
                      key: const ValueKey('centerPile2'),
                      label: 'Pile 2',
                      topCard: gameState.pile2.topCard,
                      onTap: _canPlay && _selectedCardId != null
                          ? () => _submitToPile(GamePileId.pile2)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _PlayerLane(
                  hand: gameState.myHand,
                  deckCount: gameState.myDeckCount,
                  selectedCardId: _selectedCardId,
                  onSelectCard: _canPlay ? _selectCard : null,
                ),
                if (widget.isSubmitting) ...[
                  const SizedBox(height: 12),
                  const _ServerWaitPanel(),
                ],
                if (gameState.winnerId != null) ...[
                  const SizedBox(height: 14),
                  _InfoPanel(
                    label: 'Winner',
                    value: _winnerDisplayName(gameState),
                  ),
                ],
                const SizedBox(height: 14),
                _BottomActions(
                  gameFinished: gameFinished,
                  onBack: widget.onBack,
                  onViewProfile: widget.onViewProfile,
                ),
              ],
            ),
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

class _ArenaHeader extends StatelessWidget {
  const _ArenaHeader({
    required this.title,
    required this.status,
    required this.stateVersion,
    required this.matchStatus,
    required this.elapsedTimeMs,
  });

  final String title;
  final String status;
  final int stateVersion;
  final GameMatchStatus matchStatus;
  final int elapsedTimeMs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1E2C3192),
            blurRadius: 18,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPRINT GAME',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _sprintBlue,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _sprintBlue,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w900,
                    shadows: const [
                      Shadow(color: _sprintYellow, offset: Offset(3, 3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _StatusChip(label: 'Status', value: status),
          const SizedBox(width: 8),
          _StatusChip(label: 'State version', value: stateVersion.toString()),
          const SizedBox(width: 8),
          _ElapsedTimeChip(status: matchStatus, elapsedTimeMs: elapsedTimeMs),
        ],
      ),
    );
  }
}

class _ElapsedTimeChip extends StatefulWidget {
  const _ElapsedTimeChip({required this.status, required this.elapsedTimeMs});

  final GameMatchStatus status;
  final int elapsedTimeMs;

  @override
  State<_ElapsedTimeChip> createState() => _ElapsedTimeChipState();
}

class _ElapsedTimeChipState extends State<_ElapsedTimeChip>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late int _anchorElapsedMs;
  late int _displayedSeconds;
  Duration _localElapsed = Duration.zero;

  int get _currentElapsedMs => _anchorElapsedMs + _localElapsed.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_handleTick);
    _anchorElapsedMs = widget.elapsedTimeMs;
    _displayedSeconds = _anchorElapsedMs ~/ 1000;
    if (widget.status == GameMatchStatus.active) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant _ElapsedTimeChip oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.status == GameMatchStatus.finished) {
      _ticker.stop();
      _localElapsed = Duration.zero;
      _anchorElapsedMs = widget.elapsedTimeMs;
      _displayedSeconds = _anchorElapsedMs ~/ 1000;
      return;
    }

    if (widget.status == GameMatchStatus.active) {
      final localElapsedMs = _currentElapsedMs;
      if (oldWidget.status != GameMatchStatus.active ||
          widget.elapsedTimeMs > localElapsedMs) {
        _anchorElapsedMs = widget.elapsedTimeMs;
        _localElapsed = Duration.zero;
        _ticker
          ..stop()
          ..start();
        _displayedSeconds = _anchorElapsedMs ~/ 1000;
      } else if (!_ticker.isActive) {
        _ticker.start();
      }
    }
  }

  void _handleTick(Duration elapsed) {
    _localElapsed = elapsed;
    final seconds = _currentElapsedMs ~/ 1000;
    if (seconds != _displayedSeconds) {
      setState(() => _displayedSeconds = seconds);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StatusChip(label: 'Time', value: '$_displayedSeconds s');
  }
}

class _OpponentLane extends StatelessWidget {
  const _OpponentLane({required this.handCount, required this.deckCount});

  final int handCount;
  final int deckCount;

  @override
  Widget build(BuildContext context) {
    return _SceneBand(
      title: 'Opponent',
      trailing: '$handCount cards',
      child: _OpponentArea(handCount: handCount, deckCount: deckCount),
    );
  }
}

class _PlayerLane extends StatelessWidget {
  const _PlayerLane({
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
    return _SceneBand(
      title: 'Your cards',
      trailing: '$deckCount in deck',
      child: _HandRow(
        hand: hand,
        deckCount: deckCount,
        selectedCardId: selectedCardId,
        onSelectCard: onSelectCard,
      ),
    );
  }
}

class _SceneBand extends StatelessWidget {
  const _SceneBand({
    required this.title,
    required this.trailing,
    required this.child,
  });

  final String title;
  final String trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.58)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x142C3192),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _sprintBlue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  trailing,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _sprintMuted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _CenterTable extends StatelessWidget {
  const _CenterTable({
    required this.instruction,
    required this.children,
    required this.selected,
  });

  final String instruction;
  final List<Widget> children;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: BoxDecoration(
        color: _sprintLavenderDeep.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: selected
              ? _sprintYellow.withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.92),
          width: selected ? 3 : 4,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x252C3192),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Center piles',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: _sprintBlue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.touch_app : Icons.bolt,
                color: selected ? _sprintBlue : const Color(0xFF22BFA8),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              instruction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _sprintMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 18),
          CustomPaint(
            painter: _FeltTexturePainter(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameResultPanel extends StatelessWidget {
  const _GameResultPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final won = message.toLowerCase().contains('won');

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: won
              ? const [Color(0xFFFFD166), Color(0xFFFF8A5B)]
              : const [Color(0xFF8FA3B8), Color(0xFF5C6F83)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.emoji_events, color: Color(0xFF111820), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF111820),
                  fontWeight: FontWeight.w900,
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
  const _PileStack({
    super.key,
    required this.label,
    required this.topCard,
    this.onTap,
  });

  final String label;
  final GameCard topCard;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const stackOffset = 4.0;
    final active = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active
              ? _sprintYellow.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? _sprintBlue : _sprintBlue.withValues(alpha: 0.18),
            width: active ? 3 : 1.4,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _sprintBlue,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            SizedBox(
              width: _cardWidth + stackOffset * 1.5,
              height: _cardHeight + stackOffset * 1.5,
              child: Stack(
                children: [
                  const Positioned(
                    left: stackOffset,
                    top: stackOffset,
                    child: _CardBack(),
                  ),
                  Positioned(left: 0, top: 0, child: _CardFront(card: topCard)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const double _handSpacing = 6;
const double _handCardMinWidth = 64;
const double _handCardMaxWidth = 90;

Size _handCardSizeFor(double availableWidth, int itemCount) {
  final safeCount = math.max(itemCount, 1);
  final totalSpacing = _handSpacing * (safeCount - 1);
  final rawWidth = (availableWidth - totalSpacing) / safeCount;
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
        final cardSize = _handCardSizeFor(
          constraints.maxWidth,
          hand.length + 1,
        );
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
              Transform.rotate(
                angle: (index - (handCount - 1) / 2) * 0.045,
                child: _CardBack(
                  width: cardSize.width,
                  height: cardSize.height,
                ),
              ),
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
    return Transform.translate(
      offset: selected ? const Offset(0, -10) : Offset.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          width: width,
          height: height,
          padding: EdgeInsets.all(selected ? 3 : 2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected
                  ? [_sprintYellow, _sprintOrange]
                  : [
                      Colors.white.withValues(alpha: 0.88),
                      _sprintLavenderDeep.withValues(alpha: 0.7),
                    ],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: _sprintYellow.withValues(alpha: 0.48),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: Stack(
            children: [
              _CardFront(card: card, width: width - 6, height: height - 6),
              if (selected)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.check_circle, color: _sprintBlue, size: 18),
                ),
            ],
          ),
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
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 4,
            top: 5,
            child: _CardBack(width: width, height: height),
          ),
          Positioned(
            left: 2,
            top: 2,
            child: _CardBack(width: width, height: height),
          ),
          _CardBack(width: width, height: height),
          Positioned(
            bottom: 7,
            right: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF111820),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Text(
                '$count',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  const _CardFront({
    required this.card,
    this.width = _cardWidth,
    this.height = _cardHeight,
  });

  final GameCard card;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final accent = gameCardColorValue(card.color);

    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF7F8FC)],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withValues(alpha: 0.30), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF6B6D77),
            blurRadius: 0,
            offset: Offset(7, 8),
          ),
          BoxShadow(
            color: Color(0x1A2C3192),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _CardFaceWash(accent))),
          Positioned(
            top: 6,
            left: 7,
            child: _CornerMark(card: card, size: math.max(18, width * 0.23)),
          ),
          Positioned(
            right: 7,
            bottom: 6,
            child: Transform.rotate(
              angle: math.pi,
              child: _CornerMark(card: card, size: math.max(18, width * 0.23)),
            ),
          ),
          Center(
            child: GameCardFace(card: card, maxWidth: width - 18),
          ),
        ],
      ),
    );
  }
}

class _CornerMark extends StatelessWidget {
  const _CornerMark({required this.card, required this.size});

  final GameCard card;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${card.count}',
          style: TextStyle(
            color: gameCardColorValue(card.color),
            fontSize: size * 0.48,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        GameCardShapeIcon(
          shape: card.shape,
          color: gameCardColorValue(card.color),
          size: size * 0.55,
        ),
      ],
    );
  }
}

class _CardFaceWash extends CustomPainter {
  const _CardFaceWash(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final softTint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, 0.08),
        radius: 0.95,
        colors: [
          color.withValues(alpha: 0.075),
          color.withValues(alpha: 0.028),
          Colors.transparent,
        ],
        stops: const [0.0, 0.58, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, softTint);

    final diagonalSheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.04),
          color.withValues(alpha: 0.035),
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, diagonalSheen);

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.085)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final inset = size.shortestSide * 0.16;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          inset,
          inset,
          size.width - inset * 2,
          size.height - inset * 2,
        ),
        const Radius.circular(12),
      ),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CardFaceWash oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({this.width = _cardWidth, this.height = _cardHeight});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.82),
          width: 1.4,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF6B6D77),
            blurRadius: 0,
            offset: Offset(6, 7),
          ),
        ],
      ),
      child: const CustomPaint(painter: _CardBackPainter()),
    );
  }
}

class _CardBackPainter extends CustomPainter {
  const _CardBackPainter();

  static const _baseColor = _sprintBlue;
  static const _stripeColor = _sprintYellow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_baseColor, Color(0xFF24319C), Color(0xFF1E277E)],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    final stripe = Path()
      ..moveTo(size.width * 0.78, -size.height * 0.08)
      ..lineTo(size.width * 0.96, -size.height * 0.08)
      ..lineTo(size.width * 0.22, size.height * 1.08)
      ..lineTo(size.width * 0.04, size.height * 1.08)
      ..close();
    canvas.drawPath(stripe, Paint()..color = _stripeColor);

    final shine = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white.withValues(alpha: 0.14), Colors.transparent],
      ).createShader(rect);
    canvas.drawRect(rect, shine);
  }

  @override
  bool shouldRepaint(covariant _CardBackPainter oldDelegate) => false;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 56),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x252C3192),
            blurRadius: 0,
            offset: Offset(4, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _sprintMuted,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: _sprintBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.68)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _sprintMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _sprintBlue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerWaitPanel extends StatelessWidget {
  const _ServerWaitPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Waiting for the server...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _sprintBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.gameFinished,
    required this.onBack,
    this.onViewProfile,
  });

  final bool gameFinished;
  final VoidCallback onBack;
  final VoidCallback? onViewProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onBack,
            icon: Icon(gameFinished ? Icons.home : Icons.arrow_back),
            label: Text(gameFinished ? 'Back to main menu' : 'Back'),
          ),
        ),
        if (gameFinished && onViewProfile != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: onViewProfile,
              icon: const Icon(Icons.person),
              label: const Text('View profile'),
            ),
          ),
        ],
      ],
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  const _FeedbackPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _AlertPanel(
      icon: Icons.warning_rounded,
      message: message,
      background: const Color(0xFFFFD1D1),
      foreground: const Color(0xFF3F1111),
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _AlertPanel(
      icon: Icons.wifi_off,
      message: message,
      background: const Color(0xFFFFE2A8),
      foreground: const Color(0xFF3A2500),
    );
  }
}

class _AlertPanel extends StatelessWidget {
  const _AlertPanel({
    required this.icon,
    required this.message,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String message;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArenaPainter extends CustomPainter {
  const _ArenaPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE9E8F6), Color(0xFFDCD9F0), Color(0xFFF3F1FA)],
      ).createShader(rect);
    canvas.drawRect(rect, background);

    final framePaint = Paint()..color = _sprintBlue;
    canvas.drawRect(Rect.fromLTWH(0, 0, 10, size.height), framePaint);
    canvas.drawRect(
      Rect.fromLTWH(size.width - 10, 0, 10, size.height),
      framePaint,
    );

    final gridPaint = Paint()
      ..color = _sprintBlue.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    const gap = 34.0;
    for (double x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        gridPaint,
      );
    }
    for (double x = 0; x < size.width + size.height; x += gap) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - size.height, size.height),
        gridPaint,
      );
    }

    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [Colors.white.withValues(alpha: 0.55), Colors.transparent],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.18, size.height * 0.1),
              radius: size.shortestSide * 0.65,
            ),
          );
    canvas.drawRect(rect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _ArenaPainter oldDelegate) => false;
}

class _FeltTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(22)),
      Paint()..color = Colors.white.withValues(alpha: 0.32),
    );

    final linePaint = Paint()
      ..color = _sprintBlue.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (double y = 12; y < size.height; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 18), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FeltTexturePainter oldDelegate) => false;
}
