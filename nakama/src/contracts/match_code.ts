const MATCH_CODE_COLLECTION = "match_codes";
// Nakama's reserved nil UUID, used as the owner for storage records that
// belong to the server rather than any single player.
const SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000";
const MATCH_CODE_LENGTH = 6;

// Excludes 0/O, 1/I/L to avoid characters that are easy to misread when a
// player reads a code aloud or copies it by hand.
const MATCH_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

type MatchCodeRecord = {
  // null while the code is reserved but the match it will point to hasn't
  // been created yet (see reserveMatchCode in create_match_by_code.ts).
  matchId: string | null;
  creatorId: string;
  createdAtMs: number;
};

function normalizeMatchCode(rawCode: string): string {
  return rawCode.trim().toUpperCase();
}

function generateMatchCode(random: RandomSource = Math.random): string {
  let code = "";
  for (let index = 0; index < MATCH_CODE_LENGTH; index += 1) {
    const randomValue = random();
    const charIndex = Math.floor(randomValue * MATCH_CODE_ALPHABET.length);
    code += MATCH_CODE_ALPHABET[charIndex];
  }
  return code;
}
