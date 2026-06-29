import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nakama/nakama.dart' as nakama;

import '../config/game_protocol.dart';
import '../models/game/game_state_view.dart';
import '../services/game_message_decoder.dart';
import '../services/nakama_service.dart';
import '../widgets/game_state_panel.dart';

enum PlayQueueStatus {
  connecting,
  searching,
  joiningMatch,
  waitingForInitialState,
  ready,
  failed,
}

class PlayPage extends StatefulWidget {
  const PlayPage({
    super.key,
    required this.nakamaService,
    required this.nakamaSession,
  });

  final NakamaService nakamaService;
  final nakama.Session nakamaSession;

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  static const _messageDecoder = GameMessageDecoder();

  PlayQueueStatus _status = PlayQueueStatus.connecting;
  StreamSubscription<nakama.MatchmakerMatched>? _matchmakerSubscription;
  StreamSubscription<nakama.MatchData>? _matchDataSubscription;
  nakama.NakamaWebsocketClient? _socket;
  GameStateView? _gameState;
  String? _ticket;
  String? _joiningMatchId;
  String? _matchId;
  String? _errorMessage;
  int _matchedPlayerCount = 0;

  @override
  void initState() {
    super.initState();
    _startMatchmaking();
  }

  @override
  void dispose() {
    unawaited(_matchDataSubscription?.cancel());
    unawaited(_matchmakerSubscription?.cancel());
    unawaited(_cancelMatchmaking());
    unawaited(_leaveMatchIfJoined());
    super.dispose();
  }

  Future<void> _startMatchmaking() async {
    try {
      final socket = widget.nakamaService.realtimeSocket(widget.nakamaSession);
      _socket = socket;

      // Subscribe before matchmaking so a fast match-started message cannot be
      // missed while joinMatch is still completing.
      _matchDataSubscription = socket.onMatchData.listen(
        _handleMatchData,
        onError: (Object error) {
          _setFailure('The game message stream stopped unexpectedly.');
          debugPrint('Match data stream failed: $error');
        },
      );

      // Nakama sends this event when the server finds enough compatible players.
      _matchmakerSubscription = socket.onMatchmakerMatched.listen(
        _handleMatchmakerMatched,
        onError: (error) {
          _setFailure('Matchmaker stream failed: $error');
        },
      );

      final ticket = await widget.nakamaService.joinQuickplayQueue(socket);

      if (!mounted) return;
      setState(() {
        // A very fast matchmaker event can arrive before addMatchmaker's Future
        // completes. Do not move an already joining/ready page backwards.
        if (_status == PlayQueueStatus.connecting) {
          _ticket = ticket.ticket;
          _status = PlayQueueStatus.searching;
        }
      });
    } catch (error) {
      debugPrint('Could not start matchmaking: $error');
      _setFailure('Could not start matchmaking.');
    }
  }

  Future<void> _handleMatchmakerMatched(
    nakama.MatchmakerMatched matched,
  ) async {
    try {
      if (!mounted) return;

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

      _joiningMatchId = matchId;
      setState(() {
        _ticket = null;
        _matchedPlayerCount = matched.users.length;
        _status = PlayQueueStatus.joiningMatch;
      });

      final match = await widget.nakamaService.joinAuthoritativeMatch(
        socket: socket,
        matchId: matchId,
      );

      if (!mounted) return;
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
      _joiningMatchId = null;
      debugPrint('Could not join match: $error');
      _setFailure('Could not join the match.');
    }
  }

  void _handleMatchData(nakama.MatchData message) {
    if (message.opCode != GameServerOpcode.matchStarted) {
      debugPrint('Ignoring server opcode ${message.opCode} in Step 4.');
      return;
    }

    final expectedMatchId = _matchId ?? _joiningMatchId;
    if (expectedMatchId == null || message.matchId != expectedMatchId) {
      debugPrint('Ignoring matchStarted data for an unexpected match.');
      return;
    }

    try {
      final gameState = _messageDecoder.decodeGameState(message.data);
      if (!mounted) return;

      setState(() {
        _gameState = gameState;
        _errorMessage = null;
        _status = PlayQueueStatus.ready;
      });
    } on FormatException catch (error, stackTrace) {
      debugPrint('Invalid matchStarted payload: $error\n$stackTrace');
      _setFailure('The game server sent invalid initialization data.');
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
        return 'Preparing game';
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
        return 'Waiting for Nakama to send your private starting hand.';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Play')),
      body: SafeArea(
        child: _status == PlayQueueStatus.ready && gameState != null
            ? GameStatePanel(
                gameState: gameState,
                onBack: () => Navigator.of(context).pop(),
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
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                  ],
                ),
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
