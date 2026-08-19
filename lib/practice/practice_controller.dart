import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../gameplay/game_rules.dart';
import '../models/game/game_card.dart';
import '../models/game/game_move.dart';
import '../models/game/game_state_transition.dart';
import '../models/game/game_state_view.dart';
import 'local_game_rules.dart'
    show
        drawReplacement,
        handHasLegalMove,
        playerHasWon,
        shuffledCards,
        sprintCardCatalog;

enum PracticeEventType { cardPlayed, replacementDrawn, pilesReset, matchEnded }

class PracticeEvent {
  const PracticeEvent(this.type, this.message, {this.transition});

  final PracticeEventType type;
  final String message;
  final GameStateTransition? transition;
}

class PracticeController extends ChangeNotifier {
  PracticeController({Random? random, Duration? botThinkDelay})
    : _random = random ?? Random(),
      _botThinkDelay = botThinkDelay {
    restart();
  }

  static const playerId = 'practice-player';
  static const botId = 'practice-bot';
  final Random _random;
  final Duration? _botThinkDelay;
  final _events = StreamController<PracticeEvent>.broadcast();
  final _playerHand = <GameCard>[];
  final _playerDeck = <GameCard>[];
  final _botHand = <GameCard>[];
  final _botDeck = <GameCard>[];
  final _pile1 = <GameCard>[];
  final _pile2 = <GameCard>[];
  Timer? _botTimer;
  Timer? _clockTimer;
  late DateTime _startedAt;
  int _version = 1;
  String? _winnerId;
  bool _disposed = false;
  bool botThinking = false;
  String? feedback;

  Stream<PracticeEvent> get events => _events.stream;
  bool get finished => _winnerId != null;

  GameStateView get state => GameStateView(
    stateVersion: _version,
    status: finished ? GameMatchStatus.finished : GameMatchStatus.active,
    elapsedTimeMs: DateTime.now().difference(_startedAt).inMilliseconds,
    myHand: _playerHand,
    myDeckCount: _playerDeck.length,
    opponentHandCount: _botHand.length,
    opponentDeckCount: _botDeck.length,
    pile1: CenterPileView(topCard: _pile1.last),
    pile2: CenterPileView(topCard: _pile2.last),
    winnerId: _winnerId,
    winnerName: _winnerId == playerId
        ? 'You'
        : _winnerId == botId
        ? 'Practice Bot'
        : null,
    endReason: finished ? GameMatchEndReason.normal : null,
  );

