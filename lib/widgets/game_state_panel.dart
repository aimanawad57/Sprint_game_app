import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/game/game_card.dart';
import '../models/game/game_move.dart';
import '../models/game/game_state_transition.dart';
import '../models/game/game_state_view.dart';
import '../models/game/rematch_status.dart';
import '../gameplay/game_rules.dart';
import '../utils/elapsed_time_format.dart';
import 'game_card_shape.dart';

typedef MoveSubmitCallback = void Function(String cardId, GamePileId pileId);
typedef RematchDecisionCallback = void Function(bool accept);

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
    this.rematchStatus,
    this.onRematchDecision,
    this.isRematchSubmitting = false,
    this.isSubmitting = false,
    this.feedbackMessage,
    this.movesEnabled = true,
    this.connectionMessage,
    this.pendingCardId,
    this.transitions = const <GameStateTransition>[],
    this.transitionSequence = 0,
    this.transitionRoundSequence = 0,
    this.pileResetSequence = 0,
    this.pileResetActive = false,
    this.disconnectDeadlineMs,
    this.connectionServerTimeMs,
    this.myRttEstimateMs,
    this.rttSampleSequence = 0,
    this.localReconnectRemainingSeconds,
    this.localReconnectExpired = false,
    this.onRetryReconnect,
    this.onReturnToMenu,
    this.onCardSelectedFeedback,
    this.onIllegalMoveFeedback,
    this.onIllegalMoveAttempt,
    this.onResultPresentationStarted,
    this.coachingMessage,
    this.highlightedCardIds = const <String>{},
    this.highlightedPileIds = const <GamePileId>{},
  });

  final GameStateView gameState;
  final String currentUserId;
  final MoveSubmitCallback onSubmitMove;
  final VoidCallback onBack;
  final VoidCallback? onViewProfile;
  final RematchStatusView? rematchStatus;
  final RematchDecisionCallback? onRematchDecision;
  final bool isRematchSubmitting;
  final bool isSubmitting;
  final String? feedbackMessage;
  final bool movesEnabled;
  final String? connectionMessage;
  final String? pendingCardId;
  final List<GameStateTransition> transitions;
  final int transitionSequence;
  final int transitionRoundSequence;
  final int pileResetSequence;
  final bool pileResetActive;
  final int? disconnectDeadlineMs;
  final int? connectionServerTimeMs;
  final int? myRttEstimateMs;
  final int rttSampleSequence;
  final int? localReconnectRemainingSeconds;
  final bool localReconnectExpired;
  final VoidCallback? onRetryReconnect;
  final VoidCallback? onReturnToMenu;
  final VoidCallback? onCardSelectedFeedback;
  final VoidCallback? onIllegalMoveFeedback;
  final MoveSubmitCallback? onIllegalMoveAttempt;
  final VoidCallback? onResultPresentationStarted;
  final String? coachingMessage;
  final Set<String> highlightedCardIds;
  final Set<GamePileId> highlightedPileIds;

  @override
  State<GameStatePanel> createState() => _GameStatePanelState();
}

class _GameStatePanelState extends State<GameStatePanel> {
  final GlobalKey _opponentAnchorKey = GlobalKey(
    debugLabel: 'opponent-flight-anchor',
  );
  final GlobalKey _playerAnchorKey = GlobalKey(
    debugLabel: 'player-flight-anchor',
  );
  final GlobalKey _pile1AnchorKey = GlobalKey(
    debugLabel: 'pile-1-flight-anchor',
  );
  final GlobalKey _pile2AnchorKey = GlobalKey(
    debugLabel: 'pile-2-flight-anchor',
  );
  String? _selectedCardId;
  GamePileId? _illegalPileId;
  String? _localFeedback;
  int _illegalShakeSequence = 0;
  int _pile1LandingSequence = 0;
  int _pile2LandingSequence = 0;
  Timer? _localFeedbackTimer;
  bool _transitionPresentationBusy = false;
  bool _resultPresentationPending = false;
  bool _showResultPresentation = false;

  bool get _canPlay {
    return widget.gameState.status == GameMatchStatus.active &&
        !widget.isSubmitting &&
        widget.movesEnabled;
  }

  @override
  void initState() {
    super.initState();
    final finished = widget.gameState.status == GameMatchStatus.finished;
    _transitionPresentationBusy = widget.transitions.isNotEmpty;
    _resultPresentationPending = finished;
    _showResultPresentation = finished && !_transitionPresentationBusy;
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
    if (oldWidget.gameState.stateVersion != widget.gameState.stateVersion) {
      _illegalPileId = null;
      _localFeedback = null;
      _localFeedbackTimer?.cancel();
    }
    final wasFinished = oldWidget.gameState.status == GameMatchStatus.finished;
    final isFinished = widget.gameState.status == GameMatchStatus.finished;
    if (!wasFinished && isFinished) {
      _resultPresentationPending = true;
      _showResultPresentation = false;
      if (widget.transitions.isNotEmpty) {
        _transitionPresentationBusy = true;
      } else if (!_transitionPresentationBusy) {
        _showResultPresentation = true;
      }
    } else if (wasFinished && !isFinished) {
      _resultPresentationPending = false;
      _showResultPresentation = false;
    }
  }

  @override
  void dispose() {
    _localFeedbackTimer?.cancel();
    super.dispose();
  }

  void _selectCard(String cardId) {
    if (!_canPlay) return;
    widget.onCardSelectedFeedback?.call();
    setState(() {
      _selectedCardId = _selectedCardId == cardId ? null : cardId;
      _illegalPileId = null;
      _localFeedback = null;
    });
  }

