const ONBOARDING_COLLECTION = "onboarding";
const ONBOARDING_KEY = "progress";
const MAX_ONBOARDING_VERSION = 1000;

type OnboardingProgress = {
  tutorialCompletedVersion: number;
  firstPracticeCompletedVersion: number;
  tutorialPromptDismissedVersion: number;
};

function emptyOnboardingProgress(): OnboardingProgress {
  return {
    tutorialCompletedVersion: 0,
    firstPracticeCompletedVersion: 0,
    tutorialPromptDismissedVersion: 0
  };
}

function onboardingVersion(value: unknown, field: string): number {
  if (value === undefined || value === null) return 0;
  if (!Number.isInteger(value) || (value as number) < 0 || (value as number) > MAX_ONBOARDING_VERSION) {
    throw new Error(field + " must be an integer from 0 to " + MAX_ONBOARDING_VERSION + ".");
  }
  return value as number;
}

function parseOnboardingProgress(value: unknown, rejectUnknown: boolean): OnboardingProgress {
  const payload = value && typeof value === "object" ? value as {[key: string]: unknown} : {};
  const allowed: {[key: string]: boolean} = {
    tutorialCompletedVersion: true,
    firstPracticeCompletedVersion: true,
    tutorialPromptDismissedVersion: true
  };
  if (rejectUnknown) {
    Object.keys(payload).forEach((key) => {
      if (!allowed[key]) throw new Error("Unknown onboarding field: " + key + ".");
    });
  }
  return {
    tutorialCompletedVersion: onboardingVersion(payload.tutorialCompletedVersion, "tutorialCompletedVersion"),
    firstPracticeCompletedVersion: onboardingVersion(payload.firstPracticeCompletedVersion, "firstPracticeCompletedVersion"),
    tutorialPromptDismissedVersion: onboardingVersion(payload.tutorialPromptDismissedVersion, "tutorialPromptDismissedVersion")
  };
}

function readOnboardingProgress(nk: nkruntime.Nakama, userId: string): {
  progress: OnboardingProgress;
  object: nkruntime.StorageObject | undefined;
} {
  const object = nk.storageRead([{collection: ONBOARDING_COLLECTION, key: ONBOARDING_KEY, userId: userId}])[0];
  return {
    progress: object ? parseOnboardingProgress(object.value, false) : emptyOnboardingProgress(),
    object: object
  };
}

function requireOnboardingUser(ctx: nkruntime.Context): string {
  if (!ctx.userId) throw new Error("A session is required to access onboarding progress.");
  return ctx.userId;
}

function rpcGetOnboardingProgress(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  return JSON.stringify(readOnboardingProgress(nk, requireOnboardingUser(ctx)).progress);
}

function rpcMergeOnboardingProgress(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  const userId = requireOnboardingUser(ctx);
  let decoded: unknown = {};
  if (payload) {
    try { decoded = JSON.parse(payload); } catch (_) { throw new Error("Onboarding payload must be valid JSON."); }
  }
  if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
    throw new Error("Onboarding payload must be an object.");
  }
  const submitted = parseOnboardingProgress(decoded, true);
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const existing = readOnboardingProgress(nk, userId);
    const merged: OnboardingProgress = {
      tutorialCompletedVersion: Math.max(existing.progress.tutorialCompletedVersion, submitted.tutorialCompletedVersion),
      firstPracticeCompletedVersion: Math.max(existing.progress.firstPracticeCompletedVersion, submitted.firstPracticeCompletedVersion),
      tutorialPromptDismissedVersion: Math.max(existing.progress.tutorialPromptDismissedVersion, submitted.tutorialPromptDismissedVersion)
    };
    const write: nkruntime.StorageWriteRequest = {
      collection: ONBOARDING_COLLECTION,
      key: ONBOARDING_KEY,
      userId: userId,
      value: merged,
      version: existing.object && existing.object.version ? existing.object.version : "*",
      permissionRead: 1,
      permissionWrite: 0
    };
    try {
      nk.storageWrite([write]);
      logger.debug("Merged onboarding progress for user %s", userId);
      return JSON.stringify(merged);
    } catch (error) {
      if (attempt === 2) throw error;
    }
  }
  throw new Error("Could not merge onboarding progress.");
}
