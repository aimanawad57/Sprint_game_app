import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nakama/nakama.dart' as nakama;

import '../config/game_protocol.dart';
import '../models/game/game_connection.dart';
import '../models/game/game_move.dart';
import '../models/game/game_state_transition.dart';
import '../models/game/game_state_view.dart';
import '../models/game/rematch_status.dart';
import '../models/play_exit_action.dart';
import '../services/game_connection_feedback_tracker.dart';
import '../services/game_feedback_service.dart';
import '../services/game_message_decoder.dart';
import '../services/match_reconnect_coordinator.dart';
import '../services/nakama_service.dart';
import '../services/resumable_match_store.dart';

enum GameSessionPhase {
  idle,
  connecting,
  queueing,
  joining,
  waiting,
  active,
  reconnecting,
  finished,
  abandoned,
  failed,
}

/// Owns one realtime game session independently from widget lifecycle.
///
/// Server state is always applied immediately. Presentation metadata remains
/// observable but never delays networking, authoritative state, or legal input.
class GameSessionController extends ChangeNotifier {
  GameSessionController({
    required this.nakamaService,
    required this.session,
    required this.feedbackService,
    this.directMatchId,
    this.displayCode,
    ResumableMatchStore? resumableMatchStore,
  }) {
    _resumableMatchStore =
        resumableMatchStore ??
        SharedPreferencesResumableMatchStore(userId: session.userId);
    _reconnectCoordinator = MatchReconnectCoordinator(
      attempt: _attemptMatchRecovery,
      cancelAttempt: _cancelMatchRecoveryAttempt,
    )..addListener(_handleReconnectCoordinatorChanged);
  }

  final NakamaService nakamaService;
  final nakama.Session session;
  final GameFeedbackService feedbackService;
  late final ResumableMatchStore _resumableMatchStore;

  /// When set, the page joins this match directly instead of using the
  /// quickplay matchmaker. Used by the create/join-by-code flow.
  final String? directMatchId;

  /// A code to show while waiting for the opponent to redeem it. Only
  /// meaningful when this client created the match (paired with
  /// [directMatchId]).
  final String? displayCode;

  static const _messageDecoder = GameMessageDecoder();
  static final Stopwatch _monotonicClock = Stopwatch()..start();

  GameSessionPhase _phase = GameSessionPhase.idle;
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
  bool _isDisposing = false;
  bool _started = false;
  bool _matchmakerMatchHandled = false;
  Future<void> _resumableStoreOperation = Future<void>.value();
  String? _scheduledResumableMatchId;
  bool _hasScheduledResumableValue = false;

  /// Monotonic instant when the most recent authoritative state was applied.
  /// Anchors the reaction-time measurement sent with the next move without
  /// being affected by wall-clock corrections.
  int? _lastAuthoritativeStateAtMs;

  bool get mounted => !_isDisposing;

  void _mutate(VoidCallback update) {
    if (!mounted) return;
    update();
    notifyListeners();
  }

  void start() {
    if (_started || _isDisposing) return;
    _started = true;
    _phase = GameSessionPhase.connecting;
    notifyListeners();
    _socketDisconnectSubscription = nakamaService.realtimeDisconnects.listen(
      (_) => _handleRealtimeDisconnect(),
    );

    final directMatchId = this.directMatchId;
    if (directMatchId != null) {
      unawaited(_joinDirectMatch(directMatchId));
    } else {
      unawaited(_startMatchmaking());
    }
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
      _mutate(() {
        _phase = GameSessionPhase.reconnecting;
        _isMovePending = false;
        _pendingCardId = null;
        _moveFeedback = null;
      });
      if (_connectionFeedbackTracker.hasActiveConnectedBaseline) {
        unawaited(
          feedbackService.reconnect(GameReconnectFeedback.reconnecting),
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
        _mutate(() {
          _ticket = null;
          _errorMessage =
              'Connection lost while matchmaking. Return and try again.';
          _phase = GameSessionPhase.failed;
        });
      }
      return;
    }
    _mutate(() => _phase = GameSessionPhase.reconnecting);
    try {
      await _attemptMatchRecovery();
    } catch (_) {
      if (mounted && !_isDisposing) {
        _setFailure('Could not reconnect to the match.');
      }
    }
  }

  void _handleReconnectCoordinatorChanged() {
    if (mounted) _mutate(() {});
  }

