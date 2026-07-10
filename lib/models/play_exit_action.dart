enum PlayExitAction {
  viewProfile,
  disconnectedFromMatch,
  matchFinished,
}

class PlayExitResult {
  const PlayExitResult.viewProfile()
    : action = PlayExitAction.viewProfile,
      matchId = null;

  const PlayExitResult.disconnectedFromMatch(this.matchId)
    : action = PlayExitAction.disconnectedFromMatch;

  const PlayExitResult.matchFinished()
    : action = PlayExitAction.matchFinished,
      matchId = null;

  final PlayExitAction action;
  final String? matchId;
}
