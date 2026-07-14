const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function loadRuntimeForTest() {
  const runtimePath = path.resolve(__dirname, "../build/main.js");
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  const exposedSource =
    runtimeSource +
    "\n;globalThis.__sprintTest = {" +
    "UNASSIGNED_PLAYER_ID," +
    "MATCH_CODE_ALPHABET," +
    "MATCH_CODE_LENGTH," +
    "MATCH_CODE_COLLECTION," +
    "SYSTEM_USER_ID," +
    "generateMatchCode," +
    "normalizeMatchCode," +
    "createOpenWaitingMatchState," +
    "initializeGameState," +
    "waitingMatchTimeoutMs," +
    "sprintMatchJoinAttempt," +
    "sprintMatchJoin," +
    "sprintMatchLeave," +
    "sprintMatchLoop," +
    "MatchStatus" +
    "};";
  const context = {};
  vm.createContext(context);
  vm.runInContext(exposedSource, context);
  return context.__sprintTest;
}

function normalize(value) {
  return JSON.parse(JSON.stringify(value));
}

function presence(userId) {
  return {userId, sessionId: userId + "-session", username: userId};
}

const dispatcher = {
  broadcastMessage: () => {}
};

const runtime = loadRuntimeForTest();
const logger = {info: () => {}, warn: () => {}, error: () => {}};
const TEST_CODE = "ABCDEF";

function fakeNk() {
  const deletedKeys = [];
  return {
    storageDelete: (requests) => {
      deletedKeys.push(...requests);
    },
    deletedKeys
  };
}

test("generateMatchCode produces a fixed-length code from the safe alphabet", () => {
  const code = runtime.generateMatchCode(() => 0.999999);
  assert.equal(code.length, runtime.MATCH_CODE_LENGTH);
  for (const char of code) {
    assert.ok(runtime.MATCH_CODE_ALPHABET.includes(char));
  }
});

test("normalizeMatchCode trims and uppercases", () => {
  assert.equal(runtime.normalizeMatchCode("  abc123 "), "ABC123");
});

test("createOpenWaitingMatchState only registers the creator", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1", TEST_CODE);
  assert.deepEqual(normalize(state.playerOrder), ["creator-1", runtime.UNASSIGNED_PLAYER_ID]);
  assert.ok(state.players["creator-1"]);
  assert.equal(Object.keys(state.players).length, 1);
  assert.equal(state.matchCode, TEST_CODE);
});

test("an open match does not initialize until the second seat is filled", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1", TEST_CODE);
  state.players["creator-1"].connected = true;
  state.presences["creator-1"] = presence("creator-1");

  assert.equal(runtime.initializeGameState(state, () => 0), false);
});

test("joinAttempt accepts the creator and any first challenger, rejects a third user", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1", TEST_CODE);
  const nk = fakeNk();

  const creatorAttempt = runtime.sprintMatchJoinAttempt(
    {}, logger, nk, dispatcher, 0, state, presence("creator-1"), {}
  );
  assert.equal(creatorAttempt.accept, true);

  const challengerAttempt = runtime.sprintMatchJoinAttempt(
    {}, logger, nk, dispatcher, 0, state, presence("challenger-1"), {}
  );
  assert.equal(challengerAttempt.accept, true);

  const {state: joinedState} = runtime.sprintMatchJoin(
    {}, logger, nk, dispatcher, 0, state,
    [presence("creator-1"), presence("challenger-1")]
  );
  assert.equal(joinedState.playerOrder[1], "challenger-1");

  const strangerAttempt = runtime.sprintMatchJoinAttempt(
    {}, logger, nk, dispatcher, 0, joinedState, presence("stranger-1"), {}
  );
  assert.equal(strangerAttempt.accept, false);
});

test("redeeming the code deals cards once both seats are connected", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1", TEST_CODE);
  const nk = fakeNk();

  runtime.sprintMatchJoin({}, logger, nk, dispatcher, 0, state, [presence("creator-1")]);
  assert.equal(state.playerOrder[1], runtime.UNASSIGNED_PLAYER_ID);

  runtime.sprintMatchJoin({}, logger, nk, dispatcher, 0, state, [presence("challenger-1")]);
  assert.equal(state.playerOrder[1], "challenger-1");
  assert.equal(state.status, runtime.MatchStatus.Active);
  assert.equal(state.players["creator-1"].hand.length, 3);
  assert.equal(state.players["challenger-1"].hand.length, 3);
});

