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
    "CARD_CATALOG," +
    "validateCardCatalog," +
    "cloneAndShuffleCards," +
    "createWaitingMatchState," +
    "initializeGameState," +
    "buildPlayerStateView," +
    "sprintMatchJoinAttempt," +
    "sprintMatchJoin," +
    "sprintMatchLeave," +
    "MatchStatus," +
    "CardColor," +
    "CardShape," +
    "ServerOpcode" +
    "};";
  const context = {};
  vm.createContext(context);
  vm.runInContext(exposedSource, context);
  return context.__sprintTest;
}

function normalize(value) {
  return JSON.parse(JSON.stringify(value));
}

function readDocumentedCatalog() {
  const catalogPath = path.resolve(
    __dirname,
    "../../docs/game-contract/card-catalog.csv"
  );
  const lines = fs.readFileSync(catalogPath, "utf8").trim().split(/\r?\n/);
  assert.equal(lines.shift(), "card_id,color,shape,count");

  return lines.map((line) => {
    const [card_id, color, shape, count] = line.split(",");
    return {card_id, color, shape, count: Number(count)};
  });
}

function createConnectedWaitingState(runtime) {
  const state = runtime.createWaitingMatchState(["player-a", "player-b"]);
  state.players["player-a"].connected = true;
  state.players["player-b"].connected = true;
  state.presences["player-a"] = {userId: "player-a"};
  state.presences["player-b"] = {userId: "player-b"};
  return state;
}

function collectStateCards(state) {
  const playerA = state.players[state.playerOrder[0]];
  const playerB = state.players[state.playerOrder[1]];
  return playerA.hand
    .concat(playerA.deck)
    .concat(playerB.hand)
    .concat(playerB.deck)
    .concat(state.centerPiles.pile_1)
    .concat(state.centerPiles.pile_2);
}

const runtime = loadRuntimeForTest();

test("runtime card catalog matches the reviewed CSV exactly", () => {
  assert.deepEqual(normalize(runtime.CARD_CATALOG), readDocumentedCatalog());
});

test("catalog validation enforces size, IDs, attributes, and count", () => {
  assert.doesNotThrow(() => runtime.validateCardCatalog(runtime.CARD_CATALOG));

  const missingCard = normalize(runtime.CARD_CATALOG).slice(0, -1);
  assert.throws(() => runtime.validateCardCatalog(missingCard), /expected 62 cards/);

  const duplicateId = normalize(runtime.CARD_CATALOG);
  duplicateId[1].card_id = duplicateId[0].card_id;
  assert.throws(() => runtime.validateCardCatalog(duplicateId), /expected ID|duplicate ID/);

  const invalidColor = normalize(runtime.CARD_CATALOG);
  invalidColor[0].color = "black";
  assert.throws(() => runtime.validateCardCatalog(invalidColor), /invalid color/);

  const invalidShape = normalize(runtime.CARD_CATALOG);
  invalidShape[0].shape = "square";
  assert.throws(() => runtime.validateCardCatalog(invalidShape), /invalid shape/);

  const invalidCount = normalize(runtime.CARD_CATALOG);
  invalidCount[0].count = 7;
  assert.throws(() => runtime.validateCardCatalog(invalidCount), /invalid count/);
});

test("catalog validation allows duplicate attributes when IDs differ", () => {
  const catalog = normalize(runtime.CARD_CATALOG);
  catalog[61].color = catalog[0].color;
  catalog[61].shape = catalog[0].shape;
  catalog[61].count = catalog[0].count;
  assert.doesNotThrow(() => runtime.validateCardCatalog(catalog));
});

test("shuffle clones cards, is deterministic when injected, and preserves catalog", () => {
  const original = normalize(runtime.CARD_CATALOG);
  const first = runtime.cloneAndShuffleCards(runtime.CARD_CATALOG, () => 0);
  const second = runtime.cloneAndShuffleCards(runtime.CARD_CATALOG, () => 0);

  assert.deepEqual(normalize(first), normalize(second));
  assert.deepEqual(normalize(runtime.CARD_CATALOG), original);
  assert.notStrictEqual(first, runtime.CARD_CATALOG);
  assert.notStrictEqual(first[0], runtime.CARD_CATALOG[0]);
  assert.throws(
    () => runtime.cloneAndShuffleCards(runtime.CARD_CATALOG, () => 1),
    /Random source/
  );
});

test("one connected player does not initialize the game", () => {
  const state = runtime.createWaitingMatchState(["player-a", "player-b"]);
  state.players["player-a"].connected = true;
  state.presences["player-a"] = {userId: "player-a"};

  assert.equal(runtime.initializeGameState(state, () => 0), false);
  assert.equal(state.status, runtime.MatchStatus.Waiting);
  assert.equal(state.stateVersion, 0);
  assert.equal(collectStateCards(state).length, 0);
});

