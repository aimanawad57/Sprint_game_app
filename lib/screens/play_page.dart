import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nakama/nakama.dart' as nakama;

import '../controllers/game_session_controller.dart';
import '../models/game/game_state_view.dart';
import '../models/game/rematch_status.dart';
import '../models/game_feedback_preferences.dart';
import '../models/play_exit_action.dart';
import '../services/game_feedback_service.dart';
import '../services/match_reconnect_coordinator.dart';
import '../services/nakama_service.dart';
import '../widgets/game_feedback_scope.dart';
import '../widgets/game_state_panel.dart';

class PlayPage extends StatefulWidget {
  const PlayPage({
    super.key,
    required this.nakamaService,
    required this.nakamaSession,
    this.directMatchId,
    this.displayCode,
  });

  final NakamaService nakamaService;
  final nakama.Session nakamaSession;
  final String? directMatchId;
  final String? displayCode;

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  GameSessionController? _sessionController;
  late GameFeedbackService _feedbackService;
  int _soundPreferenceRequestRevision = 0;
  int _vibrationPreferenceRequestRevision = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _feedbackService = GameFeedbackScope.of(context);
    _sessionController ??= GameSessionController(
      nakamaService: widget.nakamaService,
      session: widget.nakamaSession,
      feedbackService: _feedbackService,
      directMatchId: widget.directMatchId,
      displayCode: widget.displayCode,
    )..start();
  }

  @override
  void dispose() {
    _sessionController?.dispose();
    super.dispose();
  }

  void _exitPlayPage() {
    Navigator.of(context).pop(_sessionController?.exitResult);
  }

  void _showFeedbackSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => AnimatedBuilder(
        animation: _feedbackService,
        builder: (context, child) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Game feedback',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const ValueKey('soundEffectsSetting'),
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.volume_up_rounded),
                    title: const Text('Sound effects'),
                    subtitle: const Text('Moves, countdowns, and results'),
                    value: _feedbackService.soundEffectsEnabled,
                    onChanged: (enabled) =>
                        unawaited(_updateSoundEffectsSetting(enabled)),
                  ),
                  SwitchListTile(
                    key: const ValueKey('vibrationSetting'),
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.vibration_rounded),
                    title: const Text('Vibration'),
                    subtitle: const Text('Tactile feedback during play'),
                    value: _feedbackService.vibrationEnabled,
                    onChanged: (enabled) =>
                        unawaited(_updateVibrationSetting(enabled)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _updateSoundEffectsSetting(bool enabled) async {
    final requestRevision = ++_soundPreferenceRequestRevision;
    final result = await _feedbackService.setSoundEffectsEnabled(enabled);
    if (requestRevision != _soundPreferenceRequestRevision) return;
    _showPreferenceSaveFailure(result);
  }

  Future<void> _updateVibrationSetting(bool enabled) async {
    final requestRevision = ++_vibrationPreferenceRequestRevision;
    final result = await _feedbackService.setVibrationEnabled(enabled);
    if (requestRevision != _vibrationPreferenceRequestRevision) return;
    _showPreferenceSaveFailure(result);
  }

  void _showPreferenceSaveFailure(GameFeedbackPreferenceUpdateResult result) {
    if (!mounted || result.succeeded) return;
    final setting = result.preference == GameFeedbackPreference.soundEffects
        ? 'sound effects'
        : 'vibration';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save the $setting setting.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _sessionController!;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final gameState = controller.gameState;
        final connectionState = controller.connectionState;
        final localReconnectStatus = controller.reconnectStatus;
        final localReconnecting = controller.localReconnecting;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _exitPlayPage();
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Play'),
              leading: BackButton(onPressed: _exitPlayPage),
              actions: [
                IconButton(
                  tooltip: 'Sound and vibration settings',
                  onPressed: _showFeedbackSettings,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
            body: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child:
                        gameState != null &&
                            controller.phase != GameSessionPhase.failed
                        ? GameStatePanel(
                            gameState: gameState,
                            currentUserId: widget.nakamaSession.userId,
                            onSubmitMove: controller.submitMove,
                            onBack: _exitPlayPage,
                            onViewProfile:
                                gameState.status == GameMatchStatus.finished
                                ? () => Navigator.of(
                                    context,
                                  ).pop(const PlayExitResult.viewProfile())
                                : null,
                            rematchStatus: controller.rematchStatus,
                            isRematchSubmitting: controller.isRematchSubmitting,
                            onRematchDecision: controller.sendRematchDecision,
                            isSubmitting: controller.isMovePending,
                            feedbackMessage: controller.moveFeedback,
                            movesEnabled: controller.movesEnabled,
                            connectionMessage: controller.connectionMessage,
                            pendingCardId: controller.pendingCardId,
                            transitions: gameState.transitions,
                            transitionSequence: controller.transitionSequence,
                            transitionRoundSequence: controller.roundSequence,
                            pileResetSequence: controller.pileResetSequence,
                            pileResetActive: controller.pileResetActive,
                            disconnectDeadlineMs:
                                connectionState?.disconnectDeadlineMs,
                            connectionServerTimeMs:
                                connectionState?.serverTimeMs,
                            myRttEstimateMs: gameState.myRttEstimateMs,
                            rttSampleSequence:
                                gameState.myRttSampleSequence ?? 0,
                            localReconnectRemainingSeconds: localReconnecting
                                ? controller.reconnectRemainingSeconds
                                : null,
                            localReconnectExpired:
                                localReconnectStatus ==
                                MatchReconnectStatus.expired,
                            onRetryReconnect: () =>
                                unawaited(controller.retryReconnect()),
                            onReturnToMenu: _exitPlayPage,
                            onIllegalMoveFeedback: () =>
                                unawaited(_feedbackService.illegalMove()),
                            onResultPresentationStarted:
                                controller.handleResultPresentationStarted,
                          )
                        : _SessionLoadingPanel(
                            controller: controller,
                            onBack: _exitPlayPage,
                          ),
                  ),
                  if (controller.rematchStatus case final roundStart?
                      when roundStart.status == GameRematchStatus.starting)
                    Positioned.fill(
                      child: RoundCountdownOverlay(
                        durationMs: roundStart.startsInMs ?? 5000,
                        startsAtMs: roundStart.startsAtMs,
                        serverTimeMs: roundStart.serverTimeMs,
                        roundNumber: roundStart.roundNumber,
                        networkRttMs: gameState?.myRttEstimateMs,
                        onCountdownChanged: (seconds) =>
                            unawaited(_feedbackService.countdown(seconds)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SessionLoadingPanel extends StatelessWidget {
  const _SessionLoadingPanel({required this.controller, required this.onBack});

  final GameSessionController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final failed = controller.phase == GameSessionPhase.failed;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: failed
                ? Icon(
                    Icons.error,
                    size: 44,
                    color: Theme.of(context).colorScheme.error,
                  )
                : const SizedBox.square(
                    dimension: 34,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
          ),
          const SizedBox(height: 24),
          Text(
            controller.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            controller.subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 32),
          if (controller.displayCode case final code?) ...[
            _MatchCodeDisplay(code: code),
            const SizedBox(height: 32),
          ],
          if (controller.ticket case final ticket?)
            _InfoRow(label: 'Queue ticket', value: ticket),
          if (controller.matchId case final matchId?)
            _InfoRow(label: 'Match id', value: matchId),
          if (controller.matchedPlayerCount > 0)
            _InfoRow(
              label: 'Players matched',
              value: controller.matchedPlayerCount.toString(),
            ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
        ],
      ),
    );
  }
}

class _MatchCodeDisplay extends StatelessWidget {
  const _MatchCodeDisplay({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text('Match code', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SelectableText(
            code,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
            ),
          ),
        ],
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(value),
        ],
      ),
    );
  }
}
