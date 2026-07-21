import 'package:flutter/material.dart';

import '../practice/practice_controller.dart';
import '../services/onboarding_progress_repository.dart';
import '../widgets/game_state_panel.dart';

class PracticePage extends StatefulWidget {
  const PracticePage({super.key, required this.repository});

  final OnboardingProgressRepository repository;

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  late PracticeController _controller;
  bool _completionRecorded = false;

  @override
  void initState() {
    super.initState();
    _controller = PracticeController()..addListener(_changed);
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
    _controller.restart();
  }

  @override
  void dispose() {
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