  Future<void> _startMatchmaking() async {
    final matchmakingGeneration = ++_matchmakingGeneration;
    try {
      final socket = nakamaService.realtimeSocket(session);
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

      final ticket = await nakamaService.joinQuickplayQueue(socket);

      if (_isDisposing ||
          !mounted ||
          matchmakingGeneration != _matchmakingGeneration) {
        await _removeStaleMatchmakerTicket(socket, ticket.ticket);
        return;
      }
      _mutate(() {
        // A very fast matchmaker event can arrive before addMatchmaker's Future
        // completes. Do not move an already joining/ready page backwards.
        if (_phase == GameSessionPhase.connecting) {
          _ticket = ticket.ticket;
          _phase = GameSessionPhase.queueing;
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
      final socket = nakamaService.realtimeSocket(session);
      _socket = socket;
      _joiningMatchId = matchId;

      // Subscribe before joining so a fast match-started message cannot be
      // missed while joinAuthoritativeMatch is still completing.
      _subscribeToMatchData(socket);

      if (!mounted) return;
      _mutate(() {
        _phase = GameSessionPhase.joining;
      });

      final match = await nakamaService.joinAuthoritativeMatch(
        socket: socket,
        matchId: matchId,
      );

      if (!_isJoinCurrent(joinGeneration)) {
        await _releaseStaleJoinedMatch(socket, match.matchId);
        return;
      }
      _mutate(() {
        _matchId = match.matchId;
        _joiningMatchId = null;
        if (_gameState == null) {
          _phase = GameSessionPhase.waiting;
        }
      });
      _saveResumableMatch(match.matchId);
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

    final socket = nakamaService.realtimeSocket(session);
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
      final match = await nakamaService.joinAuthoritativeMatch(
        socket: socket,
        matchId: matchId,
      );

      if (!_isJoinCurrent(joinGeneration)) {
        await _releaseStaleJoinedMatch(socket, match.matchId);
        return;
      }
      _reconnectJoinSucceededAtMs = _monotonicClock.elapsedMilliseconds;
      _mutate(() {
        _matchId = match.matchId;
        _joiningMatchId = null;
        // Keep an existing arena visible while the targeted authoritative
        // resync arrives. Queue/loading screens still show reconnect status.
        if (_gameState == null) {
          _phase = GameSessionPhase.waiting;
        }
      });
      _saveResumableMatch(match.matchId);
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
    await nakamaService.closeRealtimeSocket();
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
      _mutate(() {
        _matchedPlayerCount = matched.users.length;
        _phase = GameSessionPhase.joining;
      });

      final match = await nakamaService.joinAuthoritativeMatch(
        socket: socket,
        matchId: matchId,
      );

      if (!_isJoinCurrent(joinGeneration)) {
        await _releaseStaleJoinedMatch(socket, match.matchId);
        return;
      }
      _mutate(() {
        _matchId = match.matchId;
        _joiningMatchId = null;
        // Opcode 10 can arrive before joinMatch's Future completes. Never move
        // a ready screen back to a loading state in that race.
        if (_gameState == null) {
          _phase = GameSessionPhase.waiting;
        }
      });
      _saveResumableMatch(match.matchId);
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
          _mutate(() {
            _isMovePending = false;
            _pendingCardId = null;
            _moveFeedback = rejection.reason.displayMessage;
          });
          unawaited(feedbackService.illegalMove());
          break;
        case GameServerOpcode.rematchStatus:
          final rematchStatus = _messageDecoder.decodeRematchStatus(
            message.data,
          );
          if (!mounted) return;
          _rematchResponseTimer?.cancel();
          _mutate(() {
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
            session.userId,
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
                feedbackService.reconnect(GameReconnectFeedback.reconnecting),
              );
            case GameConnectionFeedbackChange.restored:
              if (_reconnectCoordinator.status !=
                      MatchReconnectStatus.reconnecting &&
                  _reconnectCoordinator.status !=
                      MatchReconnectStatus.expired) {
                unawaited(
                  feedbackService.reconnect(GameReconnectFeedback.restored),
                );
              }
          }
          _mutate(() {
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
        unawaited(feedbackService.reconnect(GameReconnectFeedback.restored));
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
          unawaited(feedbackService.opponentMove());
        }
      }
    }
    if (isPileReset) {
      _pileResetTimer?.cancel();
      unawaited(feedbackService.pileReset());
      _pileResetTimer = Timer(const Duration(milliseconds: 850), () {
        if (!mounted) return;
        _mutate(() => _pileResetActive = false);
      });
    }

    // Reaction time for the next move is measured from this moment (when the
    // client processed the state it will be reacting to), on this device's
    // own clock, so it needs no synchronization with the server clock.
    _lastAuthoritativeStateAtMs = _monotonicClock.elapsedMilliseconds;

    _mutate(() {
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
      _phase = switch (gameState.status) {
        GameMatchStatus.finished
            when gameState.endReason == GameMatchEndReason.abandoned =>
          GameSessionPhase.abandoned,
        GameMatchStatus.finished => GameSessionPhase.finished,
        GameMatchStatus.active => GameSessionPhase.active,
        GameMatchStatus.waiting => GameSessionPhase.waiting,
      };
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

    final currentMatchId = _matchId ?? _joiningMatchId;
    if (gameState.status == GameMatchStatus.finished) {
      _clearResumableMatch();
    } else if (currentMatchId != null) {
      _saveResumableMatch(currentMatchId);
    }
  }

  void _saveResumableMatch(String matchId) {
    if (_hasScheduledResumableValue && _scheduledResumableMatchId == matchId) {
      return;
    }
    _hasScheduledResumableValue = true;
    _scheduledResumableMatchId = matchId;
    _queueResumableStoreOperation(() => _resumableMatchStore.save(matchId));
  }

  void _clearResumableMatch() {
    if (_hasScheduledResumableValue && _scheduledResumableMatchId == null) {
      return;
    }
    _hasScheduledResumableValue = true;
    _scheduledResumableMatchId = null;
    _queueResumableStoreOperation(_resumableMatchStore.clear);
  }

  void _queueResumableStoreOperation(Future<void> Function() operation) {
    _resumableStoreOperation = _resumableStoreOperation
        .catchError((Object _) {})
        .then((_) => operation())
        .catchError((Object error) {
          debugPrint('Could not update resumable match storage: $error');
        });
    unawaited(_resumableStoreOperation);
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
      unawaited(feedbackService.neutralEnd());
    } else if (winnerId == session.userId) {
      unawaited(feedbackService.win());
    } else {
      unawaited(feedbackService.loss());
    }
  }

  void _sendRematchDecision(bool accept) {
    final socket = _socket;
    final matchId = _matchId ?? _joiningMatchId;
    if (socket == null || matchId == null || _isRematchSubmitting) return;

    _mutate(() {
      _isRematchSubmitting = true;
      _moveFeedback = null;
    });
    try {
      nakamaService.sendRematchDecision(
        socket: socket,
        matchId: matchId,
        accept: accept,
      );
      _rematchResponseTimer?.cancel();
      _rematchResponseTimer = Timer(const Duration(seconds: 8), () {
        if (!mounted || !_isRematchSubmitting) return;
        _mutate(() {
          _isRematchSubmitting = false;
          _moveFeedback =
              'The server did not confirm the rematch request. Try again.';
        });
      });
    } catch (error) {
      debugPrint('Could not send rematch decision: $error');
      if (!mounted) return;
      _mutate(() {
        _isRematchSubmitting = false;
        _moveFeedback = 'Could not send the rematch decision.';
      });
    }
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

    _mutate(() {
      _isMovePending = true;
      _pendingCardId = cardId;
      _moveFeedback = null;
    });

    try {
      nakamaService.submitMove(
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
      _mutate(() {
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
      await nakamaService.leaveQuickplayQueue(socket: socket, ticket: ticket);
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
      await nakamaService.leaveQuickplayQueue(socket: socket, ticket: ticket);
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
      await nakamaService.leaveAuthoritativeMatch(
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
      await nakamaService.leaveAuthoritativeMatch(
        socket: socket,
        matchId: matchId,
      );
    } catch (error) {
      debugPrint('Could not leave match: $error');
    }
  }

  PlayExitResult? get exitResult {
    final matchId = _matchId ?? _joiningMatchId;
    final gameState = _gameState;
    if (gameState?.status == GameMatchStatus.finished) {
      return const PlayExitResult.matchFinished();
    }

    if (matchId != null && gameState?.status != GameMatchStatus.finished) {
      return PlayExitResult.disconnectedFromMatch(matchId);
    }

    return null;
  }

  void _setFailure(String message) {
    debugPrint(message);
    if (!mounted) return;

    _mutate(() {
      _errorMessage = message;
      _phase = GameSessionPhase.failed;
    });
  }

  String get title {
    switch (_phase) {
      case GameSessionPhase.idle:
        return 'Preparing game session';
      case GameSessionPhase.connecting:
        return 'Connecting to game server';
      case GameSessionPhase.queueing:
        return 'Searching for opponent';
      case GameSessionPhase.joining:
        return 'Joining match';
      case GameSessionPhase.waiting:
        return displayCode != null ? 'Waiting for opponent' : 'Preparing game';
      case GameSessionPhase.reconnecting:
        return 'Reconnecting to match';
      case GameSessionPhase.active:
        return 'Game ready';
      case GameSessionPhase.finished:
        return 'Game finished';
      case GameSessionPhase.abandoned:
        return 'Match ended';
      case GameSessionPhase.failed:
        return 'Matchmaking failed';
    }
  }

  String get subtitle {
    switch (_phase) {
      case GameSessionPhase.idle:
        return 'Preparing the realtime session.';
      case GameSessionPhase.connecting:
        return 'Opening a realtime Nakama websocket...';
      case GameSessionPhase.queueing:
        return 'You are now waiting in the quickplay queue.';
      case GameSessionPhase.joining:
        return 'An opponent was found. Joining the authoritative match...';
      case GameSessionPhase.waiting:
        return displayCode != null
            ? 'Share the code below with your opponent to start the match.'
            : 'Waiting for Nakama to send your private starting hand.';
      case GameSessionPhase.reconnecting:
        return 'Restoring your authoritative game state...';
      case GameSessionPhase.active:
        return 'Your authoritative game state has arrived.';
      case GameSessionPhase.finished:
        return 'The authoritative match has finished.';
      case GameSessionPhase.abandoned:
        return 'The match ended without a normal result.';
      case GameSessionPhase.failed:
        return _errorMessage ?? 'Something went wrong.';
    }
  }

  GameSessionPhase get phase => _phase;
  GameStateView? get gameState => _gameState;
  GameConnectionView? get connectionState => _connectionState;
  RematchStatusView? get rematchStatus => _rematchStatus;
  MatchReconnectStatus get reconnectStatus => _reconnectCoordinator.status;
  int get reconnectRemainingSeconds => _reconnectCoordinator.remainingSeconds;
  String? get ticket => _ticket;
  String? get matchId => _matchId;
  String? get moveFeedback => _moveFeedback;
  String? get pendingCardId => _pendingCardId;
  bool get isMovePending => _isMovePending;
  bool get isRematchSubmitting => _isRematchSubmitting;
  int get matchedPlayerCount => _matchedPlayerCount;
  int get transitionSequence => _transitionSequence;
  int get roundSequence => _roundSequence;
  int get pileResetSequence => _pileResetSequence;
  bool get pileResetActive => _pileResetActive;

  bool get localReconnecting =>
      reconnectStatus == MatchReconnectStatus.reconnecting ||
      reconnectStatus == MatchReconnectStatus.expired;

  bool get movesEnabled =>
      (_connectionState?.allPlayersConnected ?? true) && !localReconnecting;

  String? get connectionMessage {
    final state = _gameState;
    if (state?.status == GameMatchStatus.finished ||
        (movesEnabled && !localReconnecting)) {
      return null;
    }
    if (localReconnecting) {
      return reconnectStatus == MatchReconnectStatus.expired
          ? 'The reconnection window elapsed.'
          : 'Connection lost. Reconnecting automatically...';
    }
    final currentUserConnected =
        _connectionState?.isUserConnected(session.userId) ?? true;
    return currentUserConnected
        ? 'Opponent disconnected. Waiting for reconnection...'
        : 'You are disconnected. Reconnecting...';
  }

  void submitMove(String cardId, GamePileId pileId) =>
      _submitMove(cardId, pileId);
  void sendRematchDecision(bool accept) => _sendRematchDecision(accept);
  void handleResultPresentationStarted() => _handleResultPresentationStarted();
  Future<void> retryReconnect() => _reconnectCoordinator.retryNow();

  @visibleForTesting
  void applyAuthoritativeStateForTesting(
    GameStateView state, {
    bool startsNewRound = false,
    bool isPileReset = false,
  }) {
    _applyAuthoritativeState(
      state,
      startsNewRound: startsNewRound,
      isPileReset: isPileReset,
    );
  }
}
