import 'dart:async';

import 'package:flutter/foundation.dart';

enum MatchReconnectStatus { idle, reconnecting, restored, expired }

typedef MatchReconnectAttempt = Future<void> Function();
typedef MatchReconnectAttemptCancellation = Future<void> Function();
typedef MonotonicMilliseconds = int Function();

/// Runs bounded, non-overlapping reconnect attempts without owning gameplay.
///
/// The authoritative match snapshot still decides whether the match recovered;
/// callers must invoke [markRestored] after receiving it. The coordinator only
/// owns retry timing and the local recovery-window presentation.
class MatchReconnectCoordinator extends ChangeNotifier {
  MatchReconnectCoordinator({
    required MatchReconnectAttempt attempt,
    required MatchReconnectAttemptCancellation cancelAttempt,
    MonotonicMilliseconds? monotonicMilliseconds,
    Duration attemptTimeout = const Duration(seconds: 3),
  }) : assert(attemptTimeout > Duration.zero),
       _attempt = attempt,
       _cancelAttempt = cancelAttempt,
       _monotonicMilliseconds =
           monotonicMilliseconds ?? _defaultMonotonicMilliseconds,
       _attemptTimeout = attemptTimeout;

  static final Stopwatch _processClock = Stopwatch()..start();
  static const List<Duration> _retryDelays = <Duration>[
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
  ];

  final MatchReconnectAttempt _attempt;
  final MatchReconnectAttemptCancellation _cancelAttempt;
  final MonotonicMilliseconds _monotonicMilliseconds;
  final Duration _attemptTimeout;

  MatchReconnectStatus _status = MatchReconnectStatus.idle;
  Timer? _retryTimer;
  Timer? _countdownTicker;
  int _retryIndex = 0;
  int _startedAtMs = 0;
  int _windowMs = 0;
  bool _attemptInProgress = false;
  bool _disposed = false;
  int _attemptEpoch = 0;
  Future<void>? _expiryCancellation;
  Timer? _attemptTimeoutTimer;
  Completer<void>? _attemptWaiter;

  MatchReconnectStatus get status => _status;
  bool get isActive => _status == MatchReconnectStatus.reconnecting;
  bool get attemptInProgress => _attemptInProgress;

  int get remainingMilliseconds {
    if (_status == MatchReconnectStatus.idle ||
        _status == MatchReconnectStatus.restored) {
      return 0;
    }
    final elapsed = _monotonicMilliseconds() - _startedAtMs;
    return (_windowMs - elapsed).clamp(0, _windowMs);
  }

  int get remainingSeconds =>
      (remainingMilliseconds / Duration.millisecondsPerSecond).ceil();

