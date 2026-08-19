import 'package:flutter/widgets.dart';

import '../services/game_feedback_service.dart';

class GameFeedbackScope extends InheritedNotifier<GameFeedbackService> {
  const GameFeedbackScope({
    super.key,
    required GameFeedbackService service,
    required super.child,
  }) : super(notifier: service);

  static GameFeedbackService of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<GameFeedbackScope>();
    assert(scope != null, 'No GameFeedbackScope found above this context.');
    return scope!.notifier!;
  }

  static GameFeedbackService? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<GameFeedbackScope>()
        ?.notifier;
  }
}
