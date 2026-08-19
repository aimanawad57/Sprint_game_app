import 'dart:async';

import 'package:flutter/material.dart';

import '../models/game/game_state_transition.dart';
import '../practice/practice_controller.dart';
import '../services/game_feedback_service.dart';
import '../services/onboarding_progress_repository.dart';
import '../widgets/game_feedback_scope.dart';
import '../widgets/game_state_panel.dart';

class PracticePage extends StatefulWidget {
  const PracticePage({super.key, required this.repository});

  final OnboardingProgressRepository repository;

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  late PracticeController _controller;
  StreamSubscription<PracticeEvent>? _eventSubscription;
  GameFeedbackService? _feedbackService;
  bool _completionRecorded = false;
  List<GameStateTransition> _transitions = const <GameStateTransition>[];
  int _transitionSequence = 0;
  int _roundSequence = 0;
  int _pileResetSequence = 0;
  bool _pileResetActive = false;
  Timer? _pileResetTimer;

  @override
  void initState() {
    super.initState();
    _controller = PracticeController()..addListener(_changed);
    _eventSubscription = _controller.events.listen(_handlePracticeEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _feedbackService = GameFeedbackScope.maybeOf(context);
  }

  void _changed() {
    if (_controller.finished && !_completionRecorded) {
      _completionRecorded = true;
      widget.repository.update((value) => value.completeFirstPractice());
    }
    if (mounted) setState(() {});
  }

  void _restart() {
    _completionRecorded = false;
    _pileResetTimer?.cancel();
    _roundSequence += 1;
    _transitions = const <GameStateTransition>[];
    _pileResetActive = false;
    _controller.restart();
  }

  void _handlePracticeEvent(PracticeEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case PracticeEventType.cardPlayed:
        final transition = event.transition;
        if (transition == null) return;
        setState(() {
          _transitions = <GameStateTransition>[transition];
          _transitionSequence += 1;
        });
        if (transition.actor == GameStateTransitionActor.self) {
          unawaited(_feedbackService?.acceptedMove());
        } else {
          unawaited(_feedbackService?.opponentMove());
        }
      case PracticeEventType.pilesReset:
        _pileResetTimer?.cancel();
        setState(() {
          _pileResetSequence += 1;
          _pileResetActive = true;
        });
        unawaited(_feedbackService?.pileReset());
        _pileResetTimer = Timer(const Duration(milliseconds: 850), () {
          if (mounted) setState(() => _pileResetActive = false);
        });
      case PracticeEventType.replacementDrawn:
      case PracticeEventType.matchEnded:
        break;
    }
  }

  void _handleResultPresentationStarted() {
    final service = _feedbackService;
    if (service == null) return;
    if (_controller.state.winnerId == PracticeController.playerId) {
      unawaited(service.win());
    } else {
      unawaited(service.loss());
    }
  }

  @override
  void dispose() {
    _pileResetTimer?.cancel();
    unawaited(_eventSubscription?.cancel());
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    return Scaffold(
      appBar: AppBar(title: const Text('Practice vs Bot')),
      body: GameStatePanel(
        gameState: state,
        currentUserId: PracticeController.playerId,
        onSubmitMove: _controller.play,
        onBack: () => Navigator.of(context).pop(),
        feedbackMessage: _controller.feedback,
        transitions: _transitions,
        transitionSequence: _transitionSequence,
        transitionRoundSequence: _roundSequence,
        pileResetSequence: _pileResetSequence,
        pileResetActive: _pileResetActive,
        onCardSelectedFeedback: () => unawaited(_feedbackService?.selection()),
        onIllegalMoveFeedback: () => unawaited(_feedbackService?.illegalMove()),
        onResultPresentationStarted: _handleResultPresentationStarted,
        coachingMessage: state.status.name == 'active'
            ? 'No turns: match color, shape, or count on either pile. Play fast!'
            : null,
      ),
      bottomNavigationBar: _controller.finished
          ? SafeArea(
              minimum: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _restart,
                      icon: const Icon(Icons.replay),
                      label: const Text('Play Again'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Try Multiplayer'),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
