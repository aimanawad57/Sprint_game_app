import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/models/onboarding_progress.dart';

void main() {
  test('missing fields default to zero', () {
    expect(OnboardingProgress.fromJson(const {}), const OnboardingProgress());
  });

  test('progress merges monotonically per field', () {
    const local = OnboardingProgress(
      tutorialCompletedVersion: 2,
      tutorialPromptDismissedVersion: 1,
    );
    const remote = OnboardingProgress(
      tutorialCompletedVersion: 1,
      firstPracticeCompletedVersion: 3,
      tutorialPromptDismissedVersion: 2,
    );
    expect(
      local.merge(remote),
      const OnboardingProgress(
        tutorialCompletedVersion: 2,
        firstPracticeCompletedVersion: 3,
        tutorialPromptDismissedVersion: 2,
      ),
    );
  });

  test('recommendation requires neither completion nor dismissal', () {
    expect(const OnboardingProgress().shouldRecommendTutorial, isTrue);
    expect(
      const OnboardingProgress(
        tutorialCompletedVersion: currentTutorialVersion,
      ).shouldRecommendTutorial,
      isFalse,
    );
    expect(
      const OnboardingProgress(
        tutorialPromptDismissedVersion: currentTutorialVersion,
      ).shouldRecommendTutorial,
      isFalse,
    );
  });
}