  void start({required int gracePeriodMs}) {
    if (_disposed || isActive) return;
    _cancelTimers();
    _status = MatchReconnectStatus.reconnecting;
    _expiryCancellation = null;
    _retryIndex = 0;
    _windowMs = gracePeriodMs.clamp(1000, 120000);
    _startedAtMs = _monotonicMilliseconds();
    notifyListeners();
    _countdownTicker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _tickDeadline(),
    );
    unawaited(_runAttempt(scheduleAnother: true));
  }

  /// Re-anchors the local display to a newly received authoritative deadline.
  void reconcileDeadline({
    required int deadlineMs,
    required int serverTimeMs,
    int? rttEstimateMs,
  }) {
    if (!isActive) return;
    final oneWayCompensation = ((rttEstimateMs ?? 0) / 2).round().clamp(0, 500);
    _windowMs = (deadlineMs - serverTimeMs - oneWayCompensation).clamp(
      0,
      120000,
    );
    _startedAtMs = _monotonicMilliseconds();
    _tickDeadline();
  }

  Future<void> retryNow() async {
    if (_disposed || _status == MatchReconnectStatus.idle) return;
    final expiryCancellation = _expiryCancellation;
    if (expiryCancellation != null) await expiryCancellation;
    if (_disposed || _status == MatchReconnectStatus.idle) return;
    _retryTimer?.cancel();
    await _runAttempt(scheduleAnother: isActive);
  }

  void markRestored() {
    if (_disposed || _status == MatchReconnectStatus.restored) return;
    _cancelTimers();
    _cancelAttemptWait();
    _status = MatchReconnectStatus.restored;
    notifyListeners();
  }

  void reset() {
    if (_disposed) return;
    _cancelTimers();
    _cancelAttemptWait();
    _status = MatchReconnectStatus.idle;
    _retryIndex = 0;
    notifyListeners();
  }

  Future<void> _runAttempt({required bool scheduleAnother}) async {
    if (_disposed || _attemptInProgress) return;
    final attemptEpoch = ++_attemptEpoch;
    _attemptInProgress = true;
    notifyListeners();
    try {
      final attempt = _attempt();
      try {
        await _waitForAttempt(attempt);
      } on TimeoutException {
        if (_disposed ||
            (_status != MatchReconnectStatus.reconnecting &&
                _status != MatchReconnectStatus.expired)) {
          return;
        }
        // Expiring the local timeout waiter cannot cancel its source. The
        // caller must terminate the underlying transport (PlayPage closes the
        // recovery websocket) before another attempt is scheduled, preserving
        // true non-overlap.
        final expiryCancellation = _expiryCancellation;
        if (expiryCancellation != null) {
          await expiryCancellation;
        } else {
          await _cancelAttemptSafely();
        }
      }
    } catch (_) {
      // Recovery errors are expected while connectivity is unavailable. The
      // next bounded attempt remains scheduled and gameplay state is untouched.
    } finally {
      if (!_disposed && attemptEpoch == _attemptEpoch) {
        _attemptInProgress = false;
        notifyListeners();
        if (scheduleAnother && isActive) _scheduleRetry();
      }
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = _retryDelays[_retryIndex.clamp(0, _retryDelays.length - 1)];
    if (_retryIndex < _retryDelays.length - 1) _retryIndex += 1;
    _retryTimer = Timer(delay, () {
      if (!isActive || _disposed) return;
      unawaited(_runAttempt(scheduleAnother: true));
    });
  }

  void _tickDeadline() {
    if (!isActive || _disposed) return;
    if (remainingMilliseconds <= 0) {
      _retryTimer?.cancel();
      _countdownTicker?.cancel();
      _status = MatchReconnectStatus.expired;
      _beginExpiryCancellation();
    }
    notifyListeners();
  }

  void _cancelTimers() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _countdownTicker?.cancel();
    _countdownTicker = null;
  }

  static int _defaultMonotonicMilliseconds() =>
      _processClock.elapsedMilliseconds;

  Future<void> _cancelAttemptSafely() async {
    try {
      await _cancelAttempt();
    } catch (_) {
      // Cancellation is best-effort; timeout/expiry state remains usable.
    }
  }

  void _beginExpiryCancellation() {
    if (!_attemptInProgress || _expiryCancellation != null) return;
    late final Future<void> cancellation;
    cancellation = _cancelExpiredAttempt().whenComplete(() {
      if (identical(_expiryCancellation, cancellation)) {
        _expiryCancellation = null;
      }
    });
    _expiryCancellation = cancellation;
  }

  Future<void> _cancelExpiredAttempt() async {
    final cancelledEpoch = _attemptEpoch;
    await _cancelAttemptSafely();
    if (_disposed || cancelledEpoch != _attemptEpoch) return;
    _cancelAttemptWait();
    _attemptEpoch += 1;
    _attemptInProgress = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    _cancelAttemptWait();
    if (_attemptInProgress && _expiryCancellation == null) {
      unawaited(_cancelAttemptSafely());
    }
    super.dispose();
  }

  Future<void> _waitForAttempt(Future<void> attempt) {
    final waiter = Completer<void>();
    _attemptWaiter = waiter;
    late final Timer timeoutTimer;
    timeoutTimer = Timer(_attemptTimeout, () {
      if (identical(_attemptTimeoutTimer, timeoutTimer)) {
        _attemptTimeoutTimer = null;
      }
      if (!waiter.isCompleted) {
        waiter.completeError(TimeoutException('Reconnect attempt timed out.'));
      }
    });
    _attemptTimeoutTimer = timeoutTimer;

    attempt.then<void>(
      (_) {
        if (!waiter.isCompleted) waiter.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
      },
    );

    return waiter.future.whenComplete(() {
      timeoutTimer.cancel();
      if (identical(_attemptWaiter, waiter)) {
        _attemptWaiter = null;
        _attemptTimeoutTimer = null;
      }
    });
  }

  void _cancelAttemptWait() {
    _attemptTimeoutTimer?.cancel();
    _attemptTimeoutTimer = null;
    final waiter = _attemptWaiter;
    _attemptWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }
}