test("the match code stays valid after a challenger redeems it, so a dropped player can still use it", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1", TEST_CODE);
  const nk = fakeNk();

  runtime.sprintMatchJoin({}, logger, nk, dispatcher, 0, state, [presence("creator-1")]);
  runtime.sprintMatchJoin({}, logger, nk, dispatcher, 0, state, [presence("challenger-1")]);
  assert.equal(state.playerOrder[1], "challenger-1");
  assert.equal(nk.deletedKeys.length, 0);
  assert.equal(state.matchCode, TEST_CODE);
});

test("the match code is invalidated if the creator leaves before anyone redeems it", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1", TEST_CODE);
  const nk = fakeNk();

  runtime.sprintMatchJoin({}, logger, nk, dispatcher, 0, state, [presence("creator-1")]);
  assert.equal(nk.deletedKeys.length, 0);

  runtime.sprintMatchLeave({}, logger, nk, dispatcher, 0, state, [presence("creator-1")]);
  assert.equal(nk.deletedKeys.length, 1);
  assert.deepEqual(normalize(nk.deletedKeys[0]), {
    collection: runtime.MATCH_CODE_COLLECTION,
    key: TEST_CODE,
    userId: runtime.SYSTEM_USER_ID
  });
  assert.equal(state.matchCode, null);
});

test("a match-code lobby timeout invalidates the code and terminates", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1", TEST_CODE);
  const nk = fakeNk();
  state.createdAtMs = Date.now() - runtime.waitingMatchTimeoutMs - 1;

  const result = runtime.sprintMatchLoop({}, logger, nk, dispatcher, 0, state, []);

  assert.equal(result, null);
  assert.equal(nk.deletedKeys.length, 1);
  assert.deepEqual(normalize(nk.deletedKeys[0]), {
    collection: runtime.MATCH_CODE_COLLECTION,
    key: TEST_CODE,
    userId: runtime.SYSTEM_USER_ID
  });
  assert.equal(state.matchCode, null);
});

test("the match code stays valid while one player is still connected, and is invalidated once both leave", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1", TEST_CODE);
  const nk = fakeNk();

  runtime.sprintMatchJoin({}, logger, nk, dispatcher, 0, state, [presence("creator-1")]);
  runtime.sprintMatchJoin({}, logger, nk, dispatcher, 0, state, [presence("challenger-1")]);

  runtime.sprintMatchLeave({}, logger, nk, dispatcher, 0, state, [presence("creator-1")]);
  assert.equal(nk.deletedKeys.length, 0);
  assert.equal(state.matchCode, TEST_CODE);

  runtime.sprintMatchLeave({}, logger, nk, dispatcher, 0, state, [presence("challenger-1")]);
  assert.equal(nk.deletedKeys.length, 1);
  assert.deepEqual(normalize(nk.deletedKeys[0]), {
    collection: runtime.MATCH_CODE_COLLECTION,
    key: TEST_CODE,
    userId: runtime.SYSTEM_USER_ID
  });
  assert.equal(state.matchCode, null);
});

test("a dropped player can redeem the code again and reconnect to the same seat", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1", TEST_CODE);
  const nk = fakeNk();

  runtime.sprintMatchJoin({}, logger, nk, dispatcher, 0, state, [presence("creator-1")]);
  runtime.sprintMatchJoin({}, logger, nk, dispatcher, 0, state, [presence("challenger-1")]);
  runtime.sprintMatchLeave({}, logger, nk, dispatcher, 0, state, [presence("challenger-1")]);
  assert.equal(nk.deletedKeys.length, 0);

  const rejoinAttempt = runtime.sprintMatchJoinAttempt(
    {}, logger, nk, dispatcher, 0, state, presence("challenger-1"), {}
  );
  assert.equal(rejoinAttempt.accept, true);

  const {state: rejoinedState} = runtime.sprintMatchJoin(
    {}, logger, nk, dispatcher, 0, state, [presence("challenger-1")]
  );
  assert.equal(rejoinedState.presences["challenger-1"].userId, "challenger-1");
  assert.equal(nk.deletedKeys.length, 0);
});

test("the match code is not deleted twice when both players leave in the same event", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1", TEST_CODE);
  const nk = fakeNk();

  runtime.sprintMatchJoin({}, logger, nk, dispatcher, 0, state, [presence("creator-1")]);
  runtime.sprintMatchJoin({}, logger, nk, dispatcher, 0, state, [presence("challenger-1")]);

  runtime.sprintMatchLeave(
    {}, logger, nk, dispatcher, 0, state,
    [presence("creator-1"), presence("challenger-1")]
  );
  assert.equal(nk.deletedKeys.length, 1);

  runtime.sprintMatchLeave(
    {}, logger, nk, dispatcher, 0, state,
    [presence("creator-1"), presence("challenger-1")]
  );
  assert.equal(nk.deletedKeys.length, 1);
});
