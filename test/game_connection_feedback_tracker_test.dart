import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/services/game_connection_feedback_tracker.dart';

void main() {
  test('initial matchmaking connection changes stay silent', () {
    final tracker = GameConnectionFeedbackTracker();

    expect(
      tracker.observe(connected: false, matchActive: false),
      GameConnectionFeedbackChange.none,
    );
    expect(
      tracker.observe(connected: true, matchActive: false),
      GameConnectionFeedbackChange.none,
    );
    tracker.markActiveSnapshot(connected: true);
    expect(
      tracker.observe(connected: true, matchActive: true),
      GameConnectionFeedbackChange.none,
    );
  });

  test('active disconnect and restoration each emit exactly once', () {
    final tracker = GameConnectionFeedbackTracker()
      ..markActiveSnapshot(connected: true);

    expect(
      tracker.observe(connected: false, matchActive: true),
      GameConnectionFeedbackChange.reconnecting,
    );
    expect(
      tracker.observe(connected: false, matchActive: true),
      GameConnectionFeedbackChange.none,
    );
    expect(
      tracker.observe(connected: true, matchActive: true),
      GameConnectionFeedbackChange.restored,
    );
    expect(
      tracker.observe(connected: true, matchActive: true),
      GameConnectionFeedbackChange.none,
    );
  });

  test('never announces restoration before an active connected baseline', () {
    final tracker = GameConnectionFeedbackTracker();

    expect(tracker.hasActiveConnectedBaseline, isFalse);

    tracker.observe(connected: false, matchActive: false);
    expect(
      tracker.observe(connected: true, matchActive: true),
      GameConnectionFeedbackChange.none,
    );
    expect(tracker.hasActiveConnectedBaseline, isTrue);
  });

  test('finished-match connection chatter stays silent', () {
    final tracker = GameConnectionFeedbackTracker()
      ..markActiveSnapshot(connected: true);

    expect(
      tracker.observe(connected: false, matchActive: false),
      GameConnectionFeedbackChange.none,
    );
  });

  test('an authoritative active snapshot reanchors connection state', () {
    final tracker = GameConnectionFeedbackTracker()
      ..markActiveSnapshot(connected: true);

    expect(
      tracker.observe(connected: false, matchActive: true),
      GameConnectionFeedbackChange.reconnecting,
    );
    tracker.markActiveSnapshot(connected: true);
    expect(
      tracker.observe(connected: true, matchActive: true),
      GameConnectionFeedbackChange.none,
    );
  });
}
