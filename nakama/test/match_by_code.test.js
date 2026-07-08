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
    "generateMatchCode," +
    "normalizeMatchCode," +
    "createOpenWaitingMatchState," +
    "initializeGameState," +
    "sprintMatchJoinAttempt," +
    "sprintMatchJoin," +
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
  const state = runtime.createOpenWaitingMatchState("creator-1");
  assert.deepEqual(normalize(state.playerOrder), ["creator-1", runtime.UNASSIGNED_PLAYER_ID]);
  assert.ok(state.players["creator-1"]);
  assert.equal(Object.keys(state.players).length, 1);
});

test("an open match does not initialize until the second seat is filled", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1");
  state.players["creator-1"].connected = true;
  state.presences["creator-1"] = presence("creator-1");

  assert.equal(runtime.initializeGameState(state, () => 0), false);
});

test("joinAttempt accepts the creator and any first challenger, rejects a third user", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1");

  const creatorAttempt = runtime.sprintMatchJoinAttempt(
    {}, {info: () => {}, warn: () => {}}, {}, dispatcher, 0, state, presence("creator-1"), {}
  );
  assert.equal(creatorAttempt.accept, true);

  const challengerAttempt = runtime.sprintMatchJoinAttempt(
    {}, {info: () => {}, warn: () => {}}, {}, dispatcher, 0, state, presence("challenger-1"), {}
  );
  assert.equal(challengerAttempt.accept, true);

  const {state: joinedState} = runtime.sprintMatchJoin(
    {}, {info: () => {}, warn: () => {}}, {}, dispatcher, 0, state,
    [presence("creator-1"), presence("challenger-1")]
  );
  assert.equal(joinedState.playerOrder[1], "challenger-1");

  const strangerAttempt = runtime.sprintMatchJoinAttempt(
    {}, {info: () => {}, warn: () => {}}, {}, dispatcher, 0, joinedState, presence("stranger-1"), {}
  );
  assert.equal(strangerAttempt.accept, false);
});

test("redeeming the code deals cards once both seats are connected", () => {
  const state = runtime.createOpenWaitingMatchState("creator-1");
  const logger = {info: () => {}, warn: () => {}};

  runtime.sprintMatchJoin({}, logger, {}, dispatcher, 0, state, [presence("creator-1")]);
  assert.equal(state.playerOrder[1], runtime.UNASSIGNED_PLAYER_ID);

  runtime.sprintMatchJoin({}, logger, {}, dispatcher, 0, state, [presence("challenger-1")]);
  assert.equal(state.playerOrder[1], "challenger-1");
  assert.equal(state.status, runtime.MatchStatus.Active);
  assert.equal(state.players["creator-1"].hand.length, 3);
  assert.equal(state.players["challenger-1"].hand.length, 3);
});
