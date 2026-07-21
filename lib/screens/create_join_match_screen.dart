import 'package:flutter/material.dart';
import 'package:nakama/nakama.dart' as nakama;

import '../models/play_exit_action.dart';
import '../services/nakama_service.dart';
import '../models/onboarding_progress.dart';
import '../services/onboarding_progress_repository.dart';
import 'play_page.dart';
import 'practice_page.dart';
import 'tutorial_page.dart';

class CreateJoinMatchScreen extends StatefulWidget {
  const CreateJoinMatchScreen({
    super.key,
    required this.nakamaService,
    required this.nakamaSession,
  });

  final NakamaService nakamaService;
  final nakama.Session nakamaSession;

  @override
  State<CreateJoinMatchScreen> createState() => _CreateJoinMatchScreenState();
}

class _CreateJoinMatchScreenState extends State<CreateJoinMatchScreen> {
  final _codeController = TextEditingController();
  bool _isCreating = false;
  bool _isJoining = false;
  late final OnboardingProgressRepository _onboardingRepository;
  OnboardingProgress _onboardingProgress = const OnboardingProgress();
  bool _recommendationChecked = false;

  @override
  void initState() {
    super.initState();
    _onboardingRepository = OnboardingProgressRepository(
      nakamaService: widget.nakamaService,
      session: widget.nakamaSession,
    );
    _loadOnboarding();
  }

  Future<void> _loadOnboarding() async {
    final cached = await _onboardingRepository.readCached();
    if (mounted) setState(() => _onboardingProgress = cached);
    final progress = await _onboardingRepository.synchronize();
    if (!mounted) return;
    setState(() => _onboardingProgress = progress);
    if (!_recommendationChecked && progress.shouldRecommendTutorial) {
      _recommendationChecked = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showTutorialRecommendation(),
      );
    }
  }

  Future<void> _showTutorialRecommendation() async {
    if (!mounted) return;
    final start = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New to Sprint?'),
        content: const Text(
          'Learn matching, both center piles, automatic drawing, stuck resets, and speed—then practice against a bot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start Tutorial'),
          ),
        ],
      ),
    );
    if (start == true) {
      await _openTutorial();
    } else if (start == false) {
      final progress = await _onboardingRepository.update(
        (value) => value.dismissTutorialPrompt(),
      );
      if (mounted) setState(() => _onboardingProgress = progress);
    }
  }

  Future<void> _openTutorial() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TutorialPage(repository: _onboardingRepository),
      ),
    );
    final progress = await _onboardingRepository.synchronize();
    if (mounted) setState(() => _onboardingProgress = progress);
  }

  Future<void> _openPractice() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PracticePage(repository: _onboardingRepository),
      ),
    );
    final progress = await _onboardingRepository.synchronize();
    if (mounted) setState(() => _onboardingProgress = progress);
  }

  Future<void> _openLearningMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Learn at your pace',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Both modes are on-device and never affect competitive stats.',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _openTutorial();
                },
                icon: const Icon(Icons.school),
                label: Text(
                  _onboardingProgress.tutorialCompletedVersion >=
                          currentTutorialVersion
                      ? 'Replay Tutorial'
                      : 'Start Tutorial',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _openPractice();
                },
                icon: const Icon(Icons.smart_toy),
                label: const Text('Practice vs Bot'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openQuickMatch() async {
    final result = await Navigator.of(context).push<PlayExitResult>(
      MaterialPageRoute(
        builder: (context) {
          return PlayPage(
            nakamaService: widget.nakamaService,
            nakamaSession: widget.nakamaSession,
          );
        },
      ),
    );

    _bubblePlayResult(result);
  }

  Future<void> _createMatch() async {
    if (_isCreating) return;
    setState(() => _isCreating = true);

    try {
      final created = await widget.nakamaService.createMatchByCode(
        widget.nakamaSession,
      );

      if (!mounted) return;
      final result = await Navigator.of(context).push<PlayExitResult>(
        MaterialPageRoute(
          builder: (context) {
            return PlayPage(
              nakamaService: widget.nakamaService,
              nakamaSession: widget.nakamaSession,
              directMatchId: created.matchId,
              displayCode: created.code,
            );
          },
        ),
      );
      _bubblePlayResult(result);
    } catch (error) {
      debugPrint('Could not create match: $error');
      if (!mounted) return;
      _showMessage('Could not create a match. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _joinMatch() async {
    if (_isJoining) return;

    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showMessage('Enter a match code first.');
      return;
    }

    setState(() => _isJoining = true);

    try {
      final matchId = await widget.nakamaService.joinMatchByCode(
        session: widget.nakamaSession,
        code: code,
      );

      if (!mounted) return;
      final result = await Navigator.of(context).push<PlayExitResult>(
        MaterialPageRoute(
          builder: (context) {
            return PlayPage(
              nakamaService: widget.nakamaService,
              nakamaSession: widget.nakamaSession,
              directMatchId: matchId,
            );
          },
        ),
      );
      _bubblePlayResult(result);
    } catch (error) {
      debugPrint('Could not join match: $error');
      if (!mounted) return;
      _showMessage('That match code was not found.');
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  void _bubblePlayResult(PlayExitResult? result) {
    if (!mounted || result == null) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Play')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                key: const ValueKey('tutorialPracticeButton'),
                onPressed: _openLearningMenu,
                icon: const Icon(Icons.school),
                label: const Text('Tutorial & Practice'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _openQuickMatch,
                icon: const Icon(Icons.bolt),
                label: const Text('Quick Match'),
              ),
              const SizedBox(height: 24),
              const _SectionDivider(label: 'or play a friend'),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _isCreating ? null : _createMatch,
                icon: _isCreating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: Text(
                  _isCreating ? 'Creating match...' : 'Create Private Match',
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Match code',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isJoining ? null : _joinMatch,
                icon: _isJoining
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(
                  _isJoining ? 'Joining match...' : 'Join Private Match',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
