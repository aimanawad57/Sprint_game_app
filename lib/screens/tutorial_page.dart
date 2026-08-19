import 'dart:async';

import 'package:flutter/material.dart';

import '../models/game/game_card.dart';
import '../models/game/game_move.dart';
import '../models/game/game_state_transition.dart';
import '../models/game/game_state_view.dart';
import '../services/game_feedback_service.dart';
import '../services/onboarding_progress_repository.dart';
import '../widgets/game_feedback_scope.dart';
import '../widgets/game_state_panel.dart';
import 'practice_page.dart';

class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key, required this.repository});
  final OnboardingProgressRepository repository;

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  int _step = 0;
  String? _feedback;
  bool _invalidAttempted = false;
  bool _finalMoveAccepted = false;
  GameFeedbackService? _feedbackService;
  List<GameStateTransition> _transitions = const <GameStateTransition>[];
  int _transitionSequence = 0;
  int _roundSequence = 0;
  Timer? _completionTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _feedbackService = GameFeedbackScope.maybeOf(context);
  }

  static const _redStar2 = GameCard(
    cardId: 'tutorial_red_star_2',
    color: GameCardColor.red,
    shape: GameCardShape.star,
    count: 2,
  );
  static const _redTree4 = GameCard(
    cardId: 'tutorial_red_tree_4',
    color: GameCardColor.red,
    shape: GameCardShape.tree,
    count: 4,
  );
  static const _blueStar4 = GameCard(
    cardId: 'tutorial_blue_star_4',
    color: GameCardColor.blue,
    shape: GameCardShape.star,
    count: 4,
  );
  static const _greenFlag2 = GameCard(
    cardId: 'tutorial_green_flag_2',
    color: GameCardColor.green,
    shape: GameCardShape.flag,
    count: 2,
  );
  static const _purpleCircle5 = GameCard(
    cardId: 'tutorial_purple_circle_5',
    color: GameCardColor.purple,
    shape: GameCardShape.circle,
    count: 5,
  );
  static const _orangeHouse3 = GameCard(
    cardId: 'tutorial_orange_house_3',
    color: GameCardColor.orange,
    shape: GameCardShape.house,
    count: 3,
  );

  static const _messages = [
    'Match by color: play the red tree on the red star.',
    'Match by shape: play the blue star on the red star.',
    'Match by count: play the green 2 on the red 2.',
    'Try the purple circle on either pile. It is deliberately invalid.',
    'There are two shared center piles. Play the orange house on Pile 2.',
    'Final challenge—no hints. Find a card that matches either center pile by color, shape, or count, then play it.',
  ];

  Set<String> get _highlightedCards => switch (_step) {
    0 => {_redTree4.cardId},
    1 => {_blueStar4.cardId},
    2 => {_greenFlag2.cardId},
    3 => {_invalidAttempted ? _redTree4.cardId : _purpleCircle5.cardId},
    4 => {_orangeHouse3.cardId},
    _ => <String>{},
  };

  Set<GamePileId> get _highlightedPiles => switch (_step) {
    3 when !_invalidAttempted => {GamePileId.pile1, GamePileId.pile2},
    4 => {GamePileId.pile2},
    5 => <GamePileId>{},
    _ => {GamePileId.pile1},
  };

  GameStateView get _state {
    final hand = _finalMoveAccepted
        ? const <GameCard>[]
        : switch (_step) {
            0 => [_redTree4],
            1 => [_blueStar4],
            2 => [_greenFlag2],
            3 => [_purpleCircle5, _redTree4],
            4 => [_orangeHouse3],
            _ => [_blueStar4],
          };
    final finalTransition = _finalMoveAccepted && _transitions.isNotEmpty
        ? _transitions.single
        : null;
    return GameStateView(
      stateVersion: _step + 1 + (_finalMoveAccepted ? 1 : 0),
      status: GameMatchStatus.active,
      elapsedTimeMs: _step * 1500,
      myHand: hand,
      myDeckCount: 0,
      opponentHandCount: _step == 5 ? 1 : 3,
      opponentDeckCount: _step == 5 ? 0 : 4,
      pile1: CenterPileView(
        topCard: finalTransition?.targetPileId == GamePileId.pile1
            ? finalTransition!.card
            : _redStar2,
      ),
      pile2: CenterPileView(topCard: _step == 4 ? _orangeHouse3 : _greenFlag2),
      winnerId: null,
      winnerName: null,
      endReason: null,
    );
  }

  void _submit(String cardId, GamePileId pile) {
    if (_step == 3 && cardId == _purpleCircle5.cardId) {
      setState(() {
        _invalidAttempted = true;
        _feedback =
            'Correct observation: it matches no color, shape, or count. Now play the red card.';
      });
      return;
    }
    if (_step == 3 && !_invalidAttempted) {
      unawaited(_feedbackService?.illegalMove());
      setState(
        () => _feedback =
            'First try the purple circle so you can see how an invalid move is handled.',
      );
      return;
    }
    final card = _state.myHand.firstWhere((value) => value.cardId == cardId);
    final top = pile == GamePileId.pile1
        ? _state.pile1.topCard
        : _state.pile2.topCard;
    final valid =
        card.color == top.color ||
        card.shape == top.shape ||
        card.count == top.count;
    if (!valid) {
      setState(
        () => _feedback = 'That does not match. Check color, shape, or count.',
      );
      return;
    }
    if (_step == 4 && pile != GamePileId.pile2) {
      setState(
        () => _feedback =
            'Use Pile 2 this time to practice choosing between piles.',
      );
      return;
    }
    _advance(card, pile);
  }

  void _advance(GameCard card, GamePileId pile) {
    final transition = GameStateTransition(
      type: GameStateTransitionType.cardPlayed,
      actor: GameStateTransitionActor.self,
      card: card,
      targetPileId: pile,
    );
    if (_step >= _messages.length - 1) {
      unawaited(widget.repository.update((value) => value.completeTutorial()));
      setState(() {
        _transitions = <GameStateTransition>[transition];
        _transitionSequence += 1;
        _finalMoveAccepted = true;
        _feedback = null;
      });
      unawaited(_feedbackService?.acceptedMove());
      _completionTimer?.cancel();
      _completionTimer = Timer(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        setState(() => _step = _messages.length);
        unawaited(_feedbackService?.win());
      });
    } else {
      setState(() {
        _transitions = <GameStateTransition>[transition];
        _transitionSequence += 1;
        _step++;
        _invalidAttempted = false;
        _feedback = null;
      });
      unawaited(_feedbackService?.acceptedMove());
    }
  }

  void _previousLesson() {
    _completionTimer?.cancel();
    setState(() {
      _step--;
      _feedback = null;
      _invalidAttempted = false;
      _finalMoveAccepted = false;
      _transitions = const <GameStateTransition>[];
    });
  }

  void _restartTutorial() {
    _completionTimer?.cancel();
    setState(() {
      _step = 0;
      _feedback = null;
      _invalidAttempted = false;
      _finalMoveAccepted = false;
      _transitions = const <GameStateTransition>[];
      _roundSequence += 1;
    });
  }

  Future<void> _skip() async {
    await widget.repository.update((value) => value.dismissTutorialPrompt());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_step >= _messages.length) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tutorial complete')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.school, size: 72),
                const SizedBox(height: 16),
                Text(
                  'You know the rules!',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) =>
                          PracticePage(repository: widget.repository),
                    ),
                  ),
                  child: const Text('Start Practice Match'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Tutorial ${_step + 1}/${_messages.length}'),
        actions: [
          IconButton(
            tooltip: 'Previous lesson',
            onPressed: _step == 0 ? null : _previousLesson,
            icon: const Icon(Icons.undo),
          ),
          TextButton(onPressed: _restartTutorial, child: const Text('Restart')),
          TextButton(onPressed: _skip, child: const Text('Skip')),
        ],
      ),
      body: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.04, -0.08),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _TutorialCoachBanner(
              key: ValueKey('tutorial-prompt-$_step-$_invalidAttempted'),
              step: _step + 1,
              totalSteps: _messages.length,
              message: _feedback ?? _messages[_step],
              isFeedback: _feedback != null,
            ),
          ),
          Expanded(
            child: GameStatePanel(
              gameState: _state,
              currentUserId: 'tutorial-player',
              onSubmitMove: _submit,
              onIllegalMoveAttempt: _submit,
              onBack: () => Navigator.of(context).pop(),
              movesEnabled: !_finalMoveAccepted,
              transitions: _transitions,
              transitionSequence: _transitionSequence,
              transitionRoundSequence: _roundSequence,
              onCardSelectedFeedback: () =>
                  unawaited(_feedbackService?.selection()),
              onIllegalMoveFeedback: () =>
                  unawaited(_feedbackService?.illegalMove()),
              coachingMessage: _step == _messages.length - 1
                  ? 'No hints this time—find the legal match yourself.'
                  : 'Select the glowing card, then tap the glowing center pile.',
              highlightedCardIds: _highlightedCards,
              highlightedPileIds: _highlightedPiles,
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialCoachBanner extends StatelessWidget {
  const _TutorialCoachBanner({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.message,
    required this.isFeedback,
  });

  final int step;
  final int totalSteps;
  final String message;
  final bool isFeedback;

  @override
  Widget build(BuildContext context) {
    final colors = isFeedback
        ? const [Color(0xFFFFF1C7), Color(0xFFFFDFA0)]
        : const [Color(0xFFE7E8FF), Color(0xFFD8DBFF)];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isFeedback ? const Color(0xFFFFB23F) : const Color(0x552C3192),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x202C3192),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFF2C3192),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isFeedback ? Icons.lightbulb : Icons.touch_app,
                  color: const Color(0xFFFFDD2D),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFeedback ? 'Good try' : 'Your move',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF2C3192),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF24284F),
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$step/$totalSteps',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF59607F),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: step / totalSteps,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.72),
              color: const Color(0xFF2C3192),
            ),
          ),
        ],
      ),
    );
  }
}