test("initialization deals all cards once in canonical player order", () => {
  const state = createConnectedWaitingState(runtime);
  const originalCatalog = normalize(runtime.CARD_CATALOG);

  assert.equal(runtime.initializeGameState(state, () => 0), true);
  assert.equal(state.status, runtime.MatchStatus.Active);
  assert.equal(state.stateVersion, 1);
  assert.equal(state.winnerId, null);
  assert.deepEqual(normalize(state.playerOrder), ["player-a", "player-b"]);
  assert.equal(state.players["player-a"].hand.length, 3);
  assert.equal(state.players["player-a"].deck.length, 27);
  assert.equal(state.players["player-b"].hand.length, 3);
  assert.equal(state.players["player-b"].deck.length, 27);
  assert.equal(state.centerPiles.pile_1.length, 1);
  assert.equal(state.centerPiles.pile_2.length, 1);

  const allCards = collectStateCards(state);
  assert.equal(allCards.length, 62);
  assert.equal(new Set(allCards.map((card) => card.card_id)).size, 62);
  assert.deepEqual(
    [...allCards.map((card) => card.card_id)].sort(),
    originalCatalog.map((card) => card.card_id).sort()
  );
  assert.deepEqual(normalize(runtime.CARD_CATALOG), originalCatalog);

  const initializedSnapshot = normalize(state);
  assert.equal(runtime.initializeGameState(state, () => 0.75), false);
  assert.deepEqual(normalize(state), initializedSnapshot);
});

test("private views expose only the viewer hand and public counts", () => {
  const state = createConnectedWaitingState(runtime);
  runtime.initializeGameState(state, () => 0.25);

  const viewA = runtime.buildPlayerStateView(state, "player-a");
  const viewB = runtime.buildPlayerStateView(state, "player-b");
  const playerAHandIds = state.players["player-a"].hand.map((card) => card.card_id);
  const playerBHandIds = state.players["player-b"].hand.map((card) => card.card_id);

  assert.deepEqual(viewA.myHand.map((card) => card.card_id), playerAHandIds);
  assert.deepEqual(viewB.myHand.map((card) => card.card_id), playerBHandIds);
  assert.equal(viewA.myDeckCount, 27);
  assert.equal(viewA.opponentHandCount, 3);
  assert.equal(viewA.opponentDeckCount, 27);
  assert.equal("deck" in viewA, false);
  assert.equal("opponentHand" in viewA, false);
  assert.equal("opponentDeck" in viewA, false);
  assert.deepEqual(normalize(viewA.centerPiles), normalize(viewB.centerPiles));
  assert.equal(viewA.stateVersion, 1);
  assert.equal(viewA.status, runtime.MatchStatus.Active);

  const originalStateColor = state.players["player-a"].hand[0].color;
  viewA.myHand[0].color = runtime.CardColor.Purple;
  assert.equal(state.players["player-a"].hand[0].color, originalStateColor);
  assert.throws(
    () => runtime.buildPlayerStateView(state, "outsider"),
    /outside the match/
  );
});

test("match lifecycle sends connection changes before private matchStarted events once", () => {
  const state = runtime.createWaitingMatchState(["player-a", "player-b"]);
  const calls = [];
  const dispatcher = {
    broadcastMessage(opcode, data, presences) {
      calls.push({opcode, data: JSON.parse(data), presences});
    },
  };
  const logger = {info() {}, warn() {}, error() {}};
  const presenceA = {userId: "player-a", sessionId: "session-a"};
  const presenceB = {userId: "player-b", sessionId: "session-b"};

  runtime.sprintMatchJoin(null, logger, null, dispatcher, 1, state, [presenceA]);
  assert.equal(state.status, runtime.MatchStatus.Waiting);
  assert.equal(state.stateVersion, 0);
  assert.deepEqual(calls.map((call) => call.opcode), [runtime.ServerOpcode.ConnectionChanged]);

  runtime.sprintMatchJoin(null, logger, null, dispatcher, 2, state, [presenceB]);
  assert.equal(state.status, runtime.MatchStatus.Active);
  assert.equal(state.stateVersion, 1);
  assert.deepEqual(calls.map((call) => call.opcode), [
    runtime.ServerOpcode.ConnectionChanged,
    runtime.ServerOpcode.ConnectionChanged,
    runtime.ServerOpcode.MatchStarted,
    runtime.ServerOpcode.MatchStarted,
  ]);

  const startedA = calls[2];
  const startedB = calls[3];
  assert.equal(startedA.presences.length, 1);
  assert.equal(startedB.presences.length, 1);
  assert.strictEqual(startedA.presences[0], presenceA);
  assert.strictEqual(startedB.presences[0], presenceB);
  assert.deepEqual(
    normalize(startedA.data.myHand.map((card) => card.card_id)),
    normalize(state.players["player-a"].hand.map((card) => card.card_id))
  );
  assert.deepEqual(
    normalize(startedB.data.myHand.map((card) => card.card_id)),
    normalize(state.players["player-b"].hand.map((card) => card.card_id))
  );

  const cardSnapshot = normalize(collectStateCards(state));
  runtime.sprintMatchLeave(null, logger, null, dispatcher, 3, state, [presenceA]);
  runtime.sprintMatchJoin(null, logger, null, dispatcher, 4, state, [presenceA]);
  assert.equal(state.stateVersion, 1);
  assert.deepEqual(normalize(collectStateCards(state)), cardSnapshot);
  assert.equal(
    calls.filter((call) => call.opcode === runtime.ServerOpcode.MatchStarted).length,
    2
  );
});

test("match lifecycle rejects users outside canonical player order", () => {
  const state = runtime.createWaitingMatchState(["player-a", "player-b"]);
  const logger = {info() {}, warn() {}, error() {}};
  const result = runtime.sprintMatchJoinAttempt(
    null,
    logger,
    null,
    null,
    0,
    state,
    {userId: "outsider"},
    {}
  );

  assert.equal(result.accept, false);
  assert.equal(result.rejectMessage, "This user was not assigned to this match.");
});
