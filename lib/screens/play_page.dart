import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nakama/nakama.dart' as nakama;

import '../config/game_protocol.dart';
import '../models/game/game_connection.dart';
import '../models/game/game_move.dart';
import '../models/game/game_state_transition.dart';
import '../models/game/game_state_view.dart';
import '../models/game/rematch_status.dart';
import '../models/game_feedback_preferences.dart';
import '../models/play_exit_action.dart';
import '../services/game_connection_feedback_tracker.dart';
import '../services/game_feedback_service.dart';
import '../services/game_message_decoder.dart';
import '../services/match_reconnect_coordinator.dart';
import '../services/nakama_service.dart';
import '../widgets/game_feedback_scope.dart';
import '../widgets/game_state_panel.dart';

enum PlayQueueStatus {
  connecting,
  searching,
  joiningMatch,
  waitingForInitialState,
  reconnecting,
  ready,
  failed,
}

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

  /// When set, the page joins this match directly instead of using the
  /// quickplay matchmaker. Used by the create/join-by-code flow.
  final String? directMatchId;

  /// A code to show while waiting for the opponent to redeem it. Only
  /// meaningful when this client created the match (paired with
  /// [directMatchId]).
  final String? displayCode;

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  static const _messageDecoder = GameMessageDecoder();
  static final Stopwatch _monotonicClock = Stopwatch()..start();

  PlayQueueStatus _status = PlayQueueStatus.connecting;
  StreamSubscription<nakama.MatchmakerMatched>? _matchmakerSubscription;
  StreamSubscription<nakama.MatchData>? _matchDataSubscription;
  StreamSubscription<void>? _socketDisconnectSubscription;
  nakama.NakamaWebsocketClient? _socket;
  GameStateView? _gameState;
  String? _ticket;
  String? _joiningMatchId;
  String? _matchId;
  String? _errorMessage;
  String? _moveFeedback;
  String? _pendingCardId;
  bool _isMovePending = false;
  int _matchedPlayerCount = 0;
  GameConnectionView? _connectionState;
  RematchStatusView? _rematchStatus;
  bool _isRematchSubmitting = false;
  Timer? _rematchResponseTimer;
  Timer? _pileResetTimer;
  late GameFeedbackService _feedbackService;
  int _transitionSequence = 0;
  int _pileResetSequence = 0;
  bool _pileResetActive = false;
  late final MatchReconnectCoordinator _reconnectCoordinator;
  final GameConnectionFeedbackTracker _connectionFeedbackTracker =
      GameConnectionFeedbackTracker();
  int? _reconnectJoinSucceededAtMs;
  int _matchDataGeneration = 0;
  int _joinGeneration = 0;
  int _matchmakingGeneration = 0;
  int _roundSequence = 0;
  int? _lastResultFeedbackRoundSequence;
  int? _lastResultFeedbackStateVersion;
  int _soundPreferenceRequestRevision = 0;
  int _vibrationPreferenceRequestRevision = 0;
  bool _isDisposing = false;
  bool _matchmakerMatchHandled = false;

  /// Monotonic instant when the most recent authoritative state was applied.
  /// Anchors the reaction-time measurement sent with the next move without
  /// being affected by wall-clock corrections.
  int? _lastAuthoritativeStateAtMs;

  @override
  void initState() {
    super.initState();
    _reconnectCoordinator = MatchReconnectCoordinator(
      attempt: _attemptMatchRecovery,
      cancelAttempt: _cancelMatchRecoveryAttempt,
    )..addListener(_handleReconnectCoordinatorChanged);
    _socketDisconnectSubscription = widget.nakamaService.realtimeDisconnects
        .listen((_) => _handleRealtimeDisconnect());

    final directMatchId = widget.directMatchId;
    if (directMatchId != null) {
      _joinDirectMatch(directMatchId);
    } else {
      _startMatchmaking();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _feedbackService = GameFeedbackScope.of(context);
  }

  @override
  void dispose() {
    _isDisposing = true;
    _matchDataGeneration += 1;
    _joinGeneration += 1;
    _matchmakingGeneration += 1;
    unawaited(_matchDataSubscription?.cancel());
    unawaited(_matchmakerSubscription?.cancel());
    unawaited(_socketDisconnectSubscription?.cancel());
    unawaited(_cancelMatchmaking());
    unawaited(_leaveMatchIfJoined());
    _rematchResponseTimer?.cancel();
    _pileResetTimer?.cancel();
    _reconnectCoordinator
      ..removeListener(_handleReconnectCoordinatorChanged)
      ..dispose();
    super.dispose();
  }

  void _subscribeToMatchData(nakama.NakamaWebsocketClient socket) {
    final generation = ++_matchDataGeneration;
    _matchDataSubscription = socket.onMatchData.listen(
      (message) {
        if (!mounted ||
            generation != _matchDataGeneration ||
            !identical(socket, _socket)) {
          return;
        }
        _handleMatchData(message);
      },
      onError: (Object error) {
        if (!mounted || generation != _matchDataGeneration) return;
        debugPrint('Match data stream failed: $error');
      },
    );
  }

  void _handleRealtimeDisconnect() {
    if (!mounted) return;
    // Invalidate buffered events from the dead socket before starting a new
    // subscription. Only the targeted snapshot on the recovery socket may
    // complete the reconnect handshake.
    _matchDataGeneration += 1;
    _reconnectJoinSucceededAtMs = null;

    final matchId = _matchId ?? _joiningMatchId;
    final gameState = _gameState;
    if (matchId != null && gameState?.status == GameMatchStatus.active) {
      setState(() {
        _isMovePending = false;
        _pendingCardId = null;
        _moveFeedback = null;
      });
      if (_connectionFeedbackTracker.hasActiveConnectedBaseline) {
        unawaited(
          _feedbackService.reconnect(GameReconnectFeedback.reconnecting),
        );
      }
      _reconnectCoordinator.start(
        gracePeriodMs: _connectionState?.disconnectGraceMs ?? 30000,
      );
      return;
    }

    unawaited(_recoverOutsideActiveMatch());
  }

  Future<void> _recoverOutsideActiveMatch() async {
    if ((_matchId ?? _joiningMatchId) == null) {
      if (mounted && !_isDisposing) {
        setState(() {
          _ticket = null;
          _errorMessage =
              'Connection lost while matchmaking. Return and try again.';
          _status = PlayQueueStatus.failed;
        });
      }
      return;
    }
    try {
      await _attemptMatchRecovery();
    } catch (_) {
      if (mounted && !_isDisposing) {
        _setFailure('Could not reconnect to the match.');
      }
    }
  }

  void _handleReconnectCoordinatorChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _startMatchmaking() async {
    final matchmakingGeneration = ++_matchmakingGeneration;
    try {
      final socket = widget.nakamaService.realtimeSocket(widget.nakamaSession);
      _socket = socket;

      // Subscribe before matchmaking so a fast match-started message cannot be
      // missed while joinMatch is still completing.
      _subscribeToMatchData(socket);

      // Nakama sends this event when the server finds enough compatible players.
      _matchmakerSubscription = socket.onMatchmakerMatched.listen(
        _handleMatchmakerMatched,
        onError: (error) {
          if (_isDisposing ||
              !mounted ||
              matchmakingGeneration != _matchmakingGeneration ||
              !identical(socket, _socket)) {
            return;
          }
          _setFailure('Matchmaker stream failed: $error');
        },
      );

      final ticket = await widget.nakamaService.joinQuickplayQueue(socket);

      if (_isDisposing ||
          !mounted ||
          matchmakingGeneration != _matchmakingGeneration) {
        await _removeStaleMatchmakerTicket(socket, ticket.ticket);
        return;
      }
      setState(() {
        // A very fast matchmaker event can arrive before addMatchmaker's Future
        // completes. Do not move an already joining/ready page backwards.
        if (_status == PlayQueueStatus.connecting) {
          _ticket = ticket.ticket;
          _status = PlayQueueStatus.searching;
        }
      });
    } catch (error) {
      if (_isDisposing ||
          !mounted ||
          matchmakingGeneration != _matchmakingGeneration) {
        return;
      }
      debugPrint('Could not start matchmaking: $error');
      _setFailure('Could not start matchmaking.');
    }
  }

  Future<void> _joinDirectMatch(String matchId) async {
    final joinGeneration = ++_joinGeneration;
    try {
      final socket = widget.nakamaService.realtimeSocket(widget.nakamaSession);
      _socket = socket;
      _joiningMatchId = matchId;

      // Subscribe before joining so a fast match-started message cannot be
      // missed while joinAuthoritativeMatch is still completing.
      _subscribeToMatchData(socket);

      if (!mounted) return;
      setState(() {
        _status = PlayQueueStatus.joiningMatch;
      });

      final match = await widget.nakamaService.joinAuthoritativeMatch(
        socket: socket,
        matchId: matchId,
      );

      if (!_isJoinCurrent(joinGeneration)) {
        await _releaseStaleJoinedMatch(socket, match.matchId);
        return;
      }
      setState(() {
        _matchId = match.matchId;
        _joiningMatchId = null;
        if (_gameState == null) {
          _status = PlayQueueStatus.waitingForInitialState;
        }
      });
    } catch (error) {
      if (!_isJoinCurrent(joinGeneration)) return;
      _joiningMatchId = null;
      debugPrint('Could not join match: $error');
      _setFailure('Could not join the match.');
    }
  }

  Future<void> _attemptMatchRecovery() async {
    final matchId = _matchId ?? _joiningMatchId;
    if (!mounted || matchId == null) return;

    final previousJoin = _reconnectJoinSucceededAtMs;
    if (previousJoin != null &&
        _monotonicClock.elapsedMilliseconds - previousJoin < 3000) {
      return;
    }

    final socket = widget.nakamaService.realtimeSocket(widget.nakamaSession);
    if (!identical(socket, _socket)) {
      _matchDataGeneration += 1;
      await _matchDataSubscription?.cancel();
      if (_isDisposing || !mounted) return;
      _socket = socket;
      _subscribeToMatchData(socket);
    } else {
      _socket = socket;
    }
    _joiningMatchId = matchId;
    final joinGeneration = ++_joinGeneration;

    try {
      final match = await widget.nakamaService.joinAuthoritativeMatch(
        socket: socket,
        matchId: matchId,
      );

      if (!_isJoinCurrent(joinGeneration)) {
        await _releaseStaleJoinedMatch(socket, match.matchId);
        return;
      }
      _reconnectJoinSucceededAtMs = _monotonicClock.elapsedMilliseconds;
      setState(() {
        _matchId = match.matchId;
        _joiningMatchId = null;
        // Keep an existing arena visible while the targeted authoritative
        // resync arrives. Queue/loading screens still show reconnect status.
        if (_gameState == null) {
          _status = PlayQueueStatus.waitingForInitialState;
        }
      });
    } catch (error) {
      if (!_isJoinCurrent(joinGeneration)) return;
      _reconnectJoinSucceededAtMs = null;
      _joiningMatchId = null;
      debugPrint('Could not reconnect to match: $error');
      rethrow;
    }
  }

  Future<void> _cancelMatchRecoveryAttempt() async {
    _joinGeneration += 1;
    _matchDataGeneration += 1;
    _reconnectJoinSucceededAtMs = null;
    await _matchDataSubscription?.cancel();
    _matchDataSubscription = null;
    final socket = _socket;
    await widget.nakamaService.closeRealtimeSocket();
    if (identical(_socket, socket)) _socket = null;
  }

  Future<void> _handleMatchmakerMatched(
    nakama.MatchmakerMatched matched,
  ) async {
    int? joinGeneration;
    try {
      if (!mounted || _matchmakerMatchHandled) return;

      // Because the backend registers a matchmaker hook, Nakama should return
      // an authoritative match id here instead of only a relayed match token.
      final matchId = matched.matchId;
      if (matchId == null || matchId.isEmpty) {
        throw Exception('Nakama did not return an authoritative match id');
      }

      final socket = _socket;
      if (socket == null) {
        throw Exception('Realtime socket is not connected');
      }

      _matchmakerMatchHandled = true;
      _matchmakingGeneration += 1;
      unawaited(_matchmakerSubscription?.cancel());
      _matchmakerSubscription = null;
      _ticket = null;
      joinGeneration = ++_joinGeneration;
      _joiningMatchId = matchId;
      setState(() {
        _matchedPlayerCount = matched.users.length;
        _status = PlayQueueStatus.joiningMatch;
      });

      final match = await widget.nakamaService.joinAuthoritativeMatch(
        socket: socket,
        matchId: matchId,
      );

      if (!_isJoinCurrent(joinGeneration)) {
        await _releaseStaleJoinedMatch(socket, match.matchId);
        return;
      }
      setState(() {
        _matchId = match.matchId;
        _joiningMatchId = null;
        // Opcode 10 can arrive before joinMatch's Future completes. Never move
        // a ready screen back to a loading state in that race.
        if (_gameState == null) {
          _status = PlayQueueStatus.waitingForInitialState;
        }
      });
    } catch (error) {
      if (_isDisposing ||
          !mounted ||
          (joinGeneration != null && joinGeneration != _joinGeneration)) {
        return;
      }
      _joiningMatchId = null;
      debugPrint('Could not join match: $error');
      _setFailure('Could not join the match.');
    }
  }

  void _handleMatchData(nakama.MatchData message) {
    final expectedMatchId = _matchId ?? _joiningMatchId;
    if (expectedMatchId == null || message.matchId != expectedMatchId) {
      debugPrint('Ignoring game data for an unexpected match.');
      return;
    }

    try {
      switch (message.opCode) {
        case GameServerOpcode.matchStarted:
          _applyAuthoritativeState(
            _messageDecoder.decodeGameState(message.data),
            startsNewRound: true,
          );
          break;
        case GameServerOpcode.stateUpdate:
        case GameServerOpcode.gameEnded:
          _applyAuthoritativeState(
            _messageDecoder.decodeGameState(message.data),
          );
          break;
        case GameServerOpcode.stuckReset:
          _applyAuthoritativeState(
            _messageDecoder.decodeGameState(message.data),
            isPileReset: true,
          );
          break;
        case GameServerOpcode.moveRejected:
          final rejection = _messageDecoder.decodeMoveRejected(message.data);
          if (!mounted) return;
          setState(() {
            _isMovePending = false;
            _pendingCardId = null;
            _moveFeedback = rejection.reason.displayMessage;
          });
          unawaited(_feedbackService.illegalMove());
          break;
        case GameServerOpcode.rematchStatus:
          final rematchStatus = _messageDecoder.decodeRematchStatus(
            message.data,
          );
          if (!mounted) return;
          _rematchResponseTimer?.cancel();
          setState(() {
            _rematchStatus = rematchStatus;
            _isRematchSubmitting = false;
          });
          break;
        case GameServerOpcode.connectionChanged:
          final connectionState = _messageDecoder.decodeConnectionChanged(
            message.data,
          );
          if (!mounted) return;
          final currentUserConnected = connectionState.isUserConnected(
            widget.nakamaSession.userId,
          );
          final disconnectDeadlineMs = connectionState.disconnectDeadlineMs;
          final connectionServerTimeMs = connectionState.serverTimeMs;
          if (_reconnectCoordinator.isActive &&
              !currentUserConnected &&
              disconnectDeadlineMs != null &&
              connectionServerTimeMs != null) {
            _reconnectCoordinator.reconcileDeadline(
              deadlineMs: disconnectDeadlineMs,
              serverTimeMs: connectionServerTimeMs,
              rttEstimateMs: _gameState?.myRttEstimateMs,
            );
          }
          final isConnected = connectionState.allPlayersConnected;
          final feedbackChange = _connectionFeedbackTracker.observe(
            connected: isConnected,
            matchActive: _gameState?.status == GameMatchStatus.active,
          );
          switch (feedbackChange) {
            case GameConnectionFeedbackChange.none:
              break;
            case GameConnectionFeedbackChange.reconnecting:
              unawaited(
                _feedbackService.reconnect(GameReconnectFeedback.reconnecting),
              );
            case GameConnectionFeedbackChange.restored:
              if (_reconnectCoordinator.status !=
                      MatchReconnectStatus.reconnecting &&
                  _reconnectCoordinator.status !=
                      MatchReconnectStatus.expired) {
                unawaited(
                  _feedbackService.reconnect(GameReconnectFeedback.restored),
                );
              }
          }
          setState(() {
            _connectionState = connectionState;
            if (!connectionState.allPlayersConnected) {
              _isMovePending = false;
              _pendingCardId = null;
            }
          });
          break;
        default:
          debugPrint('Ignoring server opcode ${message.opCode}.');
      }
    } on FormatException catch (error, stackTrace) {
      debugPrint(
        'Invalid payload for server opcode ${message.opCode}: '
        '$error\n$stackTrace',
      );
      _setFailure('The game server sent invalid game data.');
    }
  }

  void _applyAuthoritativeState(
    GameStateView gameState, {
    bool startsNewRound = false,
    bool isPileReset = false,
  }) {
    if (!mounted) return;

    final currentState = _gameState;
    if (!startsNewRound &&
        currentState != null &&
        gameState.stateVersion < currentState.stateVersion) {
      debugPrint(
        'Ignoring older game state version ${gameState.stateVersion}; '
        'current version is ${currentState.stateVersion}.',
      );
      return;
    }

    if (_reconnectCoordinator.status == MatchReconnectStatus.reconnecting ||
        _reconnectCoordinator.status == MatchReconnectStatus.expired) {
      _reconnectJoinSucceededAtMs = null;
      if (gameState.status == GameMatchStatus.active) {
        _reconnectCoordinator.markRestored();
        unawaited(_feedbackService.reconnect(GameReconnectFeedback.restored));
      } else {
        // A recovery attempt can return the authoritative terminal snapshot
        // after the grace window elapsed. That is a match result, not a
        // successful reconnection, so remove recovery UI without a false cue.
        _reconnectCoordinator.reset();
      }
    }

    final pendingCardWasPlayed =
        _pendingCardId != null &&
        !gameState.myHand.any((card) => card.cardId == _pendingCardId);
    final pendingMoveResolved =
        pendingCardWasPlayed || gameState.status == GameMatchStatus.finished;
    final hasNewPresentationVersion =
        startsNewRound ||
        currentState == null ||
        gameState.stateVersion > currentState.stateVersion;
    if (gameState.status == GameMatchStatus.active &&
        (_connectionState?.allPlayersConnected ?? true)) {
      _connectionFeedbackTracker.markActiveSnapshot(connected: true);
    }

    if (hasNewPresentationVersion) {
      for (final transition in gameState.transitions) {
        if (transition.actor == GameStateTransitionActor.opponent) {
          unawaited(_feedbackService.opponentMove());
        }
      }
    }
    if (isPileReset) {
      _pileResetTimer?.cancel();
      unawaited(_feedbackService.pileReset());
      _pileResetTimer = Timer(const Duration(milliseconds: 850), () {
        if (!mounted) return;
        setState(() => _pileResetActive = false);
      });
    }

    // Reaction time for the next move is measured from this moment (when the
    // client processed the state it will be reacting to), on this device's
    // own clock, so it needs no synchronization with the server clock.
    _lastAuthoritativeStateAtMs = _monotonicClock.elapsedMilliseconds;

    setState(() {
      _gameState = gameState;
      if (hasNewPresentationVersion && gameState.transitions.isNotEmpty) {
        _transitionSequence += 1;
      }
      if (isPileReset) {
        _pileResetSequence += 1;
        _pileResetActive = true;
      }
      _errorMessage = null;
      _moveFeedback = null;
      if (pendingMoveResolved) {
        _pendingCardId = null;
        _isMovePending = false;
      }
      _status = PlayQueueStatus.ready;
      if (startsNewRound) {
        _roundSequence += 1;
        _pileResetTimer?.cancel();
        _pileResetActive = false;
        _rematchResponseTimer?.cancel();
        _pendingCardId = null;
        _isMovePending = false;
        _moveFeedback = null;
        _rematchStatus = null;
        _isRematchSubmitting = false;
        _connectionFeedbackTracker.markActiveSnapshot(connected: true);
      }
    });
  }

  void _handleResultPresentationStarted() {
    final gameState = _gameState;
    if (!mounted || gameState?.status != GameMatchStatus.finished) return;
    if (_lastResultFeedbackRoundSequence == _roundSequence &&
        _lastResultFeedbackStateVersion == gameState!.stateVersion) {
      return;
    }
    _lastResultFeedbackRoundSequence = _roundSequence;
    _lastResultFeedbackStateVersion = gameState!.stateVersion;

    final winnerId = gameState.winnerId;
    if (winnerId == null) {
      unawaited(_feedbackService.neutralEnd());
    } else if (winnerId == widget.nakamaSession.userId) {
      unawaited(_feedbackService.win());
    } else {
      unawaited(_feedbackService.loss());
    }
  }

  void _sendRematchDecision(bool accept) {
    final socket = _socket;
    final matchId = _matchId ?? _joiningMatchId;
    if (socket == null || matchId == null || _isRematchSubmitting) return;

    setState(() {
      _isRematchSubmitting = true;
      _moveFeedback = null;
    });
    try {
      widget.nakamaService.sendRematchDecision(
        socket: socket,
        matchId: matchId,
        accept: accept,
      );
      _rematchResponseTimer?.cancel();
      _rematchResponseTimer = Timer(const Duration(seconds: 8), () {
        if (!mounted || !_isRematchSubmitting) return;
        setState(() {
          _isRematchSubmitting = false;
          _moveFeedback =
              'The server did not confirm the rematch request. Try again.';
        });
      });
    } catch (error) {
      debugPrint('Could not send rematch decision: $error');
      if (!mounted) return;
      setState(() {
        _isRematchSubmitting = false;
        _moveFeedback = 'Could not send the rematch decision.';
      });
    }
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

  void _submitMove(String cardId, GamePileId pileId) {
    final socket = _socket;
    final matchId = _matchId ?? _joiningMatchId;
    final gameState = _gameState;
    if (socket == null ||
        matchId == null ||
        gameState == null ||
        gameState.status != GameMatchStatus.active ||
        !(_connectionState?.allPlayersConnected ?? true) ||
        _reconnectCoordinator.status == MatchReconnectStatus.reconnecting ||
        _reconnectCoordinator.status == MatchReconnectStatus.expired ||
        _isMovePending) {
      return;
    }

    final lastStateAt = _lastAuthoritativeStateAtMs;
    final reactionTimeMs = lastStateAt == null
        ? null
        : _monotonicClock.elapsedMilliseconds - lastStateAt;

    setState(() {
      _isMovePending = true;
      _pendingCardId = cardId;
      _moveFeedback = null;
    });

    try {
      widget.nakamaService.submitMove(
        socket: socket,
        matchId: matchId,
        move: SubmitMovePayload(
          cardId: cardId,
          targetPileId: pileId,
          expectedStateVersion: gameState.stateVersion,
          reactionTimeMs: reactionTimeMs,
        ),
      );
    } catch (error) {
      debugPrint('Could not submit move: $error');
      if (!mounted) return;
      setState(() {
        _isMovePending = false;
        _pendingCardId = null;
        _moveFeedback = 'Could not send the move.';
      });
    }
  }

  Future<void> _cancelMatchmaking() async {
    final ticket = _ticket;
    final socket = _socket;

    if (ticket == null || socket == null) return;

    try {
      await widget.nakamaService.leaveQuickplayQueue(
        socket: socket,
        ticket: ticket,
      );
    } catch (error) {
      debugPrint('Could not cancel matchmaking ticket: $error');
    }
  }

  bool _isJoinCurrent(int generation) {
    return !_isDisposing && mounted && generation == _joinGeneration;
  }

  Future<void> _removeStaleMatchmakerTicket(
    nakama.NakamaWebsocketClient socket,
    String ticket,
  ) async {
    try {
      await widget.nakamaService.leaveQuickplayQueue(
        socket: socket,
        ticket: ticket,
      );
    } catch (error) {
      debugPrint('Could not remove stale matchmaking ticket: $error');
    }
  }

  Future<void> _releaseStaleJoinedMatch(
    nakama.NakamaWebsocketClient socket,
    String matchId,
  ) async {
    final currentMatchId = _matchId ?? _joiningMatchId;
    final membershipStillOwned =
        !_isDisposing &&
        mounted &&
        identical(socket, _socket) &&
        currentMatchId == matchId;
    if (membershipStillOwned) return;

    try {
      await widget.nakamaService.leaveAuthoritativeMatch(
        socket: socket,
        matchId: matchId,
      );
    } catch (error) {
      debugPrint('Could not release stale match join: $error');
    }
  }

  Future<void> _leaveMatchIfJoined() async {
    final matchId = _matchId ?? _joiningMatchId;
    final socket = _socket;

    if (matchId == null || socket == null) return;

    try {
      await widget.nakamaService.leaveAuthoritativeMatch(
        socket: socket,
        matchId: matchId,
      );
    } catch (error) {
      debugPrint('Could not leave match: $error');
    }
  }

  void _exitPlayPage() {
    final matchId = _matchId ?? _joiningMatchId;
    final gameState = _gameState;
    if (gameState?.status == GameMatchStatus.finished) {
      Navigator.of(context).pop(const PlayExitResult.matchFinished());
      return;
    }

    if (matchId != null && gameState?.status == GameMatchStatus.active) {
      Navigator.of(context).pop(PlayExitResult.disconnectedFromMatch(matchId));
      return;
    }

    Navigator.of(context).pop();
  }

  void _setFailure(String message) {
    debugPrint(message);
    if (!mounted) return;

    setState(() {
      _errorMessage = message;
      _status = PlayQueueStatus.failed;
    });
  }

  String get _title {
    switch (_status) {
      case PlayQueueStatus.connecting:
        return 'Connecting to game server';
      case PlayQueueStatus.searching:
        return 'Searching for opponent';
      case PlayQueueStatus.joiningMatch:
        return 'Joining match';
      case PlayQueueStatus.waitingForInitialState:
        return widget.displayCode != null
            ? 'Waiting for opponent'
            : 'Preparing game';
      case PlayQueueStatus.reconnecting:
        return 'Reconnecting to match';
      case PlayQueueStatus.ready:
        return 'Game ready';
      case PlayQueueStatus.failed:
        return 'Matchmaking failed';
    }
  }

  String get _subtitle {
    switch (_status) {
      case PlayQueueStatus.connecting:
        return 'Opening a realtime Nakama websocket...';
      case PlayQueueStatus.searching:
        return 'You are now waiting in the quickplay queue.';
      case PlayQueueStatus.joiningMatch:
        return 'An opponent was found. Joining the authoritative match...';
      case PlayQueueStatus.waitingForInitialState:
        return widget.displayCode != null
            ? 'Share the code below with your opponent to start the match.'
            : 'Waiting for Nakama to send your private starting hand.';
      case PlayQueueStatus.reconnecting:
        return 'Restoring your authoritative game state...';
      case PlayQueueStatus.ready:
        return 'Your authoritative game state has arrived.';
      case PlayQueueStatus.failed:
        return _errorMessage ?? 'Something went wrong.';
    }
  }

  Widget _buildStatusIcon() {
    switch (_status) {
      case PlayQueueStatus.connecting:
      case PlayQueueStatus.searching:
      case PlayQueueStatus.joiningMatch:
      case PlayQueueStatus.waitingForInitialState:
      case PlayQueueStatus.reconnecting:
        return const SizedBox.square(
          dimension: 34,
          child: CircularProgressIndicator(strokeWidth: 3),
        );
      case PlayQueueStatus.ready:
        return Icon(Icons.check_circle, size: 44, color: Colors.green.shade700);
      case PlayQueueStatus.failed:
        return Icon(
          Icons.error,
          size: 44,
          color: Theme.of(context).colorScheme.error,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = _gameState;
    final connectionState = _connectionState;
    final gameFinished = gameState?.status == GameMatchStatus.finished;
    final localReconnectStatus = _reconnectCoordinator.status;
    final localReconnecting =
        localReconnectStatus == MatchReconnectStatus.reconnecting ||
        localReconnectStatus == MatchReconnectStatus.expired;
    final movesEnabled =
        (connectionState?.allPlayersConnected ?? true) && !localReconnecting;
    final currentUserConnected =
        connectionState?.isUserConnected(widget.nakamaSession.userId) ?? true;
    final connectionMessage =
        gameFinished || (movesEnabled && !localReconnecting)
        ? null
        : localReconnecting
        ? localReconnectStatus == MatchReconnectStatus.expired
              ? 'The reconnection window elapsed.'
              : 'Connection lost. Reconnecting automatically...'
        : currentUserConnected
        ? 'Opponent disconnected. Waiting for reconnection...'
        : 'You are disconnected. Reconnecting...';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitPlayPage();
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
                child: _status == PlayQueueStatus.ready && gameState != null
                    ? GameStatePanel(
                        gameState: gameState,
                        currentUserId: widget.nakamaSession.userId,
                        onSubmitMove: _submitMove,
                        onBack: _exitPlayPage,
                        onViewProfile:
                            gameState.status == GameMatchStatus.finished
                            ? () => Navigator.of(
                                context,
                              ).pop(const PlayExitResult.viewProfile())
                            : null,
                        rematchStatus: _rematchStatus,
                        isRematchSubmitting: _isRematchSubmitting,
                        onRematchDecision: _sendRematchDecision,
                        isSubmitting: _isMovePending,
                        feedbackMessage: _moveFeedback,
                        movesEnabled: movesEnabled,
                        connectionMessage: connectionMessage,
                        pendingCardId: _pendingCardId,
                        transitions: gameState.transitions,
                        transitionSequence: _transitionSequence,
                        transitionRoundSequence: _roundSequence,
                        pileResetSequence: _pileResetSequence,
                        pileResetActive: _pileResetActive,
                        disconnectDeadlineMs:
                            connectionState?.disconnectDeadlineMs,
                        connectionServerTimeMs: connectionState?.serverTimeMs,
                        myRttEstimateMs: gameState.myRttEstimateMs,
                        rttSampleSequence: gameState.myRttSampleSequence ?? 0,
                        localReconnectRemainingSeconds: localReconnecting
                            ? _reconnectCoordinator.remainingSeconds
                            : null,
                        localReconnectExpired:
                            localReconnectStatus ==
                            MatchReconnectStatus.expired,
                        onRetryReconnect: () =>
                            unawaited(_reconnectCoordinator.retryNow()),
                        onReturnToMenu: _exitPlayPage,
                        onIllegalMoveFeedback: () =>
                            unawaited(_feedbackService.illegalMove()),
                        onResultPresentationStarted:
                            _handleResultPresentationStarted,
                      )
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Spacer(),
                            Center(child: _buildStatusIcon()),
                            const SizedBox(height: 24),
                            Text(
                              _title,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _subtitle,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 32),
                            if (widget.displayCode != null) ...[
                              _MatchCodeDisplay(code: widget.displayCode!),
                              const SizedBox(height: 32),
                            ],
                            if (_ticket != null)
                              _InfoRow(label: 'Queue ticket', value: _ticket!),
                            if (_matchId != null)
                              _InfoRow(label: 'Match id', value: _matchId!),
                            if (_matchedPlayerCount > 0)
                              _InfoRow(
                                label: 'Players matched',
                                value: _matchedPlayerCount.toString(),
                              ),
                            const Spacer(),
                            OutlinedButton.icon(
                              onPressed: _exitPlayPage,
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Back'),
                            ),
                          ],
                        ),
                      ),
              ),
              if (_rematchStatus case final roundStart?
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