  void restart() {
    _botTimer?.cancel();
    _clockTimer?.cancel();
    final cards = shuffledCards(sprintCardCatalog, _random);
    _playerHand
      ..clear()
      ..addAll(cards.sublist(26, 29));
    _playerDeck
      ..clear()
      ..addAll(cards.sublist(0, 26));
    _botHand
      ..clear()
      ..addAll(cards.sublist(55, 58));
    _botDeck
      ..clear()
      ..addAll(cards.sublist(29, 55));
    _pile1
      ..clear()
      ..add(cards[58]);
    _pile2
      ..clear()
      ..add(cards[59]);
    _version = 1;
    _winnerId = null;
    feedback = null;
    botThinking = false;
    _startedAt = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_disposed && !finished) notifyListeners();
    });
    _resolveStuck();
    _scheduleBot();
    notifyListeners();
  }

  bool play(String cardId, GamePileId pileId) {
    if (finished) return false;
    final index = _playerHand.indexWhere((card) => card.cardId == cardId);
    if (index < 0) return false;
    final top = pileId == GamePileId.pile1 ? _pile1.last : _pile2.last;
    final legality = evaluateCardPlay(_playerHand[index], top);
    if (!legality.isLegal) {
      feedback = legality.feedbackMessage;
      notifyListeners();
      return false;
    }
    feedback = null;
    final card = _playerHand.removeAt(index);
    (pileId == GamePileId.pile1 ? _pile1 : _pile2).add(card);
    _version++;
    _emit(
      PracticeEventType.cardPlayed,
      'Card played.',
      transition: GameStateTransition(
        type: GameStateTransitionType.cardPlayed,
        actor: GameStateTransitionActor.self,
        card: card,
        targetPileId: pileId,
      ),
    );
    if (drawReplacement(_playerDeck, _playerHand) != null) {
      _emit(
        PracticeEventType.replacementDrawn,
        'A replacement card was drawn automatically.',
      );
    }
    if (playerHasWon(_playerDeck, _playerHand)) {
      _finish(playerId);
    } else {
      _resolveStuck();
      _scheduleBot();
    }
    notifyListeners();
    return true;
  }

  void _scheduleBot() {
    _botTimer?.cancel();
    if (finished || _disposed) return;
    final remaining = _botDeck.length + _botHand.length;
    final minMs = remaining > 18 ? 2500 : 1500;
    final spreadMs = 1001;
    botThinking = true;
    _botTimer = Timer(
      _botThinkDelay ??
          Duration(milliseconds: minMs + _random.nextInt(spreadMs)),
      _playBot,
    );
  }

  void _playBot() {
    if (finished || _disposed) return;
    final moves = <(int, GamePileId)>[];
    for (var i = 0; i < _botHand.length; i++) {
      for (final target in legalTargets(
        _botHand[i],
        _pile1.last,
        _pile2.last,
      )) {
        moves.add((i, target));
      }
    }
    if (moves.isEmpty) {
      _resolveStuck();
      _scheduleBot();
      return;
    }
    final move = moves[_random.nextInt(moves.length)];
    final card = _botHand.removeAt(move.$1);
    (move.$2 == GamePileId.pile1 ? _pile1 : _pile2).add(card);
    drawReplacement(_botDeck, _botHand);
    _version++;
    botThinking = false;
    _emit(
      PracticeEventType.cardPlayed,
      'The practice bot played a card.',
      transition: GameStateTransition(
        type: GameStateTransitionType.cardPlayed,
        actor: GameStateTransitionActor.opponent,
        card: card,
        targetPileId: move.$2,
      ),
    );
    if (playerHasWon(_botDeck, _botHand)) {
      _finish(botId);
    } else {
      _resolveStuck();
      _scheduleBot();
    }
    notifyListeners();
  }

  void _resolveStuck() {
    var attempts = 0;
    while (!finished &&
        !handHasLegalMove(_playerHand, _pile1.last, _pile2.last) &&
        !handHasLegalMove(_botHand, _pile1.last, _pile2.last) &&
        attempts++ < 32) {
      final recyclable = <GameCard>[
        if (_pile1.length > 1) ..._pile1.sublist(0, _pile1.length - 1),
        if (_pile2.length > 1) ..._pile2.sublist(0, _pile2.length - 1),
      ];
      if (recyclable.isNotEmpty) {
        final shuffled = shuffledCards(recyclable, _random);
        final old1 = _pile1.last;
        final old2 = _pile2.last;
        _pile1
          ..clear()
          ..addAll(shuffled.take((shuffled.length + 1) ~/ 2))
          ..add(old1);
        _pile2
          ..clear()
          ..addAll(shuffled.skip((shuffled.length + 1) ~/ 2))
          ..add(old2);
        _pile1.shuffle(_random);
        _pile2.shuffle(_random);
      } else if (_playerDeck.isNotEmpty && _botDeck.isNotEmpty) {
        final old1 = _pile1[0];
        final old2 = _pile2[0];
        _pile1[0] = _playerDeck.removeLast();
        _pile2[0] = _botDeck.removeLast();
        _playerDeck.insert(_random.nextInt(_playerDeck.length + 1), old1);
        _botDeck.insert(_random.nextInt(_botDeck.length + 1), old2);
      } else {
        break;
      }
      _version++;
      feedback = null;
      _emit(PracticeEventType.pilesReset, 'Center piles updated.');
    }
  }

  void _finish(String winner) {
    _winnerId = winner;
    botThinking = false;
    _botTimer?.cancel();
    _clockTimer?.cancel();
    _emit(
      PracticeEventType.matchEnded,
      winner == playerId ? 'You won!' : 'The practice bot won.',
    );
  }

  void _emit(
    PracticeEventType type,
    String message, {
    GameStateTransition? transition,
  }) {
    if (!_events.isClosed) {
      _events.add(PracticeEvent(type, message, transition: transition));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _botTimer?.cancel();
    _clockTimer?.cancel();
    _events.close();
    super.dispose();
  }
}