  void _submitToPile(GamePileId pileId) {
    final selectedCardId = _selectedCardId;
    if (!_canPlay || selectedCardId == null) return;
    final selectedCard = widget.gameState.myHand
        .where((card) => card.cardId == selectedCardId)
        .firstOrNull;
    if (selectedCard == null) return;
    final pileTop = pileId == GamePileId.pile1
        ? widget.gameState.pile1.topCard
        : widget.gameState.pile2.topCard;
    if (!cardsMatch(selectedCard, pileTop)) {
      _localFeedbackTimer?.cancel();
      widget.onIllegalMoveFeedback?.call();
      setState(() {
        _illegalPileId = pileId;
        _illegalShakeSequence += 1;
        _localFeedback = illegalMoveHint;
      });
      widget.onIllegalMoveAttempt?.call(selectedCardId, pileId);
      _localFeedbackTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() {
          _illegalPileId = null;
          _localFeedback = null;
        });
      });
      return;
    }
    setState(() {
      _illegalPileId = null;
      _localFeedback = null;
    });
    widget.onSubmitMove(selectedCardId, pileId);
  }

  void _handleTransitionBusyChanged(bool busy) {
    if (!mounted || _transitionPresentationBusy == busy) return;
    setState(() {
      _transitionPresentationBusy = busy;
      if (!busy && _resultPresentationPending) {
        _showResultPresentation = true;
      }
    });
  }

  void _handleTransitionLanded(Set<GamePileId> piles) {
    if (!mounted || piles.isEmpty) return;
    setState(() {
      if (piles.contains(GamePileId.pile1)) _pile1LandingSequence += 1;
      if (piles.contains(GamePileId.pile2)) _pile2LandingSequence += 1;
    });
  }

  void _finishResultPresentation() {
    if (!mounted) return;
    setState(() {
      _showResultPresentation = false;
      _resultPresentationPending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gameState = widget.gameState;
    final gameFinished = gameState.status == GameMatchStatus.finished;
    final resultMessage = _finishedResultMessage(gameState);
    final moveFeedback = widget.feedbackMessage ?? _localFeedback;
    final instruction =
        widget.coachingMessage ??
        (gameFinished
            ? 'The match has ended. Move controls are disabled.'
            : !widget.movesEnabled
            ? 'Moves are paused until both players are connected.'
            : _selectedCardId == null
            ? 'Select one of your cards, then select a center pile.'
            : 'Now select the center pile where you want to play it.');

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
                  matchStatus: gameState.status,
                  elapsedTimeMs: gameState.elapsedTimeMs,
                  myRttEstimateMs: widget.movesEnabled
                      ? widget.myRttEstimateMs
                      : null,
                  rttSampleSequence: widget.rttSampleSequence,
                ),
                const SizedBox(height: 14),
                if (gameFinished) ...[
                  _GameResultPanel(message: resultMessage),
                  if (gameState.endReason == GameMatchEndReason.normal) ...[
                    const SizedBox(height: 12),
                    _RematchPanel(
                      status: widget.rematchStatus,
                      currentUserId: widget.currentUserId,
                      isSubmitting: widget.isRematchSubmitting,
                      onDecision: widget.onRematchDecision,
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                if (widget.connectionMessage case final message?) ...[
                  _ConnectionPanel(
                    message: message,
                    disconnectDeadlineMs: widget.disconnectDeadlineMs,
                    serverTimeMs: widget.connectionServerTimeMs,
                    networkRttMs: widget.myRttEstimateMs,
                  ),
                  const SizedBox(height: 10),
                ],
                _OpponentLane(
                  handCount: gameState.opponentHandCount,
                  deckCount: gameState.opponentDeckCount,
                  anchorKey: _opponentAnchorKey,
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
                      anchorKey: _pile1AnchorKey,
                      highlighted: widget.highlightedPileIds.contains(
                        GamePileId.pile1,
                      ),
                      rejected: _illegalPileId == GamePileId.pile1,
                      shakeSequence: _illegalShakeSequence,
                      landingSequence: _pile1LandingSequence,
                      onTap: _canPlay && _selectedCardId != null
                          ? () => _submitToPile(GamePileId.pile1)
                          : null,
                    ),
                    _PileStack(
                      key: const ValueKey('centerPile2'),
                      label: 'Pile 2',
                      topCard: gameState.pile2.topCard,
                      anchorKey: _pile2AnchorKey,
                      highlighted: widget.highlightedPileIds.contains(
                        GamePileId.pile2,
                      ),
                      rejected: _illegalPileId == GamePileId.pile2,
                      shakeSequence: _illegalShakeSequence,
                      landingSequence: _pile2LandingSequence,
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
                  pendingCardId: widget.pendingCardId,
                  highlightedCardIds: widget.highlightedCardIds,
                  onSelectCard: _canPlay ? _selectCard : null,
                  anchorKey: _playerAnchorKey,
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
          Positioned.fill(
            child: _GameplayTransitionOverlay(
              transitions: widget.transitions,
              roundSequence: widget.transitionRoundSequence,
              stateVersion: gameState.stateVersion,
              playerAnchorKey: _playerAnchorKey,
              opponentAnchorKey: _opponentAnchorKey,
              pile1AnchorKey: _pile1AnchorKey,
              pile2AnchorKey: _pile2AnchorKey,
              onBusyChanged: _handleTransitionBusyChanged,
              onLanded: _handleTransitionLanded,
            ),
          ),
          Positioned.fill(
            child: _PileResetPresentation(
              sequence: widget.pileResetSequence,
              active: widget.pileResetActive,
            ),
          ),
          if (moveFeedback != null)
            Positioned.fill(
              child: IgnorePointer(
                key: const ValueKey('moveFeedbackOverlay'),
                child: SafeArea(
                  minimum: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _FeedbackPanel(message: moveFeedback),
                  ),
                ),
              ),
            ),
          if (widget.localReconnectRemainingSeconds != null ||
              widget.localReconnectExpired)
            Positioned.fill(
              child: _LocalReconnectOverlay(
                remainingSeconds: widget.localReconnectRemainingSeconds,
                expired: widget.localReconnectExpired,
                onRetry: widget.onRetryReconnect,
                onReturnToMenu: widget.onReturnToMenu,
              ),
            ),
          if (gameFinished && _showResultPresentation)
            Positioned.fill(
              child: _ResultPresentation(
                outcome: gameState.winnerId == null
                    ? _ResultOutcome.neutral
                    : gameState.winnerId == widget.currentUserId
                    ? _ResultOutcome.victory
                    : _ResultOutcome.defeat,
                forfeit: gameState.endReason == GameMatchEndReason.forfeit,
                elapsedTimeMs: gameState.elapsedTimeMs,
                onStarted: widget.onResultPresentationStarted,
                onFinished: _finishResultPresentation,
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

class RoundCountdownOverlay extends StatefulWidget {
  const RoundCountdownOverlay({
    super.key,
    required this.durationMs,
    this.startsAtMs,
    this.serverTimeMs,
    this.networkRttMs,
    required this.roundNumber,
    this.onCountdownChanged,
  });

  final int durationMs;
  final int? startsAtMs;
  final int? serverTimeMs;
  final int? networkRttMs;
  final int? roundNumber;
  final ValueChanged<int>? onCountdownChanged;

  @override
  State<RoundCountdownOverlay> createState() => _RoundCountdownOverlayState();
}

class _RoundCountdownOverlayState extends State<RoundCountdownOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Ticker _deadlineTicker;
  final Set<int> _emittedCues = <int>{};
  late int _anchorRemainingMs;
  late int _secondsRemaining;
  late int _maximumSeconds;
  String? _logicalDeadlineKey;
  bool? _reduceMotion;
  Duration _deadlineElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _deadlineTicker = createTicker(_handleDeadlineTick);
    _configureDeadline();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _syncPulseAnimation();
  }

  @override
  void didUpdateWidget(covariant RoundCountdownOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startsAtMs != widget.startsAtMs ||
        oldWidget.serverTimeMs != widget.serverTimeMs ||
        oldWidget.networkRttMs != widget.networkRttMs ||
        (widget.startsAtMs == null &&
            oldWidget.durationMs != widget.durationMs)) {
      _configureDeadline();
    }
  }

  void _configureDeadline() {
    _deadlineTicker.stop();
    final startsAtMs = widget.startsAtMs;
    final serverTimeMs = widget.serverTimeMs;
    final logicalKey = startsAtMs == null
        ? 'duration:${widget.durationMs}'
        : 'deadline:$startsAtMs';
    if (_logicalDeadlineKey != logicalKey) {
      _emittedCues.clear();
      _logicalDeadlineKey = logicalKey;
    }
    final remainingFromServer = startsAtMs == null
        ? widget.durationMs
        : serverTimeMs == null
        ? startsAtMs - DateTime.now().millisecondsSinceEpoch
        : startsAtMs - serverTimeMs;
    final oneWayCompensationMs = ((widget.networkRttMs ?? 0) / 2)
        .round()
        .clamp(0, 500)
        .toInt();
    _anchorRemainingMs = math.max(
      0,
      remainingFromServer - oneWayCompensationMs,
    );
    _maximumSeconds = math.max(1, (widget.durationMs / 1000).ceil());
    _deadlineElapsed = Duration.zero;
    _secondsRemaining = _remainingSeconds();
    _notifyCueOnce(_secondsRemaining);
    if (_secondsRemaining > 0) _deadlineTicker.start();
  }

  int _remainingSeconds() {
    final milliseconds = math.max(
      0,
      _anchorRemainingMs - _deadlineElapsed.inMilliseconds,
    );
    return (milliseconds / 1000).ceil().clamp(0, _maximumSeconds);
  }

  void _handleDeadlineTick(Duration elapsed) {
    if (!mounted) return;
    _deadlineElapsed = elapsed;
    final next = _remainingSeconds();
    if (next == _secondsRemaining) return;
    _notifyCueOnce(next);
    setState(() => _secondsRemaining = next);
    if (next == 0) _deadlineTicker.stop();
  }

  void _notifyCueOnce(int value) {
    if (value < 0 || value > _maximumSeconds || !_emittedCues.add(value)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCountdownChanged?.call(value);
    });
  }

  void _syncPulseAnimation() {
    if (_reduceMotion == true) {
      _pulseController
        ..stop()
        ..value = 0.5;
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _deadlineTicker.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pulse = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
    final label = _secondsRemaining > 0 ? '$_secondsRemaining' : 'GO!';
    final isFirstRound = (widget.roundNumber ?? 1) <= 1;

    return Semantics(
      liveRegion: true,
      excludeSemantics: true,
      label: _secondsRemaining > 0
          ? 'Match starts in $_secondsRemaining seconds'
          : 'Go',
      child: DecoratedBox(
        key: ValueKey(
          isFirstRound
              ? 'initialCountdownBackground'
              : 'rematchCountdownBackground',
        ),
        decoration: BoxDecoration(
          color: isFirstRound ? null : _sprintBlue.withValues(alpha: 0.80),
          gradient: isFirstRound
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF171B63),
                    Color(0xFF393DA5),
                    Color(0xFF7565D8),
                  ],
                )
              : null,
        ),
        child: Stack(
          children: [
            if (isFirstRound)
              const Positioned.fill(
                child: CustomPaint(painter: _CountdownBackdropPainter()),
              ),
            Center(
              child: AnimatedBuilder(
                animation: pulse,
                builder: (context, child) {
                  final value = pulse.value;
                  return Transform.scale(
                    scale: 0.92 + value * 0.16,
                    child: Container(
                      key: const ValueKey('rematchCountdown'),
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [_sprintYellow, _sprintOrange],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.92),
                          width: 5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _sprintYellow.withValues(
                              alpha: 0.45 + value * 0.30,
                            ),
                            blurRadius: 34 + value * 28,
                            spreadRadius: 8 + value * 12,
                          ),
                          const BoxShadow(
                            color: Color(0x99000000),
                            blurRadius: 26,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            label,
                            key: const ValueKey('rematchCountdownValue'),
                            style: const TextStyle(
                              color: _sprintBlue,
                              fontSize: 92,
                              height: 0.95,
                              fontWeight: FontWeight.w900,
                              shadows: [
                                Shadow(
                                  color: Color(0x55000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                          ),
                          if (!isFirstRound)
                            Text(
                              'ROUND ${widget.roundNumber}',
                              style: const TextStyle(
                                color: _sprintBlue,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownBackdropPainter extends CustomPainter {
  const _CountdownBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.5, size.height * 0.46),
              radius: size.shortestSide * 0.55,
            ),
          );
    canvas.drawRect(Offset.zero & size, glowPaint);

    final orbitPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final center = Offset(size.width / 2, size.height * 0.46);
    for (final radius in <double>[150, 230, 320]) {
      canvas.drawCircle(center, radius, orbitPaint);
    }

    final sparkPaint = Paint()..color = _sprintYellow.withValues(alpha: 0.55);
    const sparks = <Offset>[
      Offset(0.12, 0.18),
      Offset(0.83, 0.16),
      Offset(0.18, 0.72),
      Offset(0.88, 0.68),
      Offset(0.30, 0.87),
      Offset(0.70, 0.84),
    ];
    for (var index = 0; index < sparks.length; index++) {
      final spark = sparks[index];
      canvas.drawCircle(
        Offset(size.width * spark.dx, size.height * spark.dy),
        index.isEven ? 5 : 3,
        sparkPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CountdownBackdropPainter oldDelegate) => false;
}

class _RematchPanel extends StatelessWidget {
  const _RematchPanel({
    required this.status,
    required this.currentUserId,
    required this.isSubmitting,
    required this.onDecision,
  });

  final RematchStatusView? status;
  final String currentUserId;
  final bool isSubmitting;
  final RematchDecisionCallback? onDecision;

  @override
  Widget build(BuildContext context) {
    final value = status;
    String message;
    if (value == null) {
      message = 'Play another round with the same opponent?';
    } else {
      switch (value.status) {
        case GameRematchStatus.requested:
          message = value.requestedBy == currentUserId
              ? 'Waiting for your opponent…'
              : 'Your opponent wants a rematch.';
        case GameRematchStatus.preparing:
          message = 'Both players are ready. Preparing the next round…';
        case GameRematchStatus.starting:
          message = 'Rematch accepted. Starting round ${value.roundNumber}…';
        case GameRematchStatus.declined:
          message = 'The rematch was declined.';
        case GameRematchStatus.expired:
          message = 'The rematch request expired.';
        case GameRematchStatus.unavailable:
          message = 'Rematch is unavailable because a player left.';
      }
    }

    final canDecide =
        onDecision != null &&
        !isSubmitting &&
        (value == null ||
            (value.status == GameRematchStatus.requested &&
                value.requestedBy != currentUserId));
    final waitingForOpponent =
        value?.status == GameRematchStatus.requested &&
        value?.requestedBy == currentUserId;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message,
              key: const ValueKey('rematchStatusMessage'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (isSubmitting) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ] else if (canDecide) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('acceptRematchButton'),
                      onPressed: () => onDecision!(true),
                      child: Text(value == null ? 'Rematch' : 'Accept'),
                    ),
                  ),
                  if (value != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('declineRematchButton'),
                        onPressed: () => onDecision!(false),
                        child: const Text('Decline'),
                      ),
                    ),
                  ],
                ],
              ),
            ] else if (waitingForOpponent && onDecision != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('cancelRematchButton'),
                onPressed: () => onDecision!(false),
                child: const Text('Cancel rematch'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArenaHeader extends StatelessWidget {
  const _ArenaHeader({
    required this.title,
    required this.matchStatus,
    required this.elapsedTimeMs,
    required this.myRttEstimateMs,
    required this.rttSampleSequence,
  });

  final String title;
  final GameMatchStatus matchStatus;
  final int elapsedTimeMs;
  final int? myRttEstimateMs;
  final int rttSampleSequence;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
          );
          final indicators = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ElapsedTimeChip(
                status: matchStatus,
                elapsedTimeMs: elapsedTimeMs,
              ),
              _NetworkQualityIndicator(
                rttMs: myRttEstimateMs,
                sampleSequence: rttSampleSequence,
              ),
            ],
          );
          if (constraints.maxWidth < 430) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: indicators),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 12),
              indicators,
            ],
          );
        },
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
  const _OpponentLane({
    required this.handCount,
    required this.deckCount,
    required this.anchorKey,
  });

  final int handCount;
  final int deckCount;
  final GlobalKey anchorKey;

  @override
  Widget build(BuildContext context) {
    return _SceneBand(
      title: 'Opponent',
      trailing: '$handCount cards',
      child: KeyedSubtree(
        key: anchorKey,
        child: _OpponentArea(handCount: handCount, deckCount: deckCount),
      ),
    );
  }
}

class _PlayerLane extends StatelessWidget {
  const _PlayerLane({
    required this.hand,
    required this.deckCount,
    required this.selectedCardId,
    required this.pendingCardId,
    required this.highlightedCardIds,
    required this.onSelectCard,
    required this.anchorKey,
  });

  final List<GameCard> hand;
  final int deckCount;
  final String? selectedCardId;
  final String? pendingCardId;
  final Set<String> highlightedCardIds;
  final ValueChanged<String>? onSelectCard;
  final GlobalKey anchorKey;

  @override
  Widget build(BuildContext context) {
    return _SceneBand(
      title: 'Your cards',
      trailing: '$deckCount in deck',
      child: KeyedSubtree(
        key: anchorKey,
        child: _HandRow(
          hand: hand,
          deckCount: deckCount,
          selectedCardId: selectedCardId,
          pendingCardId: pendingCardId,
          highlightedCardIds: highlightedCardIds,
          onSelectCard: onSelectCard,
        ),
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

String _cardSemanticLabel(GameCard card) {
  final shape = card.shape.name;
  final pluralShape = card.count == 1 ? shape : '${shape}s';
  return '${card.color.name}, ${card.count} $pluralShape';
}

class _PileStack extends StatelessWidget {
  const _PileStack({
    super.key,
    required this.label,
    required this.topCard,
    required this.anchorKey,
    this.highlighted = false,
    this.rejected = false,
    this.shakeSequence = 0,
    this.landingSequence = 0,
    this.onTap,
  });

  final String label;
  final GameCard topCard;
  final GlobalKey anchorKey;
  final bool highlighted;
  final bool rejected;
  final int shakeSequence;
  final int landingSequence;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const stackOffset = 4.0;
    final active = onTap != null;

    final borderColor = rejected
        ? const Color(0xFFD9364B)
        : active
        ? _sprintBlue
        : _sprintBlue.withValues(alpha: 0.18);
    return _ShakeOnChange(
      sequence: rejected ? shakeSequence : 0,
      child: _LandingPulseOnChange(
        sequence: landingSequence,
        child: _AttentionPulse(
          active: highlighted,
          borderRadius: 20,
          child: KeyedSubtree(
            key: anchorKey,
            child: Semantics(
              key: ValueKey(
                '${label.toLowerCase().replaceAll(' ', '')}Semantics',
              ),
              button: true,
              enabled: active,
              liveRegion: rejected,
              excludeSemantics: true,
              label: '$label, ${_cardSemanticLabel(topCard)}',
              value: rejected ? 'Move rejected' : 'Center pile',
              hint: !active
                  ? 'Select a card first'
                  : 'Double tap to try the selected card',
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: rejected
                        ? const Color(0xFFFFB6BF).withValues(alpha: 0.58)
                        : active
                        ? _sprintYellow.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.36),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: borderColor,
                      width: rejected || active ? 3 : 1.4,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: _sprintBlue,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          if (rejected) ...[
                            const SizedBox(width: 5),
                            Icon(
                              Icons.block_rounded,
                              key: const ValueKey('rejectedTargetIcon'),
                              size: 17,
                              color: borderColor,
                            ),
                          ],
                        ],
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
                            Positioned(
                              left: 0,
                              top: 0,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutBack,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: Tween(
                                          begin: 0.88,
                                          end: 1.0,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                child: KeyedSubtree(
                                  key: ValueKey('pile-card-${topCard.cardId}'),
                                  child: _CardFront(card: topCard),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const double _handSpacing = 6;
const double _handCardMinWidth = 48;
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
    required this.pendingCardId,
    required this.highlightedCardIds,
    required this.onSelectCard,
  });

  final List<GameCard> hand;
  final int deckCount;
  final String? selectedCardId;
  final String? pendingCardId;
  final Set<String> highlightedCardIds;
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
                pending: card.cardId == pendingCardId,
                highlighted: highlightedCardIds.contains(card.cardId),
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
    this.pending = false,
    this.highlighted = false,
    this.onTap,
    this.width = _cardWidth,
    this.height = _cardHeight,
  });

  final GameCard card;
  final bool selected;
  final bool pending;
  final bool highlighted;
  final VoidCallback? onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      excludeSemantics: true,
      label: _cardSemanticLabel(card),
      value: pending
          ? 'Move pending'
          : selected
          ? 'Selected'
          : 'Not selected',
      hint: pending
          ? 'Waiting for the server'
          : onTap == null
          ? 'Move controls are disabled'
          : selected
          ? 'Double tap to deselect this card'
          : 'Double tap to select this card',
      child: _AttentionPulse(
        active: highlighted && !selected,
        borderRadius: 20,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: pending ? 0.68 : 1,
          child: Transform.translate(
            offset: selected || pending ? const Offset(0, -10) : Offset.zero,
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
                    if (selected || pending)
                      BoxShadow(
                        color: _sprintYellow.withValues(alpha: 0.48),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                  ],
                ),
                child: Stack(
                  children: [
                    _CardFront(
                      card: card,
                      width: width - 6,
                      height: height - 6,
                    ),
                    if (pending)
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0x332C3192),
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                          ),
                          child: Center(
                            child: SizedBox.square(
                              dimension: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: _sprintYellow,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (selected)
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: Icon(
                          Icons.check_circle,
                          color: _sprintBlue,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttentionPulse extends StatefulWidget {
  const _AttentionPulse({
    required this.active,
    required this.child,
    this.borderRadius = 18,
  });

  final bool active;
  final Widget child;
  final double borderRadius;

  @override
  State<_AttentionPulse> createState() => _AttentionPulseState();
}

class _AttentionPulseState extends State<_AttentionPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _AttentionPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.active && !_reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final value = Curves.easeInOut.transform(_controller.value);
        return Transform.scale(
          scale: 1 + value * 0.025,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: Color.lerp(_sprintYellow, _sprintOrange, value)!,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: _sprintYellow.withValues(alpha: 0.28 + value * 0.25),
                  blurRadius: 12 + value * 14,
                  spreadRadius: value * 3,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _ShakeOnChange extends StatefulWidget {
  const _ShakeOnChange({required this.sequence, required this.child});

  final int sequence;
  final Widget child;

  @override
  State<_ShakeOnChange> createState() => _ShakeOnChangeState();
}

class _ShakeOnChangeState extends State<_ShakeOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) _controller.stop();
  }

  @override
  void didUpdateWidget(covariant _ShakeOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_reduceMotion &&
        widget.sequence != 0 &&
        widget.sequence != oldWidget.sequence) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final offset =
            math.sin(_controller.value * math.pi * 6) *
            9 *
            (1 - _controller.value);
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
    );
  }
}

class _LandingPulseOnChange extends StatefulWidget {
  const _LandingPulseOnChange({required this.sequence, required this.child});

  final int sequence;
  final Widget child;

  @override
  State<_LandingPulseOnChange> createState() => _LandingPulseOnChangeState();
}

class _LandingPulseOnChangeState extends State<_LandingPulseOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _staticTimer;
  bool _reduceMotion = false;
  bool _showStatic = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) _controller.stop();
  }

  @override
  void didUpdateWidget(covariant _LandingPulseOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sequence == 0 || widget.sequence == oldWidget.sequence) return;
    _staticTimer?.cancel();
    if (_reduceMotion) {
      _showStatic = true;
      _staticTimer = Timer(const Duration(milliseconds: 420), () {
        if (mounted) setState(() => _showStatic = false);
      });
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _staticTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) {
      return DecoratedBox(
        key: ValueKey('landingPulse-${widget.sequence}'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: _showStatic
              ? Border.all(color: _sprintYellow, width: 4)
              : null,
        ),
        child: widget.child,
      );
    }
    return KeyedSubtree(
      key: ValueKey('landingPulse-${widget.sequence}'),
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final pulse = math.sin(_controller.value * math.pi);
          return Transform.scale(
            scale: 1 + pulse * 0.055,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: pulse <= 0
                    ? const <BoxShadow>[]
                    : [
                        BoxShadow(
                          color: _sprintYellow.withValues(alpha: pulse * 0.62),
                          blurRadius: 28 * pulse,
                          spreadRadius: 5 * pulse,
                        ),
                      ],
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

enum _NetworkTier { hidden, degraded, poor }

class _NetworkQualityIndicator extends StatefulWidget {
  const _NetworkQualityIndicator({
    required this.rttMs,
    required this.sampleSequence,
  });

  final int? rttMs;
  final int sampleSequence;

  @override
  State<_NetworkQualityIndicator> createState() =>
      _NetworkQualityIndicatorState();
}

class _NetworkQualityIndicatorState extends State<_NetworkQualityIndicator> {
  final List<int> _samples = <int>[];
  _NetworkTier _tier = _NetworkTier.hidden;
  int? _displayRttMs;
  int _healthyReadings = 0;
  int _degradedReadings = 0;
  Timer? _freshnessTimer;

  @override
  void initState() {
    super.initState();
    _record(widget.rttMs);
  }

  @override
  void didUpdateWidget(covariant _NetworkQualityIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rttMs != oldWidget.rttMs ||
        widget.sampleSequence != oldWidget.sampleSequence) {
      _record(widget.rttMs);
    }
  }

  void _record(int? value) {
    _freshnessTimer?.cancel();
    if (value == null) {
      _freshnessTimer = null;
      _samples.clear();
      _tier = _NetworkTier.hidden;
      _displayRttMs = null;
      _healthyReadings = 0;
      _degradedReadings = 0;
      return;
    }
    _freshnessTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      setState(() {
        _freshnessTimer = null;
        _samples.clear();
        _tier = _NetworkTier.hidden;
        _displayRttMs = null;
        _healthyReadings = 0;
        _degradedReadings = 0;
      });
    });
    _samples
      ..add(value)
      ..removeRange(0, math.max(0, _samples.length - 3));
    final average = _samples.reduce((a, b) => a + b) / _samples.length;
    _displayRttMs = average.round();
    if (value >= 400 || average >= 400) {
      _tier = _NetworkTier.poor;
      _healthyReadings = 0;
      _degradedReadings += 1;
    } else if (average >= 200) {
      _healthyReadings = 0;
      _degradedReadings += 1;
      if (_degradedReadings >= 2 || _tier != _NetworkTier.hidden) {
        _tier = _NetworkTier.degraded;
      }
    } else if (average < 180) {
      _degradedReadings = 0;
      _healthyReadings += 1;
      if (_healthyReadings >= 3) {
        _tier = _NetworkTier.hidden;
        _freshnessTimer?.cancel();
        _freshnessTimer = null;
      }
    } else {
      _degradedReadings = 0;
      _healthyReadings += 1;
      if (_healthyReadings >= 3) {
        _tier = _NetworkTier.hidden;
        _freshnessTimer?.cancel();
        _freshnessTimer = null;
      }
    }
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tier == _NetworkTier.hidden) return const SizedBox.shrink();
    final poor = _tier == _NetworkTier.poor;
    final rttMs = _displayRttMs ?? widget.rttMs ?? 0;
    final color = poor ? const Color(0xFFD9364B) : const Color(0xFFB26A00);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: poor
            ? 'Poor connection ($rttMs ms)'
            : 'Connection is slower than usual ($rttMs ms)',
        child: Semantics(
          label:
              '${poor ? 'Poor' : 'Degraded'} connection, '
              '$rttMs milliseconds round-trip latency',
          child: Container(
            key: const ValueKey('degradedConnectionIndicator'),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  poor ? Icons.wifi_off_rounded : Icons.wifi_2_bar_rounded,
                  size: 17,
                  color: color,
                ),
                if (poor) ...[
                  const SizedBox(width: 5),
                  Text(
                    'Poor',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                const SizedBox(width: 5),
                Text(
                  '$rttMs ms',
                  key: const ValueKey('degradedConnectionRtt'),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GameplayTransitionOverlay extends StatefulWidget {
  const _GameplayTransitionOverlay({
    required this.transitions,
    required this.roundSequence,
    required this.stateVersion,
    required this.playerAnchorKey,
    required this.opponentAnchorKey,
    required this.pile1AnchorKey,
    required this.pile2AnchorKey,
    required this.onBusyChanged,
    required this.onLanded,
  });

  final List<GameStateTransition> transitions;
  final int roundSequence;
  final int stateVersion;
  final GlobalKey playerAnchorKey;
  final GlobalKey opponentAnchorKey;
  final GlobalKey pile1AnchorKey;
  final GlobalKey pile2AnchorKey;
  final ValueChanged<bool> onBusyChanged;
  final ValueChanged<Set<GamePileId>> onLanded;

  @override
  State<_GameplayTransitionOverlay> createState() =>
      _GameplayTransitionOverlayState();
}

class _GameplayTransitionOverlayState extends State<_GameplayTransitionOverlay>
    with SingleTickerProviderStateMixin {
  static const int _maximumPendingBatches = 6;
  static const int _maximumRememberedSequences = 32;
  static const Duration _flightDuration = Duration(milliseconds: 350);
  final GlobalKey _overlayKey = GlobalKey(debugLabel: 'flight-overlay');
  final ListQueue<_TransitionBatch> _pending = ListQueue<_TransitionBatch>();
  final LinkedHashSet<_TransitionBatchIdentity> _seenBatchIdentities =
      LinkedHashSet<_TransitionBatchIdentity>();
  late final AnimationController _controller;
  Timer? _reducedMotionTimer;
  _TransitionBatch? _current;
  _FlightGeometry? _geometry;
  bool _reduceMotion = false;
  bool _reportedBusy = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _flightDuration)
      ..addStatusListener(_handleAnimationStatus);
    _enqueue(
      roundSequence: widget.roundSequence,
      stateVersion: widget.stateVersion,
      transitions: widget.transitions,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (_reduceMotion && _current != null) {
      _controller.stop();
      _showReducedMotionFeedback();
    }
  }

  @override
  void didUpdateWidget(covariant _GameplayTransitionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _enqueue(
      roundSequence: widget.roundSequence,
      stateVersion: widget.stateVersion,
      transitions: widget.transitions,
    );
  }

  void _enqueue({
    required int roundSequence,
    required int stateVersion,
    required List<GameStateTransition> transitions,
  }) {
    final identity = _TransitionBatchIdentity(
      roundSequence: roundSequence,
      stateVersion: stateVersion,
    );
    if (transitions.isEmpty || _seenBatchIdentities.contains(identity)) return;
    _seenBatchIdentities.add(identity);
    while (_seenBatchIdentities.length > _maximumRememberedSequences) {
      _seenBatchIdentities.remove(_seenBatchIdentities.first);
    }
    final compressedLandings = <GamePileId>{};
    while (_pending.length >= _maximumPendingBatches) {
      final compressed = _pending.removeFirst();
      compressedLandings.addAll(
        compressed.transitions.map((transition) => transition.targetPileId),
      );
    }
    if (compressedLandings.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLanded(compressedLandings);
      });
    }
    _pending.add(
      _TransitionBatch(
        identity: identity,
        transitions: List<GameStateTransition>.unmodifiable(transitions),
      ),
    );
    _setReportedBusy(true);
    if (_current == null) _startNextBatch();
  }

  void _startNextBatch() {
    if (!mounted || _current != null) return;
    if (_pending.isEmpty) {
      _setReportedBusy(false);
      return;
    }
    _current = _pending.removeFirst();
    _geometry = null;
    if (_reduceMotion) {
      _showReducedMotionFeedback();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _current == null || _reduceMotion) return;
      final geometry = _measureGeometry();
      if (geometry == null) {
        _completeCurrentBatch();
        return;
      }
      setState(() => _geometry = geometry);
      _controller.forward(from: 0);
    });
  }

  _FlightGeometry? _measureGeometry() {
    final batch = _current;
    if (batch == null) return null;
    final overlayBox =
        _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) return null;

    Offset? centerOf(GlobalKey key) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      final globalCenter = box.localToGlobal(box.size.center(Offset.zero));
      return overlayBox.globalToLocal(globalCenter);
    }

    final player = centerOf(widget.playerAnchorKey);
    final opponent = centerOf(widget.opponentAnchorKey);
    final pile1 = centerOf(widget.pile1AnchorKey);
    final pile2 = centerOf(widget.pile2AnchorKey);
    // A fast player can scroll a lane just outside ListView's cache before the
    // confirmed state arrives. Prefer the real anchors, then use responsive
    // viewport positions so decorative feedback is not silently discarded.
    final horizontalCenter = overlayBox.size.width / 2;
    final tableY = overlayBox.size.height * 0.48;
    return _FlightGeometry(
      player: player ?? Offset(horizontalCenter, overlayBox.size.height + 45),
      opponent: opponent ?? Offset(horizontalCenter, -45),
      pile1: pile1 ?? Offset(overlayBox.size.width * 0.38, tableY),
      pile2: pile2 ?? Offset(overlayBox.size.width * 0.62, tableY),
    );
  }

  void _showReducedMotionFeedback() {
    _controller.stop();
    _reducedMotionTimer?.cancel();
    if (mounted) setState(() => _geometry = null);
    _reducedMotionTimer = Timer(const Duration(milliseconds: 320), () {
      if (mounted) _completeCurrentBatch();
    });
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _completeCurrentBatch();
  }

  void _completeCurrentBatch() {
    final batch = _current;
    if (!mounted || batch == null) return;
    final landedPiles = batch.transitions
        .map((transition) => transition.targetPileId)
        .toSet();
    widget.onLanded(landedPiles);
    setState(() {
      _current = null;
      _geometry = null;
    });
    _startNextBatch();
  }

  void _setReportedBusy(bool busy) {
    if (_reportedBusy == busy) return;
    _reportedBusy = busy;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _reportedBusy == busy) widget.onBusyChanged(busy);
    });
  }

  @override
  void dispose() {
    _reducedMotionTimer?.cancel();
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final batch = _current;
    final semanticsLabel = batch == null
        ? null
        : batch.transitions.length == 1
        ? batch.transitions.single.actor == GameStateTransitionActor.opponent
              ? 'Opponent played a card'
              : 'Your card was played'
        : '${batch.transitions.length} cards were played';
    return IgnorePointer(
      child: Semantics(
        liveRegion: batch != null,
        label: semanticsLabel,
        excludeSemantics: true,
        child: SizedBox.expand(
          key: _overlayKey,
          child: batch == null
              ? const SizedBox.shrink()
              : _reduceMotion
              ? Align(
                  alignment: Alignment.topCenter,
                  child: SafeArea(
                    child: Container(
                      key: const ValueKey('reducedMotionMoveFeedback'),
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _sprintBlue,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        semanticsLabel ?? 'Card played',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                )
              : _geometry == null
              ? const SizedBox.shrink()
              : ClipRect(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) => Stack(
                      children: [
                        for (
                          var index = 0;
                          index < batch.transitions.length;
                          index++
                        )
                          _buildFlight(
                            batch.transitions[index],
                            batch.identity,
                            index,
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFlight(
    GameStateTransition transition,
    _TransitionBatchIdentity identity,
    int index,
  ) {
    final geometry = _geometry!;
    final progress = _controller.value.clamp(0.0, 1.0);
    if (progress <= 0 || progress >= 1) return const SizedBox.shrink();
    final eased = Curves.easeInOutCubic.transform(progress);
    final start = transition.actor == GameStateTransitionActor.self
        ? geometry.player
        : geometry.opponent;
    final end = transition.targetPileId == GamePileId.pile1
        ? geometry.pile1
        : geometry.pile2;
    final position = Offset.lerp(start, end, eased)!;
    final opacity = progress > 0.88 ? (1 - progress) / 0.12 : 1.0;
    final revealOpponent =
        transition.actor == GameStateTransitionActor.self || progress >= 0.34;

    return Positioned(
      key: ValueKey(
        'transitionFlight-${identity.roundSequence}-'
        '${identity.stateVersion}-$index',
      ),
      left: position.dx - 33,
      top: position.dy - 45,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle:
              (1 - eased) *
              (transition.targetPileId == GamePileId.pile1 ? -0.16 : 0.16),
          child: Transform.scale(
            scale: 0.76 + math.sin(progress * math.pi) * 0.22,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (transition.actor == GameStateTransitionActor.opponent)
                  Container(
                    margin: const EdgeInsets.only(bottom: 5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _sprintBlue,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'OPPONENT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                if (revealOpponent)
                  _CardFront(card: transition.card, width: 66, height: 90)
                else
                  const _CardBack(width: 66, height: 90),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransitionBatch {
  const _TransitionBatch({required this.identity, required this.transitions});

  final _TransitionBatchIdentity identity;
  final List<GameStateTransition> transitions;
}

class _TransitionBatchIdentity {
  const _TransitionBatchIdentity({
    required this.roundSequence,
    required this.stateVersion,
  });

  final int roundSequence;
  final int stateVersion;

  @override
  bool operator ==(Object other) =>
      other is _TransitionBatchIdentity &&
      other.roundSequence == roundSequence &&
      other.stateVersion == stateVersion;

  @override
  int get hashCode => Object.hash(roundSequence, stateVersion);
}

class _FlightGeometry {
  const _FlightGeometry({
    required this.player,
    required this.opponent,
    required this.pile1,
    required this.pile2,
  });

  final Offset player;
  final Offset opponent;
  final Offset pile1;
  final Offset pile2;
}

class _PileResetPresentation extends StatefulWidget {
  const _PileResetPresentation({required this.sequence, required this.active});

  final int sequence;
  final bool active;

  @override
  State<_PileResetPresentation> createState() => _PileResetPresentationState();
}

class _PileResetPresentationState extends State<_PileResetPresentation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  int? _playedSequence;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncPresentation();
  }

  @override
  void didUpdateWidget(covariant _PileResetPresentation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPresentation();
  }

  void _syncPresentation() {
    if (!widget.active) {
      _controller
        ..stop()
        ..value = 0;
      return;
    }
    if (_playedSequence == widget.sequence) return;
    _playedSequence = widget.sequence;
    if (_reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: SafeArea(
          child: Semantics(
            liveRegion: true,
            container: true,
            label: 'No legal moves. Center piles were reshuffled.',
            excludeSemantics: true,
            child: Container(
              key: const ValueKey('pileResetPresentation'),
              margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _sprintYellow, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x402C3192),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) => Transform.rotate(
                      angle: _reduceMotion
                          ? 0
                          : _controller.value * math.pi * 2,
                      child: child,
                    ),
                    child: const Icon(
                      Icons.autorenew_rounded,
                      size: 28,
                      color: _sprintBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PILES RESET',
                          style: TextStyle(
                            color: _sprintBlue,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                        Text(
                          'No moves—keep playing on the new cards.',
                          style: TextStyle(
                            color: _sprintMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ResultOutcome { victory, defeat, neutral }

class _ResultPresentation extends StatefulWidget {
  const _ResultPresentation({
    required this.outcome,
    required this.forfeit,
    required this.elapsedTimeMs,
    required this.onStarted,
    required this.onFinished,
  });

  final _ResultOutcome outcome;
  final bool forfeit;
  final int elapsedTimeMs;
  final VoidCallback? onStarted;
  final VoidCallback onFinished;

  @override
  State<_ResultPresentation> createState() => _ResultPresentationState();
}

class _ResultPresentationState extends State<_ResultPresentation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _reducedMotionTimer;
  bool _started = false;
  bool _finished = false;

  bool get _won => widget.outcome == _ResultOutcome.victory;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..addStatusListener(_handleStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onStarted?.call();
    });
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _reducedMotionTimer = Timer(const Duration(milliseconds: 1050), _finish);
    } else {
      _controller.forward();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finish();
  }

  void _finish() {
    if (!mounted || _finished) return;
    _finished = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _reducedMotionTimer?.cancel();
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.outcome) {
      _ResultOutcome.victory => 'VICTORY',
      _ResultOutcome.defeat => 'DEFEAT',
      _ResultOutcome.neutral => 'MATCH COMPLETE',
    };
    final semantics = widget.forfeit
        ? _won
              ? 'Victory. Opponent disconnected.'
              : widget.outcome == _ResultOutcome.defeat
              ? 'Defeat by disconnect timeout.'
              : 'Match completed after a disconnect.'
        : '$title. Match time ${formatElapsedTimeMs(widget.elapsedTimeMs)}.';
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Widget surface(double value, {required bool animated}) {
      final opacity = !animated
          ? 1.0
          : value < 0.12
          ? value / 0.12
          : value > 0.82
          ? (1 - value) / 0.18
          : 1.0;
      final background = switch (widget.outcome) {
        _ResultOutcome.victory => const Color(0xFF292E87),
        _ResultOutcome.defeat => const Color(0xFF26313D),
        _ResultOutcome.neutral => const Color(0xFF394667),
      };
      final icon = switch (widget.outcome) {
        _ResultOutcome.victory => Icons.emoji_events_rounded,
        _ResultOutcome.defeat => Icons.sports_esports_rounded,
        _ResultOutcome.neutral => Icons.flag_circle_rounded,
      };
      return Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: ColoredBox(
          key: const ValueKey('resultPresentation'),
          color: background.withValues(alpha: 0.94),
          child: Stack(
            children: [
              if (_won && !widget.forfeit && animated)
                const Positioned.fill(
                  child: CustomPaint(painter: _CelebrationPainter()),
                ),
              Center(
                child: Transform.scale(
                  scale: !animated
                      ? 1
                      : 0.82 +
                            Curves.easeOutBack.transform(
                                  math.min(value / 0.32, 1),
                                ) *
                                0.18,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        color: _won ? _sprintYellow : const Color(0xFFDDE4EC),
                        size: 78,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _won ? _sprintYellow : Colors.white,
                          fontSize: title.length > 10 ? 30 : 42,
                          fontWeight: FontWeight.w900,
                          letterSpacing: title.length > 10 ? 2 : 4,
                          shadows: const [
                            Shadow(color: Colors.black45, blurRadius: 15),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.forfeit
                            ? _won
                                  ? 'Opponent disconnected'
                                  : widget.outcome == _ResultOutcome.defeat
                                  ? 'Connection timeout'
                                  : 'Match ended'
                            : 'Time ${formatElapsedTimeMs(widget.elapsedTimeMs)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AbsorbPointer(
      key: const ValueKey('resultPresentationBlocker'),
      absorbing: true,
      child: BlockSemantics(
        blocking: true,
        child: Semantics(
          liveRegion: true,
          scopesRoute: true,
          explicitChildNodes: true,
          container: true,
          label: semantics,
          excludeSemantics: true,
          child: reduceMotion
              ? surface(1, animated: false)
              : AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) =>
                      surface(_controller.value, animated: true),
                ),
        ),
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  const _CelebrationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const colors = <Color>[
      _sprintYellow,
      _sprintOrange,
      Color(0xFF62D6C5),
      Colors.white,
    ];
    final paint = Paint();
    for (var index = 0; index < 28; index++) {
      paint.color = colors[index % colors.length].withValues(alpha: 0.78);
      final x = ((index * 73) % 101) / 100 * size.width;
      final y = ((index * 47) % 89) / 88 * size.height;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(index * 0.71);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 9, height: 20),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter oldDelegate) => false;
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
    return Semantics(
      key: const ValueKey('moveFeedbackSemantics'),
      liveRegion: true,
      container: true,
      label: message,
      excludeSemantics: true,
      child: _AlertPanel(
        icon: Icons.warning_rounded,
        message: message,
        background: const Color(0xFFFFD1D1),
        foreground: const Color(0xFF3F1111),
      ),
    );
  }
}

class _LocalReconnectOverlay extends StatelessWidget {
  const _LocalReconnectOverlay({
    required this.remainingSeconds,
    required this.expired,
    required this.onRetry,
    required this.onReturnToMenu,
  });

  final int? remainingSeconds;
  final bool expired;
  final VoidCallback? onRetry;
  final VoidCallback? onReturnToMenu;

  @override
  Widget build(BuildContext context) {
    final seconds = math.max(0, remainingSeconds ?? 0);
    final label = expired
        ? 'Could not reconnect to the match.'
        : 'Reconnecting to the match. $seconds seconds remaining.';
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Semantics(
          liveRegion: true,
          container: true,
          label: label,
          excludeSemantics: !expired,
          child: Material(
            key: const ValueKey('localReconnectOverlay'),
            color: const Color(0xFF20265F),
            elevation: 16,
            borderRadius: BorderRadius.circular(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (expired)
                          const Icon(
                            Icons.cloud_off_rounded,
                            color: _sprintYellow,
                          )
                        else
                          const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: _sprintYellow,
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            expired
                                ? 'Could not reconnect'
                                : 'Reconnecting… $seconds s',
                            key: const ValueKey('localReconnectStatus'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (expired) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              key: const ValueKey('retryReconnectButton'),
                              onPressed: onRetry,
                              child: const Text('Try again'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              key: const ValueKey('returnToMenuButton'),
                              onPressed: onReturnToMenu,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Main menu'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionPanel extends StatefulWidget {
  const _ConnectionPanel({
    required this.message,
    required this.disconnectDeadlineMs,
    required this.serverTimeMs,
    required this.networkRttMs,
  });

  final String message;
  final int? disconnectDeadlineMs;
  final int? serverTimeMs;
  final int? networkRttMs;

  @override
  State<_ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<_ConnectionPanel>
    with SingleTickerProviderStateMixin {
  late final Ticker _deadlineTicker;
  int? _anchorRemainingMs;
  int? _remainingSeconds;
  Duration _deadlineElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _deadlineTicker = createTicker(_handleDeadlineTick);
    _configureDeadline();
  }

  @override
  void didUpdateWidget(covariant _ConnectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.disconnectDeadlineMs != widget.disconnectDeadlineMs ||
        oldWidget.serverTimeMs != widget.serverTimeMs ||
        oldWidget.networkRttMs != widget.networkRttMs) {
      _configureDeadline();
    }
  }

  void _configureDeadline() {
    _deadlineTicker.stop();
    final deadlineMs = widget.disconnectDeadlineMs;
    if (deadlineMs == null) {
      _anchorRemainingMs = null;
      _remainingSeconds = null;
      _deadlineElapsed = Duration.zero;
      return;
    }
    final serverTimeMs = widget.serverTimeMs;
    final remainingFromServer = serverTimeMs == null
        ? deadlineMs - DateTime.now().millisecondsSinceEpoch
        : deadlineMs - serverTimeMs;
    final oneWayCompensationMs = ((widget.networkRttMs ?? 0) / 2)
        .round()
        .clamp(0, 500)
        .toInt();
    _anchorRemainingMs = math.max(
      0,
      remainingFromServer - oneWayCompensationMs,
    );
    _deadlineElapsed = Duration.zero;
    _updateRemaining();
    if ((_remainingSeconds ?? 0) == 0) return;
    _deadlineTicker.start();
  }

  void _handleDeadlineTick(Duration elapsed) {
    if (!mounted) return;
    _deadlineElapsed = elapsed;
    final previous = _remainingSeconds;
    _updateRemaining();
    if (_remainingSeconds != previous) setState(() {});
  }

  void _updateRemaining() {
    final anchorRemainingMs = _anchorRemainingMs;
    if (anchorRemainingMs == null) {
      _remainingSeconds = null;
      return;
    }
    final milliseconds = math.max(
      0,
      anchorRemainingMs - _deadlineElapsed.inMilliseconds,
    );
    _remainingSeconds = (milliseconds / 1000).ceil();
    if (_remainingSeconds == 0) _deadlineTicker.stop();
  }

  @override
  void dispose() {
    _deadlineTicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _remainingSeconds;
    final secondsLabel = seconds == 1 ? '1 second' : '$seconds seconds';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AlertPanel(
          icon: Icons.wifi_off,
          message: widget.message,
          background: const Color(0xFFFFE2A8),
          foreground: const Color(0xFF3A2500),
        ),
        if (seconds != null)
          Semantics(
            liveRegion: seconds <= 10 || seconds % 5 == 0,
            label: '$secondsLabel remain for reconnection',
            child: Container(
              key: const ValueKey('reconnectCountdown'),
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: seconds <= 10
                    ? const Color(0xFFFFD1D1)
                    : const Color(0xFFFFF1CF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 20,
                    color: seconds <= 10
                        ? const Color(0xFF9C1D32)
                        : const Color(0xFF7B5200),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$secondsLabel until the match is forfeited',
                      key: const ValueKey('reconnectCountdownValue'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
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
