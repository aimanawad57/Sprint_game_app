import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/services/match_reconnect_coordinator.dart';

void main() {
  testWidgets(
    'attempts immediately and follows bounded backoff without overlap',
    (tester) async {
      var nowMs = 0;
      var attempts = 0;
      final completions = <Completer<void>>[];
      final coordinator = MatchReconnectCoordinator(
        attempt: () {
          attempts += 1;
          final completer = Completer<void>();
          completions.add(completer);
          return completer.future;
        },
        cancelAttempt: () async {
          for (final completion in completions) {
            if (!completion.isCompleted) completion.complete();
          }
        },
        monotonicMilliseconds: () => nowMs,
      );

      coordinator.start(gracePeriodMs: 30000);
      await tester.pump();
      expect(attempts, 1);

      nowMs = 2000;
      await tester.pump(const Duration(seconds: 2));
      expect(attempts, 1, reason: 'an in-flight attempt must not overlap');

      completions.single.complete();
      await tester.pump();
      nowMs = 2500;
      await tester.pump(const Duration(milliseconds: 500));
      expect(attempts, 2);

      coordinator.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'expires from monotonic elapsed time and stops automatic retries',
    (tester) async {
      var nowMs = 0;
      var attempts = 0;
      final coordinator = MatchReconnectCoordinator(
        attempt: () async => attempts += 1,
        cancelAttempt: () async {},
        monotonicMilliseconds: () => nowMs,
      );

      coordinator.start(gracePeriodMs: 1000);
      await tester.pump();
      expect(attempts, 1);

      nowMs = 1000;
      await tester.pump(const Duration(seconds: 1));
      expect(coordinator.status, MatchReconnectStatus.expired);
      final attemptsAtExpiry = attempts;

      nowMs = 5000;
      await tester.pump(const Duration(seconds: 4));
      expect(attempts, attemptsAtExpiry);
      coordinator.dispose();
    },
  );

  testWidgets(
    'authoritative deadline reconciliation includes bounded half RTT',
    (tester) async {
      var nowMs = 100;
      final coordinator = MatchReconnectCoordinator(
        attempt: () async {},
        cancelAttempt: () async {},
        monotonicMilliseconds: () => nowMs,
      )..start(gracePeriodMs: 30000);
      await tester.pump();

      coordinator.reconcileDeadline(
        deadlineMs: 110000,
        serverTimeMs: 100000,
        rttEstimateMs: 400,
      );
      expect(coordinator.remainingMilliseconds, 9800);

      nowMs += 1800;
      await tester.pump(const Duration(milliseconds: 200));
      expect(coordinator.remainingSeconds, 8);
      coordinator.dispose();
    },
  );

  testWidgets(
    'restoration cancels retries and manual retry remains available',
    (tester) async {
      var nowMs = 0;
      var attempts = 0;
      final coordinator = MatchReconnectCoordinator(
        attempt: () async => attempts += 1,
        cancelAttempt: () async {},
        monotonicMilliseconds: () => nowMs,
      )..start(gracePeriodMs: 30000);
      await tester.pump();
      expect(attempts, 1);

      coordinator.markRestored();
      nowMs = 10000;
      await tester.pump(const Duration(seconds: 10));
      expect(attempts, 1);
      expect(coordinator.status, MatchReconnectStatus.restored);

      coordinator.reset();
      coordinator.start(gracePeriodMs: 1000);
      await tester.pump();
      nowMs = 11000;
      await tester.pump(const Duration(seconds: 1));
      expect(coordinator.status, MatchReconnectStatus.expired);
      coordinator.retryNow();
      await tester.pump();
      expect(attempts, 3);
      coordinator.dispose();
    },
  );

  testWidgets('a hung attempt times out so automatic retry can continue', (
    tester,
  ) async {
    var nowMs = 0;
    var attempts = 0;
    var cancellations = 0;
    Completer<void>? inFlight;
    final coordinator = MatchReconnectCoordinator(
      attempt: () {
        attempts += 1;
        inFlight = Completer<void>();
        return inFlight!.future;
      },
      cancelAttempt: () async {
        cancellations += 1;
        if (inFlight case final attempt? when !attempt.isCompleted) {
          attempt.complete();
        }
      },
      monotonicMilliseconds: () => nowMs,
      attemptTimeout: const Duration(milliseconds: 400),
    )..start(gracePeriodMs: 30000);

    await tester.pump();
    expect(attempts, 1);

    nowMs = 400;
    await tester.pump(const Duration(milliseconds: 400));
    expect(coordinator.attemptInProgress, isFalse);
    expect(cancellations, 1);

    nowMs = 900;
    await tester.pump(const Duration(milliseconds: 500));
    expect(attempts, 2);
    coordinator.dispose();
    await tester.pump();
  });

  testWidgets('expiry cancels a hung transport before manual retry', (
    tester,
  ) async {
    var nowMs = 0;
    var attempts = 0;
    var cancellations = 0;
    Completer<void>? inFlight;
    final coordinator = MatchReconnectCoordinator(
      attempt: () {
        attempts += 1;
        inFlight = Completer<void>();
        return inFlight!.future;
      },
      cancelAttempt: () async {
        cancellations += 1;
        if (inFlight case final attempt? when !attempt.isCompleted) {
          attempt.complete();
        }
      },
      monotonicMilliseconds: () => nowMs,
      attemptTimeout: const Duration(seconds: 5),
    )..start(gracePeriodMs: 1000);

    await tester.pump();
    nowMs = 1000;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(coordinator.status, MatchReconnectStatus.expired);
    expect(cancellations, 1);
    expect(coordinator.attemptInProgress, isFalse);

    final retry = coordinator.retryNow();
    await tester.pump();
    expect(attempts, 2);
    coordinator.dispose();
    await tester.pump();
    await retry;
  });

  testWidgets('authoritative restore wins a race with attempt timeout', (
    tester,
  ) async {
    var nowMs = 0;
    var attempts = 0;
    var cancellations = 0;
    final coordinator = MatchReconnectCoordinator(
      attempt: () {
        attempts += 1;
        return Completer<void>().future;
      },
      cancelAttempt: () async => cancellations += 1,
      monotonicMilliseconds: () => nowMs,
      attemptTimeout: const Duration(milliseconds: 400),
    )..start(gracePeriodMs: 30000);

    await tester.pump();
    coordinator.markRestored();
    nowMs = 1000;
    await tester.pump(const Duration(seconds: 1));

    expect(coordinator.status, MatchReconnectStatus.restored);
    expect(coordinator.attemptInProgress, isFalse);
    expect(attempts, 1);
    expect(cancellations, 0);
    coordinator.dispose();
  });
}
