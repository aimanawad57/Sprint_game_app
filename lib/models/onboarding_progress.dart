const currentTutorialVersion = 1;

class OnboardingProgress {
  const OnboardingProgress({
    this.tutorialCompletedVersion = 0,
    this.firstPracticeCompletedVersion = 0,
    this.tutorialPromptDismissedVersion = 0,
  });

  final int tutorialCompletedVersion;
  final int firstPracticeCompletedVersion;
  final int tutorialPromptDismissedVersion;

  bool get shouldRecommendTutorial =>
      tutorialCompletedVersion < currentTutorialVersion &&
      tutorialPromptDismissedVersion < currentTutorialVersion;

  factory OnboardingProgress.fromJson(Map<String, dynamic> json) {
    int version(String field) {
      final value = json[field] ?? 0;
      if (value is! int || value < 0) {
        throw FormatException('$field must be a non-negative integer');
      }
      return value;
    }

    return OnboardingProgress(
      tutorialCompletedVersion: version('tutorialCompletedVersion'),
      firstPracticeCompletedVersion: version('firstPracticeCompletedVersion'),
      tutorialPromptDismissedVersion: version('tutorialPromptDismissedVersion'),
    );
  }

  Map<String, dynamic> toJson() => {
    'tutorialCompletedVersion': tutorialCompletedVersion,
    'firstPracticeCompletedVersion': firstPracticeCompletedVersion,
    'tutorialPromptDismissedVersion': tutorialPromptDismissedVersion,
  };

  OnboardingProgress merge(OnboardingProgress other) => OnboardingProgress(
    tutorialCompletedVersion: _max(
      tutorialCompletedVersion,
      other.tutorialCompletedVersion,
    ),
    firstPracticeCompletedVersion: _max(
      firstPracticeCompletedVersion,
      other.firstPracticeCompletedVersion,
    ),
    tutorialPromptDismissedVersion: _max(
      tutorialPromptDismissedVersion,
      other.tutorialPromptDismissedVersion,
    ),
  );

  OnboardingProgress completeTutorial() => merge(
    const OnboardingProgress(tutorialCompletedVersion: currentTutorialVersion),
  );

  OnboardingProgress completeFirstPractice() => merge(
    const OnboardingProgress(
      firstPracticeCompletedVersion: currentTutorialVersion,
    ),
  );

  OnboardingProgress dismissTutorialPrompt() => merge(
    const OnboardingProgress(
      tutorialPromptDismissedVersion: currentTutorialVersion,
    ),
  );

  static int _max(int a, int b) => a > b ? a : b;

  @override
  bool operator ==(Object other) =>
      other is OnboardingProgress &&
      tutorialCompletedVersion == other.tutorialCompletedVersion &&
      firstPracticeCompletedVersion == other.firstPracticeCompletedVersion &&
      tutorialPromptDismissedVersion == other.tutorialPromptDismissedVersion;

  @override
  int get hashCode => Object.hash(
    tutorialCompletedVersion,
    firstPracticeCompletedVersion,
    tutorialPromptDismissedVersion,
  );
}
