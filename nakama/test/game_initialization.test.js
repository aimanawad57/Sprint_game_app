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
    "initializeRematchRound," +
    "handleRematchDecision," +
    "rematchTimeoutMs," +
    "disconnectTimeoutMs," +
    "rttEmaAlpha," +
    "buildPlayerStateView," +
    "buildConnectionChangedPayload," +
    "recordPlayerRttSample," +
    "calculateElapsedTimeMs," +
    "applySubmitMove," +
    "cardsMatch," +
    "hasAnyLegalMove," +
    "isGameStuck," +
    "reshuffleCenterPiles," +
    "replaceSingleCardPilesFromPlayerDecks," +
    "resolveStuckState," +
    "resolveAndBroadcastStuckState," +
    "resolveDisconnectTimeout," +
    "abandonMatch," +
    "moveFairnessWindowMs," +
    "computeFairnessWindowMs," +
    "validateSubmitMoveCandidate," +
    "collectReadyPendingSubmitMoves," +
    "applyPendingSubmitMoveBatch," +
    "shouldTerminateSprintMatch," +
    "waitingMatchTimeoutMs," +
    "activeIdleTimeoutMs," +
    "finishedEmptyGraceMs," +
    "persistPendingMatchResult," +
    "ensureSprintWinsLeaderboard," +
    "writeSprintWinsLeaderboardRecord," +
    "rpcGetWinsLeaderboard," +
    "rpcGetOrCreateProfile," +
    "rpcGetOnboardingProgress," +
    "rpcMergeOnboardingProgress," +
    "sprintMatchJoinAttempt," +
    "sprintMatchJoin," +
    "sprintMatchLeave," +
    "sprintMatchLoop," +
    "MatchStatus," +
    "MatchEndReason," +
    "CardColor," +
    "CardShape," +
    "ClientOpcode," +
    "ServerOpcode," +
    "MoveRejectionReason," +
    "PileId" +
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

function readCardMatchCases() {
  const fixturePath = path.resolve(
    __dirname,
    "../../docs/game-contract/card-match-cases.json"
  );
  const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
  assert.equal(fixture.schemaVersion, 1);
  assert.equal(Array.isArray(fixture.cases), true);
  return fixture.cases;
}

function createConnectedWaitingState(runtime) {
  const state = runtime.createWaitingMatchState(["player-a", "player-b"]);
  state.players["player-a"].displayName = "Alice";
  state.players["player-b"].displayName = "Bob";
  state.players["player-a"].connected = true;
  state.players["player-b"].connected = true;
  state.presences["player-a"] = {userId: "player-a", username: "Alice"};
  state.presences["player-b"] = {userId: "player-b", username: "Bob"};
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

function createInitializedState(runtime) {
  const state = createConnectedWaitingState(runtime);
  runtime.initializeGameState(state, () => 0);
  return state;
}

function card(id, color, shape, count) {
  return {card_id: id, color, shape, count};
}

function seededRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 0x100000000;
  };
}

function onboardingStorage(initialValue) {
  let stored = initialValue ? {value: initialValue, version: "v1"} : undefined;
  return {
    nk: {
      storageRead() { return stored ? [stored] : []; },
      storageWrite(writes) {
        stored = {value: writes[0].value, version: "v2"};
      }
    },
    value() { return stored && stored.value; }
  };
}

function cardsMatchForTest(playedCard, topCard) {
  return (
    playedCard.color === topCard.color ||
    playedCard.shape === topCard.shape ||
    playedCard.count === topCard.count
  );
}

function findLegalMove(state) {
  const piles = [
    [runtime.PileId.Pile1, state.centerPiles.pile_1.at(-1)],
    [runtime.PileId.Pile2, state.centerPiles.pile_2.at(-1)]
  ];

  for (const userId of state.playerOrder) {
    for (const handCard of state.players[userId].hand) {
      for (const [pileId, topCard] of piles) {
        if (cardsMatchForTest(handCard, topCard)) {
          return {userId, cardId: handCard.card_id, pileId};
        }
      }
    }
  }

  return null;
}

function assertCardConservation(state) {
  const cards = collectStateCards(state);
  assert.equal(cards.length, 60);
  assert.equal(new Set(cards.map((entry) => entry.card_id)).size, 60);
}

function submitMoveMessage(runtime, userId, payload) {
  return {
    opCode: runtime.ClientOpcode.SubmitMove,
    sender: {userId, sessionId: userId + "-session"},
    data: JSON.stringify(payload)
  };
}

function validatedMove(runtime, state, userId, payload, receivedAtMs, sequence) {
  const result = runtime.validateSubmitMoveCandidate(
    state,
    {userId, sessionId: userId + "-session"},
    JSON.stringify(payload),
    receivedAtMs,
    sequence
  );
  assert.equal(result.accepted, true);
  return result.move;
}

const runtime = loadRuntimeForTest();

test("runtime card catalog matches the reviewed CSV exactly", () => {
  assert.deepEqual(normalize(runtime.CARD_CATALOG), readDocumentedCatalog());
});

test("server card matching agrees with the shared client contract cases", () => {
  const cases = readCardMatchCases();
  assert.ok(cases.length >= 6);
  cases.forEach((matchCase) => {
    assert.equal(
      runtime.cardsMatch(matchCase.playedCard, matchCase.topCard),
      matchCase.matches,
      matchCase.name
    );
  });
});

test("catalog validation enforces size, IDs, attributes, and count", () => {
  assert.doesNotThrow(() => runtime.validateCardCatalog(runtime.CARD_CATALOG));

  const missingCard = normalize(runtime.CARD_CATALOG).slice(0, -1);
  assert.throws(() => runtime.validateCardCatalog(missingCard), /expected 60 cards/);

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
  invalidCount[0].count = 6;
  assert.throws(() => runtime.validateCardCatalog(invalidCount), /invalid count/);
});

test("catalog validation allows duplicate attributes when IDs differ", () => {
  const catalog = normalize(runtime.CARD_CATALOG);
  catalog[59].color = catalog[0].color;
  catalog[59].shape = catalog[0].shape;
  catalog[59].count = catalog[0].count;
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
  assert.equal(state.players["player-a"].deck.length, 26);
  assert.equal(state.players["player-b"].hand.length, 3);
  assert.equal(state.players["player-b"].deck.length, 26);
  assert.equal(state.centerPiles.pile_1.length, 1);
  assert.equal(state.centerPiles.pile_2.length, 1);

  const allCards = collectStateCards(state);
  assert.equal(allCards.length, 60);
  assert.equal(new Set(allCards.map((card) => card.card_id)).size, 60);
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
  assert.equal(viewA.myDeckCount, 26);
  assert.equal(viewA.opponentHandCount, 3);
  assert.equal(viewA.opponentDeckCount, 26);
  assert.equal("deck" in viewA, false);
  assert.equal("opponentHand" in viewA, false);
  assert.equal("opponentDeck" in viewA, false);
  assert.deepEqual(normalize(viewA.centerPiles), normalize(viewB.centerPiles));
  assert.equal(viewA.stateVersion, 1);
  assert.equal(viewA.status, runtime.MatchStatus.Active);
  assert.equal(viewA.winnerName, null);
  assert.deepEqual(normalize(viewA.transitions), []);
  assert.equal(viewA.myRttEstimateMs, null);
  assert.equal(viewA.myRttSampleSequence, 0);

  const originalStateColor = state.players["player-a"].hand[0].color;
  viewA.myHand[0].color = runtime.CardColor.Purple;
  assert.equal(state.players["player-a"].hand[0].color, originalStateColor);
  assert.throws(
    () => runtime.buildPlayerStateView(state, "outsider"),
    /outside the match/
  );
});

test("player views expose only the viewer RTT and viewer-relative public transitions", () => {
  const state = createInitializedState(runtime);
  state.players["player-a"].rttEstimateMs = 237.9;
  state.players["player-a"].rttSampleSequence = 4;
  state.players["player-b"].rttEstimateMs = 481.2;
  state.players["player-b"].rttSampleSequence = 9;
  const transitions = [
    {
      type: "card_played",
      playerId: "player-b",
      card: card(
        "public_b_move",
        runtime.CardColor.Green,
        runtime.CardShape.Star,
        3
      ),
      targetPileId: runtime.PileId.Pile2
    },
    {
      type: "card_played",
      playerId: "player-a",
      card: card(
        "public_a_move",
        runtime.CardColor.Red,
        runtime.CardShape.Circle,
        2
      ),
      targetPileId: runtime.PileId.Pile1
    }
  ];

  const viewA = runtime.buildPlayerStateView(state, "player-a", 5000, transitions);
  const viewB = runtime.buildPlayerStateView(state, "player-b", 5000, transitions);

  assert.equal(viewA.myRttEstimateMs, 237);
  assert.equal(viewB.myRttEstimateMs, 481);
  assert.equal(viewA.myRttSampleSequence, 4);
  assert.equal(viewB.myRttSampleSequence, 9);
  assert.deepEqual(
    normalize(viewA.transitions.map((transition) => transition.actor)),
    ["opponent", "self"]
  );
  assert.deepEqual(
    normalize(viewB.transitions.map((transition) => transition.actor)),
    ["self", "opponent"]
  );
  assert.deepEqual(
    normalize(viewA.transitions.map((transition) => transition.card.card_id)),
    ["public_b_move", "public_a_move"]
  );
  assert.equal(viewA.transitions[0].targetPileId, runtime.PileId.Pile2);
  assert.equal("playerId" in viewA.transitions[0], false);
  assert.equal(JSON.stringify(viewA).includes("481.2"), false);
  assert.equal(JSON.stringify(viewA).includes('"myRttSampleSequence":9'), false);

  viewA.transitions[0].card.color = runtime.CardColor.Purple;
  assert.equal(transitions[0].card.color, runtime.CardColor.Green);
});

test("RTT samples use an EMA and advance freshness even when the value repeats", () => {
  const state = createInitializedState(runtime);
  const player = state.players["player-a"];

  runtime.recordPlayerRttSample(player, 100);
  assert.equal(player.rttEstimateMs, 100);
  assert.equal(player.rttSampleSequence, 1);

  runtime.recordPlayerRttSample(player, 100);
  assert.equal(player.rttEstimateMs, 100);
  assert.equal(player.rttSampleSequence, 2);

  runtime.recordPlayerRttSample(player, 300);
  assert.equal(runtime.rttEmaAlpha, 0.25);
  assert.equal(player.rttEstimateMs, 150);
  assert.equal(player.rttSampleSequence, 3);

  const ownView = runtime.buildPlayerStateView(state, "player-a");
  const opponentView = runtime.buildPlayerStateView(state, "player-b");
  assert.equal(ownView.myRttEstimateMs, 150);
  assert.equal(ownView.myRttSampleSequence, 3);
  assert.equal(opponentView.myRttEstimateMs, null);
  assert.equal(opponentView.myRttSampleSequence, 0);

  // A live state created by an older runtime may not have the new fields yet.
  // The first post-upgrade sample should initialize them instead of producing
  // NaN values.
  player.rttEstimateMs = undefined;
  player.rttSampleSequence = undefined;
  runtime.recordPlayerRttSample(player, 80);
  assert.equal(player.rttEstimateMs, 80);
  assert.equal(player.rttSampleSequence, 1);
});

test("elapsed match time is authoritative and never negative", () => {
  const state = createConnectedWaitingState(runtime);
  runtime.initializeGameState(state, () => 0.25, 10_000);

  assert.equal(runtime.calculateElapsedTimeMs(state, 47_250), 37_250);
  assert.equal(
    runtime.buildPlayerStateView(state, "player-a", 47_250).elapsedTimeMs,
    37_250
  );

  state.status = runtime.MatchStatus.Finished;
  state.endedAtMs = 51_999;
  assert.equal(runtime.calculateElapsedTimeMs(state, 90_000), 41_999);

  state.startedAtMs = null;
  assert.equal(runtime.calculateElapsedTimeMs(state, 90_000), 0);

  state.startedAtMs = 100_000;
  state.status = runtime.MatchStatus.Active;
  state.endedAtMs = null;
  assert.equal(runtime.calculateElapsedTimeMs(state, 90_000), 0);
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
  const presenceA = {userId: "player-a", sessionId: "session-a", username: "Alice"};
  const presenceB = {userId: "player-b", sessionId: "session-b", username: "Bob"};

  runtime.sprintMatchJoin(null, logger, null, dispatcher, 1, state, [presenceA]);
  assert.equal(state.status, runtime.MatchStatus.Waiting);
  assert.equal(state.stateVersion, 0);
  assert.deepEqual(calls.map((call) => call.opcode), [runtime.ServerOpcode.ConnectionChanged]);

  runtime.sprintMatchJoin(null, logger, null, dispatcher, 2, state, [presenceB]);
  assert.equal(state.status, runtime.MatchStatus.Waiting);
  assert.equal(state.stateVersion, 0);
  assert.notEqual(state.roundStartsAtMs, null);
  assert.deepEqual(calls.map((call) => call.opcode), [
    runtime.ServerOpcode.ConnectionChanged,
    runtime.ServerOpcode.ConnectionChanged,
    runtime.ServerOpcode.RematchStatus,
  ]);
  assert.equal(calls[2].data.status, "starting");
  assert.equal(calls[2].data.roundNumber, 1);
  assert.equal(calls[2].data.startsInMs, 5000);
  assert.equal(calls[2].data.startsAtMs - calls[2].data.serverTimeMs, 5000);

  state.roundStartsAtMs = Date.now() - 1;
  runtime.sprintMatchLoop(null, logger, null, dispatcher, 3, state, []);
  assert.equal(state.status, runtime.MatchStatus.Active);
  assert.equal(state.stateVersion, 1);
  assert.deepEqual(calls.map((call) => call.opcode), [
    runtime.ServerOpcode.ConnectionChanged,
    runtime.ServerOpcode.ConnectionChanged,
    runtime.ServerOpcode.RematchStatus,
    runtime.ServerOpcode.MatchStarted,
    runtime.ServerOpcode.MatchStarted,
  ]);

  const startedA = calls[3];
  const startedB = calls[4];
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
  assert.equal(startedA.data.winnerName, null);
  assert.equal(startedA.data.myRttSampleSequence, 0);
  assert.notEqual(state.players["player-a"].lastStateSentAtMs, null);
  assert.equal(
    state.players["player-a"].lastStateSentAtMs,
    state.players["player-b"].lastStateSentAtMs
  );
  assert.equal(state.players["player-a"].displayName, "Alice");
  assert.equal(state.players["player-b"].displayName, "Bob");

  const cardSnapshot = normalize(collectStateCards(state));
  runtime.sprintMatchLeave(null, logger, null, dispatcher, 4, state, [presenceA]);
  const disconnected = calls.at(-1);
  assert.equal(disconnected.opcode, runtime.ServerOpcode.ConnectionChanged);
  assert.equal(
    disconnected.data.disconnectDeadlineMs - disconnected.data.serverTimeMs,
    runtime.disconnectTimeoutMs
  );
  assert.equal(disconnected.data.disconnectGraceMs, runtime.disconnectTimeoutMs);
  state.players["player-a"].lastStateSentAtMs = 123;
  state.players["player-b"].lastStateSentAtMs = 456;
  runtime.sprintMatchJoin(null, logger, null, dispatcher, 5, state, [presenceA]);
  const reconnected = calls
    .filter((call) => call.opcode === runtime.ServerOpcode.ConnectionChanged)
    .at(-1);
  assert.equal(reconnected.data.disconnectDeadlineMs, null);
  assert.equal(typeof reconnected.data.serverTimeMs, "number");
  assert.equal(reconnected.data.disconnectGraceMs, runtime.disconnectTimeoutMs);
  assert.ok(state.players["player-a"].lastStateSentAtMs > 123);
  assert.equal(state.players["player-b"].lastStateSentAtMs, 456);
  assert.equal(state.stateVersion, 1);
  assert.deepEqual(normalize(collectStateCards(state)), cardSnapshot);
  assert.equal(
    calls.filter((call) => call.opcode === runtime.ServerOpcode.MatchStarted).length,
    2
  );
  const resyncCalls = calls.filter(
    (call) => call.opcode === runtime.ServerOpcode.StateUpdate
  );
  assert.equal(resyncCalls.length, 1);
  assert.strictEqual(resyncCalls[0].presences[0], presenceA);
  assert.deepEqual(
    normalize(resyncCalls[0].data.myHand),
    normalize(state.players["player-a"].hand)
  );
  assert.equal(resyncCalls[0].data.stateVersion, 1);
  assert.deepEqual(normalize(resyncCalls[0].data.transitions), []);
});

test("connection payload uses the earliest authoritative disconnect deadline", () => {
  const state = createInitializedState(runtime);
  state.players["player-a"].connected = false;
  state.players["player-a"].disconnectedAtMs = 1500;
  state.players["player-b"].connected = false;
  state.players["player-b"].disconnectedAtMs = 1000;
  delete state.presences["player-a"];
  delete state.presences["player-b"];

  const payload = runtime.buildConnectionChangedPayload(state, [], 7000);

  assert.equal(payload.serverTimeMs, 7000);
  assert.equal(payload.disconnectDeadlineMs, 1000 + runtime.disconnectTimeoutMs);
  assert.equal(payload.disconnectGraceMs, runtime.disconnectTimeoutMs);
  assert.equal(payload.connectedCount, 0);

  state.status = runtime.MatchStatus.Finished;
  assert.equal(
    runtime.buildConnectionChangedPayload(state, [], 8000).disconnectDeadlineMs,
    null
  );
});

test("player views use account display names instead of generated presence usernames", () => {
  const state = runtime.createWaitingMatchState(["player-a", "player-b"]);
  const calls = [];
  const dispatcher = {
    broadcastMessage(opcode, data, presences) {
      calls.push({opcode, data: JSON.parse(data), presences});
    },
  };
  const logger = {info() {}, warn() {}, error() {}};
  const nk = {
    accountGetId(userId) {
      return {
        user: {
          displayName: userId === "player-a" ? "Mohammed" : "Aiman"
        }
      };
    }
  };
  const presenceA = {
    userId: "player-a",
    sessionId: "session-a",
    username: "KllCnnRBkQ"
  };
  const presenceB = {
    userId: "player-b",
    sessionId: "session-b",
    username: "RandomUserName"
  };

  runtime.sprintMatchJoin(null, logger, nk, dispatcher, 1, state, [
    presenceA,
    presenceB
  ]);

  assert.equal(state.players["player-a"].displayName, "Mohammed");
  assert.equal(state.players["player-b"].displayName, "Aiman");

  state.roundStartsAtMs = Date.now() - 1;
  runtime.sprintMatchLoop(null, logger, nk, dispatcher, 2, state, []);
  state.status = runtime.MatchStatus.Finished;
  state.winnerId = "player-a";
  const view = runtime.buildPlayerStateView(state, "player-b");
  assert.equal(view.winnerName, "Mohammed");
});

test("a player rejoining the initial countdown receives its remaining deadline", () => {
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

  runtime.sprintMatchJoin(null, logger, null, dispatcher, 1, state, [
    presenceA,
    presenceB,
  ]);
  const originalDeadline = state.roundStartsAtMs;
  runtime.sprintMatchLeave(null, logger, null, dispatcher, 2, state, [presenceB]);

  const rejoinedB = {userId: "player-b", sessionId: "session-b-new"};
  runtime.sprintMatchJoin(null, logger, null, dispatcher, 3, state, [rejoinedB]);

  const countdown = calls.at(-1);
  assert.equal(countdown.opcode, runtime.ServerOpcode.RematchStatus);
  assert.equal(countdown.data.status, "starting");
  assert.equal(countdown.data.startsAtMs, originalDeadline);
  assert.equal(countdown.presences.length, 1);
  assert.strictEqual(countdown.presences[0], rejoinedB);
});

test("reconnection replaces the presence and ignores a delayed old-session leave", () => {
  const state = createInitializedState(runtime);
  const calls = [];
  const dispatcher = {
    broadcastMessage(opcode, data, presences) {
      calls.push({opcode, data: JSON.parse(data), presences});
    },
  };
  const logger = {info() {}, warn() {}, error() {}};
  const oldPresence = {
    userId: "player-a",
    sessionId: "player-a-old-session"
  };
  const newPresence = {
    userId: "player-a",
    sessionId: "player-a-new-session"
  };
  state.presences["player-a"] = oldPresence;
  state.presences["player-b"] = {
    userId: "player-b",
    sessionId: "player-b-session"
  };
  const cardsBeforeReconnect = normalize(collectStateCards(state));
  const versionBeforeReconnect = state.stateVersion;

  runtime.sprintMatchJoin(
    null,
    logger,
    null,
    dispatcher,
    10,
    state,
    [newPresence]
  );
  runtime.sprintMatchLeave(
    null,
    logger,
    null,
    dispatcher,
    11,
    state,
    [oldPresence]
  );

  assert.strictEqual(state.presences["player-a"], newPresence);
  assert.equal(state.players["player-a"].connected, true);
  assert.equal(state.stateVersion, versionBeforeReconnect);
  assert.deepEqual(normalize(collectStateCards(state)), cardsBeforeReconnect);
  assert.deepEqual(calls.map((call) => call.opcode), [
    runtime.ServerOpcode.ConnectionChanged,
    runtime.ServerOpcode.StateUpdate
  ]);
  assert.strictEqual(calls[1].presences[0], newPresence);
});

test("finished matches resynchronize privately without persisting results twice", () => {
  const state = createInitializedState(runtime);
  const dispatcherCalls = [];
  const dispatcher = {
    broadcastMessage(opcode, data, presences) {
      dispatcherCalls.push({opcode, data: JSON.parse(data), presences});
    },
  };
  const logger = {info() {}, warn() {}, error() {}};
  const reconnectingPresence = {
    userId: "player-a",
    sessionId: "finished-reconnect-session"
  };
  state.status = runtime.MatchStatus.Finished;
  state.winnerId = "player-a";
  state.resultPersisted = true;
  state.resultPersistencePending = false;
  const versionBeforeReconnect = state.stateVersion;

  runtime.sprintMatchJoin(
    null,
    logger,
    null,
    dispatcher,
    20,
    state,
    [reconnectingPresence]
  );

  const update = dispatcherCalls.find(
    (call) => call.opcode === runtime.ServerOpcode.StateUpdate
  );
  assert.ok(update);
  assert.strictEqual(update.presences[0], reconnectingPresence);
  assert.equal(update.data.status, runtime.MatchStatus.Finished);
  assert.equal(update.data.winnerId, "player-a");
  assert.equal(update.data.winnerName, "Alice");
  assert.equal(update.data.stateVersion, versionBeforeReconnect);
  assert.equal(state.resultPersisted, true);
  assert.equal(state.resultPersistencePending, false);
});

test("disconnect timeout does not finish before 30 seconds and reconnect clears timer", () => {
  const state = createInitializedState(runtime);
  state.players["player-b"].connected = false;
  state.players["player-b"].disconnectedAtMs = 1000;
  delete state.presences["player-b"];

  assert.deepEqual(
    normalize(runtime.resolveDisconnectTimeout(state, 30_999)),
    {finished: false, reason: null}
  );
  assert.equal(state.status, runtime.MatchStatus.Active);

  const dispatcher = {broadcastMessage() {}};
  const logger = {info() {}, warn() {}, error() {}};
  runtime.sprintMatchJoin(
    null,
    logger,
    null,
    dispatcher,
    10,
    state,
    [{userId: "player-b", sessionId: "player-b-reconnect"}]
  );

  assert.equal(state.players["player-b"].connected, true);
  assert.equal(state.players["player-b"].disconnectedAtMs, null);
  assert.deepEqual(
    normalize(runtime.resolveDisconnectTimeout(state, 40_000)),
    {finished: false, reason: null}
  );
});

test("disconnect timeout declares the connected opponent winner by forfeit", () => {
  const state = createInitializedState(runtime);
  state.players["player-b"].connected = false;
  state.players["player-b"].disconnectedAtMs = 1000;
  delete state.presences["player-b"];
  const versionBeforeTimeout = state.stateVersion;

  const result = runtime.resolveDisconnectTimeout(state, 31_000);

  assert.deepEqual(normalize(result), {
    finished: true,
    reason: runtime.MatchEndReason.Forfeit
  });
  assert.equal(state.status, runtime.MatchStatus.Finished);
  assert.equal(state.winnerId, "player-a");
  assert.equal(state.endReason, runtime.MatchEndReason.Forfeit);
  assert.equal(state.stateVersion, versionBeforeTimeout + 1);
  assert.equal(state.resultPersistencePending, true);
  assert.equal(state.resultPersisted, false);
});

test("disconnect timeout abandons when both players are disconnected", () => {
  const state = createInitializedState(runtime);
  state.playerOrder.forEach((userId) => {
    state.players[userId].connected = false;
    state.players[userId].disconnectedAtMs = 1000;
    delete state.presences[userId];
  });
  const versionBeforeTimeout = state.stateVersion;

  const result = runtime.resolveDisconnectTimeout(state, 31_000);

  assert.deepEqual(normalize(result), {
    finished: true,
    reason: runtime.MatchEndReason.Abandoned
  });
  assert.equal(state.status, runtime.MatchStatus.Finished);
  assert.equal(state.winnerId, null);
  assert.equal(state.endReason, runtime.MatchEndReason.Abandoned);
  assert.equal(state.stateVersion, versionBeforeTimeout + 1);
  assert.equal(state.resultPersistencePending, false);
});

test("disconnect timeout does not apply while waiting", () => {
  const state = runtime.createWaitingMatchState(["player-a", "player-b"]);
  state.players["player-a"].connected = false;
  state.players["player-a"].disconnectedAtMs = 1000;

  assert.deepEqual(
    normalize(runtime.resolveDisconnectTimeout(state, 31_000)),
    {finished: false, reason: null}
  );
  assert.equal(state.status, runtime.MatchStatus.Waiting);
});

test("explicit abandon immediately forfeits the sender", () => {
  const state = createInitializedState(runtime);
  const versionBeforeAbandon = state.stateVersion;

  assert.equal(
    runtime.abandonMatch(state, {userId: "player-b"}, 5000),
    true
  );

  assert.equal(state.status, runtime.MatchStatus.Finished);
  assert.equal(state.winnerId, "player-a");
  assert.equal(state.endReason, runtime.MatchEndReason.Forfeit);
  assert.equal(state.endedAtMs, 5000);
  assert.equal(state.stateVersion, versionBeforeAbandon + 1);
  assert.equal(state.resultPersistencePending, true);
  assert.equal(runtime.abandonMatch(state, {userId: "player-b"}, 6000), false);
  assert.equal(runtime.abandonMatch(state, {userId: "outsider"}, 6000), false);
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

test("applySubmitMove accepts a legal move, draws replacement, and increments version", () => {
  const state = createInitializedState(runtime);
  const player = state.players["player-a"];
  const playedCard = player.hand[0];
  const replacementCard = player.deck[player.deck.length - 1];
  state.centerPiles.pile_1 = [
    card("pile_top", playedCard.color, runtime.CardShape.Flag, 5)
  ];
  const beforeVersion = state.stateVersion;

  const result = runtime.applySubmitMove(
    state,
    {userId: "player-a"},
    JSON.stringify({
      card_id: playedCard.card_id,
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: beforeVersion
    })
  );

  assert.equal(result.accepted, true);
  assert.equal(result.gameEnded, false);
  assert.equal(state.stateVersion, beforeVersion + 1);
  assert.equal(state.centerPiles.pile_1.at(-1).card_id, playedCard.card_id);
  assert.equal(player.hand.length, 3);
  assert.equal(player.hand.some((handCard) => handCard.card_id === playedCard.card_id), false);
  assert.equal(player.hand.some((handCard) => handCard.card_id === replacementCard.card_id), true);
  assert.equal(player.deck.length, 25);
});

test("applySubmitMove rejects inactive match, unknown player, missing card, bad pile, and mismatch", () => {
  const state = createInitializedState(runtime);
  const player = state.players["player-a"];
  const playedCard = player.hand[0];

  const inactive = normalize(state);
  inactive.status = runtime.MatchStatus.Waiting;
  assert.equal(
    runtime.applySubmitMove(
      inactive,
      {userId: "player-a"},
      JSON.stringify({
        card_id: playedCard.card_id,
        targetPileId: runtime.PileId.Pile1,
        expectedStateVersion: inactive.stateVersion
      })
    ).rejection.reason,
    runtime.MoveRejectionReason.MatchNotActive
  );

  assert.equal(
    runtime.applySubmitMove(
      state,
      {userId: "outsider"},
      JSON.stringify({
        card_id: playedCard.card_id,
        targetPileId: runtime.PileId.Pile1,
        expectedStateVersion: state.stateVersion
      })
    ).rejection.reason,
    runtime.MoveRejectionReason.PlayerNotInMatch
  );

  assert.equal(
    runtime.applySubmitMove(
      state,
      {userId: "player-a"},
      JSON.stringify({
        card_id: "not_in_hand",
        targetPileId: runtime.PileId.Pile1,
        expectedStateVersion: state.stateVersion
      })
    ).rejection.reason,
    runtime.MoveRejectionReason.CardNotInHand
  );

  assert.equal(
    runtime.applySubmitMove(
      state,
      {userId: "player-a"},
      JSON.stringify({
        card_id: playedCard.card_id,
        targetPileId: "pile_3",
        expectedStateVersion: state.stateVersion
      })
    ).rejection.reason,
    runtime.MoveRejectionReason.InvalidTargetPile
  );

  state.centerPiles.pile_1 = [
    card("pile_top", runtime.CardColor.Purple, runtime.CardShape.Flag, 5)
  ];
  player.hand[0] = card("unmatched", runtime.CardColor.Red, runtime.CardShape.Star, 1);
  assert.equal(
    runtime.applySubmitMove(
      state,
      {userId: "player-a"},
      JSON.stringify({
        card_id: "unmatched",
        targetPileId: runtime.PileId.Pile1,
        expectedStateVersion: state.stateVersion
      })
    ).rejection.reason,
    runtime.MoveRejectionReason.CardDoesNotMatch
  );
});

test("applySubmitMove rejects moves while either player is disconnected", () => {
  const payloadFor = (state) =>
    JSON.stringify({
      card_id: state.players["player-a"].hand[0].card_id,
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion
    });

  const opponentDisconnected = createInitializedState(runtime);
  const opponentVersion = opponentDisconnected.stateVersion;
  opponentDisconnected.players["player-b"].connected = false;
  delete opponentDisconnected.presences["player-b"];

  const opponentResult = runtime.applySubmitMove(
    opponentDisconnected,
    {userId: "player-a"},
    payloadFor(opponentDisconnected)
  );

  assert.equal(opponentResult.accepted, false);
  assert.equal(
    opponentResult.rejection.reason,
    runtime.MoveRejectionReason.PlayerDisconnected
  );
  assert.equal(opponentDisconnected.stateVersion, opponentVersion);

  const senderConnectionMissing = createInitializedState(runtime);
  const senderVersion = senderConnectionMissing.stateVersion;
  senderConnectionMissing.players["player-a"].connected = false;
  delete senderConnectionMissing.presences["player-a"];

  const senderResult = runtime.applySubmitMove(
    senderConnectionMissing,
    {userId: "player-a"},
    payloadFor(senderConnectionMissing)
  );

  assert.equal(senderResult.accepted, false);
  assert.equal(
    senderResult.rejection.reason,
    runtime.MoveRejectionReason.PlayerDisconnected
  );
  assert.equal(senderConnectionMissing.stateVersion, senderVersion);
});

test("stale moves are revalidated against the current authoritative pile", () => {
  const stillLegal = createInitializedState(runtime);
  const legalPlayer = stillLegal.players["player-a"];
  const legalCard = legalPlayer.hand[0];
  stillLegal.stateVersion = 9;
  stillLegal.centerPiles.pile_1 = [
    card("current_top", legalCard.color, runtime.CardShape.Flag, 5)
  ];

  const accepted = runtime.applySubmitMove(
    stillLegal,
    {userId: "player-a"},
    JSON.stringify({
      card_id: legalCard.card_id,
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: 8
    })
  );

  assert.equal(accepted.accepted, true);
  assert.equal(stillLegal.stateVersion, 10);

  const noLongerLegal = createInitializedState(runtime);
  noLongerLegal.stateVersion = 12;
  noLongerLegal.players["player-a"].hand[0] = card(
    "stale_card",
    runtime.CardColor.Red,
    runtime.CardShape.Star,
    1
  );
  noLongerLegal.centerPiles.pile_1 = [
    card(
      "changed_top",
      runtime.CardColor.Purple,
      runtime.CardShape.Flag,
      5
    )
  ];
  const stateBeforeRejection = normalize(noLongerLegal);

  const rejected = runtime.applySubmitMove(
    noLongerLegal,
    {userId: "player-a"},
    JSON.stringify({
      card_id: "stale_card",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: 11
    })
  );

  assert.equal(rejected.accepted, false);
  assert.equal(
    rejected.rejection.reason,
    runtime.MoveRejectionReason.CardDoesNotMatch
  );
  assert.deepEqual(normalize(noLongerLegal), stateBeforeRejection);
});

test("applySubmitMove ends the game when the last hand card is played with no deck", () => {
  const state = createInitializedState(runtime);
  const player = state.players["player-a"];
  player.hand = [card("last_card", runtime.CardColor.Red, runtime.CardShape.Star, 1)];
  player.deck = [];
  state.centerPiles.pile_1 = [
    card("pile_top", runtime.CardColor.Red, runtime.CardShape.Flag, 5)
  ];

  const result = runtime.applySubmitMove(
    state,
    {userId: "player-a"},
    JSON.stringify({
      card_id: "last_card",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion
    })
  );

  assert.equal(result.accepted, true);
  assert.equal(result.gameEnded, true);
  assert.equal(state.status, runtime.MatchStatus.Finished);
  assert.equal(state.winnerId, "player-a");
});

test("pending move batch accepts valid moves on different piles together", () => {
  const state = createInitializedState(runtime);
  const versionBeforeMove = state.stateVersion;
  state.players["player-a"].hand = [
    card("player_a_move", runtime.CardColor.Red, runtime.CardShape.Star, 1)
  ];
  state.players["player-a"].deck = [
    card("player_a_replacement", runtime.CardColor.Blue, runtime.CardShape.Circle, 4)
  ];
  state.players["player-b"].hand = [
    card("player_b_move", runtime.CardColor.Green, runtime.CardShape.Diamond, 2)
  ];
  state.players["player-b"].deck = [
    card("player_b_replacement", runtime.CardColor.Purple, runtime.CardShape.House, 5)
  ];
  state.centerPiles.pile_1 = [
    card("pile_1_top", runtime.CardColor.Red, runtime.CardShape.Flag, 5)
  ];
  state.centerPiles.pile_2 = [
    card("pile_2_top", runtime.CardColor.Green, runtime.CardShape.Flag, 5)
  ];

  const moveA = validatedMove(
    runtime,
    state,
    "player-a",
    {
      card_id: "player_a_move",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: versionBeforeMove
    },
    1000,
    0
  );
  const moveB = validatedMove(
    runtime,
    state,
    "player-b",
    {
      card_id: "player_b_move",
      targetPileId: runtime.PileId.Pile2,
      expectedStateVersion: versionBeforeMove
    },
    1050,
    1
  );

  // Deliberately reverse the input to prove transitions follow authoritative
  // reaction-adjusted resolution order rather than array/inbox order.
  const result = runtime.applyPendingSubmitMoveBatch(state, [moveB, moveA], 1200);

  assert.equal(result.changed, true);
  assert.equal(result.gameEnded, false);
  assert.deepEqual(normalize(result.acceptedPlayerIds), ["player-a", "player-b"]);
  assert.deepEqual(
    normalize(result.transitions),
    [
      {
        type: "card_played",
        playerId: "player-a",
        card: {
          card_id: "player_a_move",
          color: runtime.CardColor.Red,
          shape: runtime.CardShape.Star,
          count: 1
        },
        targetPileId: runtime.PileId.Pile1
      },
      {
        type: "card_played",
        playerId: "player-b",
        card: {
          card_id: "player_b_move",
          color: runtime.CardColor.Green,
          shape: runtime.CardShape.Diamond,
          count: 2
        },
        targetPileId: runtime.PileId.Pile2
      }
    ]
  );
  assert.equal(result.rejections.length, 0);
  assert.equal(state.stateVersion, versionBeforeMove + 1);
  assert.equal(state.centerPiles.pile_1.at(-1).card_id, "player_a_move");
  assert.equal(state.centerPiles.pile_2.at(-1).card_id, "player_b_move");
});

test("same-pile conflict is won by reaction-adjusted time, not arrival order", () => {
  const state = createInitializedState(runtime);
  state.players["player-a"].lastStateSentAtMs = 1000;
  state.players["player-b"].lastStateSentAtMs = 1000;
  state.nextTieBreakerPlayerId = "player-a";
  state.players["player-a"].hand = [
    card("player_a_move", runtime.CardColor.Red, runtime.CardShape.Star, 1)
  ];
  state.players["player-b"].hand = [
    card("player_b_move", runtime.CardColor.Red, runtime.CardShape.Diamond, 2)
  ];
  state.centerPiles.pile_1 = [
    card("pile_1_top", runtime.CardColor.Red, runtime.CardShape.Flag, 5)
  ];

  // player-a: fast network (arrives first) but slow reaction (45ms).
  const fastNetworkSlowReaction = validatedMove(
    runtime,
    state,
    "player-a",
    {
      card_id: "player_a_move",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion,
      reactionTimeMs: 45
    },
    1050,
    0
  );
  // player-b: slow network (arrives 70ms later) but fast reaction (20ms).
  const slowNetworkFastReaction = validatedMove(
    runtime,
    state,
    "player-b",
    {
      card_id: "player_b_move",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion,
      reactionTimeMs: 20
    },
    1120,
    1
  );

  assert.equal(fastNetworkSlowReaction.effectiveResponseTimeMs, 1045);
  assert.equal(slowNetworkFastReaction.effectiveResponseTimeMs, 1020);

  const result = runtime.applyPendingSubmitMoveBatch(
    state,
    [fastNetworkSlowReaction, slowNetworkFastReaction],
    1300
  );

  // player-b wins the pile despite their move physically arriving later.
  assert.deepEqual(normalize(result.acceptedPlayerIds), ["player-b"]);
  assert.equal(result.rejections.length, 1);
  assert.equal(
    result.rejections[0].rejection.reason,
    runtime.MoveRejectionReason.StaleMove
  );
  assert.equal(state.centerPiles.pile_1.at(-1).card_id, "player_b_move");
  // A clear (non-tie) reaction-time winner must not consume the tie-breaker.
  assert.equal(state.nextTieBreakerPlayerId, "player-a");
});

test("an inflated reaction-time claim is clamped to the observed elapsed time", () => {
  const state = createInitializedState(runtime);
  state.players["player-a"].lastStateSentAtMs = 1000;
  state.players["player-a"].hand = [
    card("player_a_move", runtime.CardColor.Red, runtime.CardShape.Star, 1)
  ];
  state.centerPiles.pile_1 = [
    card("pile_1_top", runtime.CardColor.Red, runtime.CardShape.Flag, 5)
  ];

  const move = validatedMove(
    runtime,
    state,
    "player-a",
    {
      card_id: "player_a_move",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion,
      reactionTimeMs: 999999
    },
    1050,
    0
  );

  // Clamped to elapsed (1050 - 1000 = 50): a claim cannot beat physics.
  assert.equal(move.effectiveResponseTimeMs, 1050);
  assert.equal(move.networkRttEstimateMs, 0);
});

test("reaction timing uses each sender's private state-send anchor", () => {
  const state = createInitializedState(runtime);
  state.players["player-a"].lastStateSentAtMs = 1000;
  state.players["player-b"].lastStateSentAtMs = 2000;
  state.players["player-a"].hand = [
    card("player_a_move", runtime.CardColor.Red, runtime.CardShape.Star, 1)
  ];
  state.players["player-b"].hand = [
    card("player_b_move", runtime.CardColor.Green, runtime.CardShape.Flag, 3)
  ];
  state.centerPiles.pile_1 = [
    card("pile_1_top", runtime.CardColor.Red, runtime.CardShape.Flag, 5)
  ];
  state.centerPiles.pile_2 = [
    card("pile_2_top", runtime.CardColor.Green, runtime.CardShape.Circle, 2)
  ];

  const moveA = validatedMove(
    runtime,
    state,
    "player-a",
    {
      card_id: "player_a_move",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion,
      reactionTimeMs: 50
    },
    1100,
    0
  );
  const moveB = validatedMove(
    runtime,
    state,
    "player-b",
    {
      card_id: "player_b_move",
      targetPileId: runtime.PileId.Pile2,
      expectedStateVersion: state.stateVersion,
      reactionTimeMs: 50
    },
    2100,
    1
  );

  assert.equal(moveA.effectiveResponseTimeMs, 1050);
  assert.equal(moveA.networkRttEstimateMs, 50);
  assert.equal(moveB.effectiveResponseTimeMs, 2050);
  assert.equal(moveB.networkRttEstimateMs, 50);
});

test("a missing or malformed reaction time falls back to arrival order", () => {
  const state = createInitializedState(runtime);
  state.players["player-a"].lastStateSentAtMs = 1000;
  state.players["player-a"].hand = [
    card("player_a_move", runtime.CardColor.Red, runtime.CardShape.Star, 1),
    card("player_a_other", runtime.CardColor.Red, runtime.CardShape.Circle, 3)
  ];
  state.centerPiles.pile_1 = [
    card("pile_1_top", runtime.CardColor.Red, runtime.CardShape.Flag, 5)
  ];

  const withoutReaction = validatedMove(
    runtime,
    state,
    "player-a",
    {
      card_id: "player_a_move",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion
    },
    1080,
    0
  );
  assert.equal(withoutReaction.effectiveResponseTimeMs, 1080);
  assert.equal(withoutReaction.networkRttEstimateMs, null);

  const malformedReaction = validatedMove(
    runtime,
    state,
    "player-a",
    {
      card_id: "player_a_other",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion,
      reactionTimeMs: "instant"
    },
    1090,
    1
  );
  assert.equal(malformedReaction.effectiveResponseTimeMs, 1090);
  assert.equal(malformedReaction.networkRttEstimateMs, null);

  state.players["player-a"].lastStateSentAtMs = undefined;
  const legacyAnchor = validatedMove(
    runtime,
    state,
    "player-a",
    {
      card_id: "player_a_other",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion,
      reactionTimeMs: 75
    },
    1500,
    2
  );
  assert.equal(legacyAnchor.effectiveResponseTimeMs, 1500);
  assert.equal(legacyAnchor.networkRttEstimateMs, null);
});

test("reaction compensation only applies to moves responding to the current state version", () => {
  const state = createInitializedState(runtime);
  state.players["player-a"].lastStateSentAtMs = 1000;
  state.players["player-a"].hand = [
    card("player_a_move", runtime.CardColor.Red, runtime.CardShape.Star, 1)
  ];
  state.centerPiles.pile_1 = [
    card("pile_1_top", runtime.CardColor.Red, runtime.CardShape.Flag, 5)
  ];

  const staleVersionMove = validatedMove(
    runtime,
    state,
    "player-a",
    {
      card_id: "player_a_move",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion - 1,
      reactionTimeMs: 10
    },
    1100,
    0
  );

  assert.equal(staleVersionMove.effectiveResponseTimeMs, 1100);
  assert.equal(staleVersionMove.networkRttEstimateMs, null);
});

test("the fairness window is sized adaptively from the RTT gap between players", () => {
  const state = createInitializedState(runtime);

  // No measurements yet: fall back to the default window.
  assert.equal(runtime.computeFairnessWindowMs(state), runtime.moveFairnessWindowMs);

  // Only one player measured yet: a gap needs two data points, so still
  // fall back to the default window.
  state.players["player-a"].rttEstimateMs = 30;
  assert.equal(runtime.computeFairnessWindowMs(state), runtime.moveFairnessWindowMs);

  // Two low-latency players with a small gap: (40-30)/2 floors at the
  // minimum (100ms).
  state.players["player-b"].rttEstimateMs = 40;
  assert.equal(runtime.computeFairnessWindowMs(state), 100);

  // Both players equally (and highly) latent: no gap between them means no
  // compensation is needed, regardless of how high the shared latency is.
  state.players["player-a"].rttEstimateMs = 500;
  state.players["player-b"].rttEstimateMs = 500;
  assert.equal(runtime.computeFairnessWindowMs(state), 100);

  // A real latency gap widens the window to (400-30)/2 = 185ms.
  state.players["player-a"].rttEstimateMs = 30;
  state.players["player-b"].rttEstimateMs = 400;
  assert.equal(runtime.computeFairnessWindowMs(state), 185);

  // A very large gap is capped at the maximum (300ms).
  state.players["player-b"].rttEstimateMs = 900;
  assert.equal(runtime.computeFairnessWindowMs(state), 300);
});

test("same-pile fairness ties alternate between players", () => {
  const state = createInitializedState(runtime);
  state.nextTieBreakerPlayerId = "player-a";

  function setTieCards(suffix) {
    state.players["player-a"].hand = [
      card("player_a_move_" + suffix, runtime.CardColor.Red, runtime.CardShape.Star, 1)
    ];
    state.players["player-a"].deck = [
      card("player_a_replacement_" + suffix, runtime.CardColor.Blue, runtime.CardShape.Circle, 4)
    ];
    state.players["player-b"].hand = [
      card("player_b_move_" + suffix, runtime.CardColor.Red, runtime.CardShape.Diamond, 2)
    ];
    state.players["player-b"].deck = [
      card("player_b_replacement_" + suffix, runtime.CardColor.Purple, runtime.CardShape.House, 5)
    ];
    state.centerPiles.pile_1 = [
      card("pile_1_top_" + suffix, runtime.CardColor.Red, runtime.CardShape.Flag, 5)
    ];
  }

  setTieCards("first");
  const firstVersion = state.stateVersion;
  const firstMoveA = validatedMove(
    runtime,
    state,
    "player-a",
    {
      card_id: "player_a_move_first",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: firstVersion
    },
    1000,
    0
  );
  const firstMoveB = validatedMove(
    runtime,
    state,
    "player-b",
    {
      card_id: "player_b_move_first",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: firstVersion
    },
    1000,
    1
  );

  const firstResult = runtime.applyPendingSubmitMoveBatch(
    state,
    [firstMoveA, firstMoveB],
    1200
  );

  assert.deepEqual(normalize(firstResult.acceptedPlayerIds), ["player-a"]);
  assert.equal(firstResult.rejections.length, 1);
  assert.equal(
    firstResult.rejections[0].rejection.reason,
    runtime.MoveRejectionReason.StaleMove
  );
  assert.equal(state.centerPiles.pile_1.at(-1).card_id, "player_a_move_first");
  assert.equal(state.nextTieBreakerPlayerId, "player-b");

  setTieCards("second");
  const secondVersion = state.stateVersion;
  const secondMoveA = validatedMove(
    runtime,
    state,
    "player-a",
    {
      card_id: "player_a_move_second",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: secondVersion
    },
    2000,
    2
  );
  const secondMoveB = validatedMove(
    runtime,
    state,
    "player-b",
    {
      card_id: "player_b_move_second",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: secondVersion
    },
    2000,
    3
  );

  const secondResult = runtime.applyPendingSubmitMoveBatch(
    state,
    [secondMoveA, secondMoveB],
    2200
  );

  assert.deepEqual(normalize(secondResult.acceptedPlayerIds), ["player-b"]);
  assert.equal(secondResult.rejections.length, 1);
  assert.equal(state.centerPiles.pile_1.at(-1).card_id, "player_b_move_second");
  assert.equal(state.nextTieBreakerPlayerId, "player-a");
});

test("fairness window waits 150ms from the first queued move", () => {
  const state = createInitializedState(runtime);
  const versionBeforeMove = state.stateVersion;
  state.players["player-a"].hand = [
    card("player_a_move", runtime.CardColor.Red, runtime.CardShape.Star, 1)
  ];
  state.players["player-b"].hand = [
    card("player_b_move", runtime.CardColor.Green, runtime.CardShape.Diamond, 2)
  ];
  state.centerPiles.pile_1 = [
    card("pile_1_top", runtime.CardColor.Red, runtime.CardShape.Flag, 5)
  ];
  state.centerPiles.pile_2 = [
    card("pile_2_top", runtime.CardColor.Green, runtime.CardShape.Flag, 5)
  ];

  state.pendingMoves = [
    validatedMove(
      runtime,
      state,
      "player-a",
      {
        card_id: "player_a_move",
        targetPileId: runtime.PileId.Pile1,
        expectedStateVersion: versionBeforeMove
      },
      1000,
      0
    ),
    validatedMove(
      runtime,
      state,
      "player-b",
      {
        card_id: "player_b_move",
        targetPileId: runtime.PileId.Pile2,
        expectedStateVersion: versionBeforeMove
      },
      1149,
      1
    )
  ];

  const beforeDeadline = runtime.collectReadyPendingSubmitMoves(state, 1149);
  assert.deepEqual(normalize(beforeDeadline), []);
  assert.equal(state.pendingMoves.length, 2);

  const atDeadline = runtime.collectReadyPendingSubmitMoves(state, 1150);
  assert.deepEqual(
    normalize(atDeadline.map((move) => move.playerId)),
    ["player-a", "player-b"]
  );
  assert.equal(state.pendingMoves.length, 0);
});

test("moves after the first fairness window stay queued for the next batch", () => {
  const state = createInitializedState(runtime);
  const versionBeforeMove = state.stateVersion;
  state.players["player-a"].hand = [
    card("player_a_move", runtime.CardColor.Red, runtime.CardShape.Star, 1)
  ];
  state.players["player-b"].hand = [
    card("player_b_late_move", runtime.CardColor.Green, runtime.CardShape.Diamond, 2)
  ];
  state.centerPiles.pile_1 = [
    card("pile_1_top", runtime.CardColor.Red, runtime.CardShape.Flag, 5)
  ];
  state.centerPiles.pile_2 = [
    card("pile_2_top", runtime.CardColor.Green, runtime.CardShape.Flag, 5)
  ];

  state.pendingMoves = [
    validatedMove(
      runtime,
      state,
      "player-a",
      {
        card_id: "player_a_move",
        targetPileId: runtime.PileId.Pile1,
        expectedStateVersion: versionBeforeMove
      },
      1000,
      0
    ),
    validatedMove(
      runtime,
      state,
      "player-b",
      {
        card_id: "player_b_late_move",
        targetPileId: runtime.PileId.Pile2,
        expectedStateVersion: versionBeforeMove
      },
      1160,
      1
    )
  ];

  const readyMoves = runtime.collectReadyPendingSubmitMoves(state, 1150);
  assert.deepEqual(normalize(readyMoves.map((move) => move.playerId)), ["player-a"]);
  assert.deepEqual(
    normalize(state.pendingMoves.map((move) => move.playerId)),
    ["player-b"]
  );
});

test("duplicate pending move from the same player is rejected immediately", () => {
  const state = createInitializedState(runtime);
  const player = state.players["player-a"];
  const playedCard = player.hand[0];
  state.centerPiles.pile_1 = [
    card("pile_top", playedCard.color, runtime.CardShape.Flag, 5)
  ];
  const calls = [];
  const dispatcher = {
    broadcastMessage(opcode, data, presences) {
      calls.push({opcode, data: JSON.parse(data), presences});
    }
  };
  const logger = {info() {}, warn() {}, error() {}};
  const payload = {
    card_id: playedCard.card_id,
    targetPileId: runtime.PileId.Pile1,
    expectedStateVersion: state.stateVersion
  };

  runtime.sprintMatchLoop(null, logger, null, dispatcher, 1, state, [
    submitMoveMessage(runtime, "player-a", payload)
  ]);

  assert.equal(calls.length, 0);
  assert.equal(state.pendingMoves.length, 1);

  runtime.sprintMatchLoop(null, logger, null, dispatcher, 2, state, [
    submitMoveMessage(runtime, "player-a", payload)
  ]);

  assert.equal(state.pendingMoves.length, 1);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].opcode, runtime.ServerOpcode.MoveRejected);
  assert.equal(calls[0].data.reason, runtime.MoveRejectionReason.StaleMove);
  assert.equal(calls[0].presences[0].userId, "player-a");
});

test("late queued move is revalidated after an earlier batch changes the pile", () => {
  const state = createInitializedState(runtime);
  const versionBeforeMove = state.stateVersion;
  state.players["player-a"].hand = [
    card("player_a_move", runtime.CardColor.Purple, runtime.CardShape.Star, 1)
  ];
  state.players["player-a"].deck = [
    card("player_a_replacement", runtime.CardColor.Blue, runtime.CardShape.Circle, 4)
  ];
  state.players["player-b"].hand = [
    card("player_b_late_move", runtime.CardColor.Green, runtime.CardShape.Flag, 2)
  ];
  state.players["player-b"].deck = [];
  state.centerPiles.pile_1 = [
    card("pile_1_top", runtime.CardColor.Purple, runtime.CardShape.Flag, 5)
  ];

  const moveA = validatedMove(
    runtime,
    state,
    "player-a",
    {
      card_id: "player_a_move",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: versionBeforeMove
    },
    1000,
    0
  );
  const moveB = validatedMove(
    runtime,
    state,
    "player-b",
    {
      card_id: "player_b_late_move",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: versionBeforeMove
    },
    1160,
    1
  );

  state.pendingMoves = [moveA, moveB];

  const firstReadyMoves = runtime.collectReadyPendingSubmitMoves(state, 1150);
  const firstResult = runtime.applyPendingSubmitMoveBatch(state, firstReadyMoves, 1150);

  assert.deepEqual(normalize(firstResult.acceptedPlayerIds), ["player-a"]);
  assert.equal(firstResult.rejections.length, 0);
  assert.equal(state.centerPiles.pile_1.at(-1).card_id, "player_a_move");
  assert.deepEqual(
    normalize(state.pendingMoves.map((move) => move.playerId)),
    ["player-b"]
  );

  const secondReadyMoves = runtime.collectReadyPendingSubmitMoves(state, 1310);
  const secondResult = runtime.applyPendingSubmitMoveBatch(state, secondReadyMoves, 1310);

  assert.equal(secondResult.changed, false);
  assert.equal(secondResult.rejections.length, 1);
  assert.equal(
    secondResult.rejections[0].rejection.reason,
    runtime.MoveRejectionReason.CardDoesNotMatch
  );
  assert.equal(state.centerPiles.pile_1.at(-1).card_id, "player_a_move");
});

test("deterministic full matches finish while preserving every card", () => {
  const seeds = Array.from({length: 100}, (_, index) => index + 1);
  for (const seed of seeds) {
    const random = seededRandom(seed);
    const state = createConnectedWaitingState(runtime);
    runtime.initializeGameState(state, random, 1000);
    assertCardConservation(state);

    let acceptedMoves = 0;
    while (state.status === runtime.MatchStatus.Active && acceptedMoves < 100) {
      let move = findLegalMove(state);
      if (!move) {
        const resetResult = runtime.resolveStuckState(
          state,
          () => assertCardConservation(state),
          random
        );
        assert.equal(
          resetResult.stillStuck,
          false,
          "seed " + seed + " produced an unresolved stuck match"
        );
        move = findLegalMove(state);
      }

      assert.ok(move, "seed " + seed + " must have a legal move");
      const versionBeforeMove = state.stateVersion;
      const result = runtime.applySubmitMove(
        state,
        {userId: move.userId},
        JSON.stringify({
          card_id: move.cardId,
          targetPileId: move.pileId,
          expectedStateVersion: versionBeforeMove
        }),
        1000 + acceptedMoves + 1
      );

      assert.equal(result.accepted, true);
      assert.equal(state.stateVersion, versionBeforeMove + 1);
      assertCardConservation(state);
      acceptedMoves += 1;
    }

    assert.equal(
      state.status,
      runtime.MatchStatus.Finished,
      "seed " + seed + " did not finish"
    );
    assert.ok(state.winnerId);
    assert.ok(acceptedMoves > 0 && acceptedMoves <= 100);
    assert.equal(state.resultPersistencePending, true);
  }
});

test("two rematch acceptances start exactly one fresh round", () => {
  const state = createInitializedState(runtime);
  state.players["player-a"].rttEstimateMs = 220;
  state.players["player-a"].rttSampleSequence = 4;
  state.players["player-a"].lastStateSentAtMs = 1500;
  state.status = runtime.MatchStatus.Finished;
  state.winnerId = "player-a";
  state.endReason = runtime.MatchEndReason.Normal;
  state.endedAtMs = 2000;
  state.resultPersistencePending = false;
  state.resultPersisted = true;
  const calls = [];
  const dispatcher = {
    broadcastMessage(opcode, data) {
      calls.push({opcode, data: JSON.parse(data)});
    }
  };

  assert.equal(runtime.handleRematchDecision(
    dispatcher, state, state.presences["player-a"],
    JSON.stringify({accept: true}), 3000
  ), true);
  assert.equal(calls.at(-1).data.status, "requested");
  assert.equal(runtime.initializeRematchRound(state, seededRandom(1), 3001), false);

  assert.equal(runtime.handleRematchDecision(
    dispatcher, state, state.presences["player-b"],
    JSON.stringify({accept: true}), 3002
  ), true);
  assert.equal(calls.at(-1).data.status, "starting");
  assert.equal(calls.at(-1).data.startsInMs, 5000);
  assert.equal(runtime.initializeRematchRound(state, seededRandom(2), 3003), false);
  assert.equal(runtime.initializeRematchRound(state, seededRandom(2), 8002), true);
  assert.equal(state.roundNumber, 2);
  assert.equal(state.status, runtime.MatchStatus.Active);
  assert.equal(state.stateVersion, 1);
  assert.equal(state.winnerId, null);
  assert.equal(state.endedAtMs, null);
  assert.equal(state.pendingMoves.length, 0);
  assert.equal(state.players["player-a"].rttEstimateMs, null);
  assert.equal(state.players["player-a"].rttSampleSequence, 0);
  assert.equal(state.players["player-a"].lastStateSentAtMs, null);
  assertCardConservation(state);
  assert.equal(runtime.initializeRematchRound(state, seededRandom(3), 8003), false);
});

test("rematch countdown waits for result persistence", () => {
  const state = createInitializedState(runtime);
  state.status = runtime.MatchStatus.Finished;
  state.winnerId = "player-a";
  state.endReason = runtime.MatchEndReason.Normal;
  state.resultPersistencePending = true;
  state.resultPersisted = false;
  const calls = [];
  const dispatcher = {
    broadcastMessage(opcode, data) {
      calls.push({opcode, data: JSON.parse(data)});
    }
  };

  runtime.handleRematchDecision(
    dispatcher, state, state.presences["player-a"],
    JSON.stringify({accept: true}), 3000
  );
  runtime.handleRematchDecision(
    dispatcher, state, state.presences["player-b"],
    JSON.stringify({accept: true}), 3001
  );

  assert.equal(state.rematchPhase, "awaiting_persistence");
  assert.equal(state.roundStartsAtMs, null);
  assert.equal(calls.at(-1).data.status, "preparing");

  state.resultPersistencePending = false;
  state.resultPersisted = true;
  runtime.sprintMatchLoop(
    null, {info() {}, warn() {}, error() {}}, null, dispatcher, 1, state, []
  );

  assert.equal(state.rematchPhase, "countdown");
  assert.notEqual(state.roundStartsAtMs, null);
  assert.equal(calls.at(-1).data.status, "starting");
  assert.equal(calls.at(-1).data.startsAtMs - calls.at(-1).data.serverTimeMs, 5000);
});

test("rematch decisions and expiry cannot change a started countdown", () => {
  const state = createInitializedState(runtime);
  state.status = runtime.MatchStatus.Finished;
  state.winnerId = "player-a";
  state.endReason = runtime.MatchEndReason.Normal;
  state.resultPersistencePending = false;
  state.resultPersisted = true;
  const calls = [];
  const dispatcher = {
    broadcastMessage(opcode, data) {
      calls.push({opcode, data: JSON.parse(data)});
    }
  };

  runtime.handleRematchDecision(
    dispatcher, state, state.presences["player-a"],
    JSON.stringify({accept: true}), 1000
  );
  runtime.handleRematchDecision(
    dispatcher, state, state.presences["player-b"],
    JSON.stringify({accept: true}), 1001
  );
  const countdownStartsAtMs = state.roundStartsAtMs;
  assert.equal(state.rematchPhase, "countdown");

  assert.equal(runtime.handleRematchDecision(
    dispatcher, state, state.presences["player-a"],
    JSON.stringify({accept: false}), 1002
  ), false);
  state.rematchRequestedAtMs = Date.now() - runtime.rematchTimeoutMs - 1;
  state.roundStartsAtMs = Date.now() + 60_000;
  runtime.sprintMatchLoop(
    null, {info() {}, warn() {}, error() {}}, null, dispatcher, 1, state, []
  );

  assert.equal(state.rematchPhase, "countdown");
  assert.equal(state.rematchExpired, false);
  assert.equal(
    calls.filter((call) => call.data.status === "expired").length,
    0
  );
  assert.notEqual(countdownStartsAtMs, null);
});

test("rematch decisions reject active matches, outsiders, and acceptance after decline", () => {
  const state = createInitializedState(runtime);
  const dispatcher = {broadcastMessage() {}};
  assert.equal(runtime.handleRematchDecision(
    dispatcher, state, state.presences["player-a"],
    JSON.stringify({accept: true}), 1000
  ), false);

  state.status = runtime.MatchStatus.Finished;
  state.endReason = runtime.MatchEndReason.Normal;
  state.resultPersisted = true;
  assert.equal(runtime.handleRematchDecision(
    dispatcher, state, {userId: "outsider"},
    JSON.stringify({accept: true}), 2000
  ), false);
  assert.equal(runtime.handleRematchDecision(
    dispatcher, state, state.presences["player-a"],
    JSON.stringify({accept: false}), 2001
  ), true);
  assert.equal(runtime.handleRematchDecision(
    dispatcher, state, state.presences["player-a"],
    JSON.stringify({accept: true}), 2002
  ), false);
});

test("rematch decisions are rejected after a disconnect forfeit", () => {
  const state = createInitializedState(runtime);
  state.status = runtime.MatchStatus.Finished;
  state.winnerId = "player-a";
  state.endReason = runtime.MatchEndReason.Forfeit;
  state.resultPersisted = true;

  assert.equal(runtime.handleRematchDecision(
    {broadcastMessage() {}}, state, state.presences["player-a"],
    JSON.stringify({accept: true}), 2000
  ), false);
  assert.equal(state.rematchResponses["player-a"], "pending");
});

test("sprintMatchLoop broadcasts private state updates and targeted move rejections", () => {
  const state = createInitializedState(runtime);
  const player = state.players["player-a"];
  player.lastStateSentAtMs = Date.now() - 100;
  const previousPlayerAStateSentAtMs = player.lastStateSentAtMs;
  const playedCard = player.hand[0];
  state.centerPiles.pile_1 = [
    card("pile_top", playedCard.color, runtime.CardShape.Flag, 5)
  ];
  const calls = [];
  const dispatcher = {
    broadcastMessage(opcode, data, presences) {
      calls.push({opcode, data: JSON.parse(data), presences});
    },
  };
  const logger = {info() {}, warn() {}, error() {}};

  runtime.sprintMatchLoop(null, logger, null, dispatcher, 1, state, [
    submitMoveMessage(runtime, "player-a", {
      card_id: playedCard.card_id,
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion,
      reactionTimeMs: 20
    })
  ]);

  assert.equal(calls.length, 0);
  assert.equal(state.pendingMoves.length, 1);
  assert.notEqual(player.rttEstimateMs, null);
  assert.equal(player.rttSampleSequence, 1);
  state.pendingMoves[0].receivedAtMs -= runtime.moveFairnessWindowMs + 1;

  runtime.sprintMatchLoop(null, logger, null, dispatcher, 2, state, []);

  assert.deepEqual(calls.map((call) => call.opcode), [
    runtime.ServerOpcode.StateUpdate,
    runtime.ServerOpcode.StateUpdate
  ]);
  assert.equal(calls[0].presences.length, 1);
  assert.equal(calls[1].presences.length, 1);
  assert.notEqual(calls[0].data.myHand[0]?.card_id, undefined);
  const playerAUpdate = calls.find(
    (call) => call.presences[0].userId === "player-a"
  );
  const playerBUpdate = calls.find(
    (call) => call.presences[0].userId === "player-b"
  );
  assert.equal(playerAUpdate.data.transitions.length, 1);
  assert.equal(playerAUpdate.data.transitions[0].type, "card_played");
  assert.equal(playerAUpdate.data.transitions[0].actor, "self");
  assert.equal(playerAUpdate.data.transitions[0].card.card_id, playedCard.card_id);
  assert.equal(playerAUpdate.data.myRttSampleSequence, 1);
  assert.equal(playerBUpdate.data.myRttSampleSequence, 0);
  assert.ok(
    state.players["player-a"].lastStateSentAtMs > previousPlayerAStateSentAtMs
  );
  assert.equal(
    state.players["player-a"].lastStateSentAtMs,
    state.players["player-b"].lastStateSentAtMs
  );
  assert.equal(
    playerAUpdate.data.transitions[0].targetPileId,
    runtime.PileId.Pile1
  );
  assert.equal(playerBUpdate.data.transitions[0].actor, "opponent");
  assert.equal("playerId" in playerBUpdate.data.transitions[0], false);

  const callCountAfterValidMove = calls.length;
  runtime.sprintMatchLoop(null, logger, null, dispatcher, 3, state, [
    submitMoveMessage(runtime, "player-a", {
      card_id: "missing",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion
    })
  ]);

  assert.equal(calls.length, callCountAfterValidMove + 1);
  assert.equal(calls.at(-1).opcode, runtime.ServerOpcode.MoveRejected);
  assert.equal(
    calls.at(-1).data.reason,
    runtime.MoveRejectionReason.CardNotInHand
  );
  assert.equal(calls.at(-1).presences[0].userId, "player-a");
});

test("sprintMatchLoop sends gameEnded when disconnect timeout fires", () => {
  const state = createInitializedState(runtime);
  state.players["player-b"].connected = false;
  state.players["player-b"].disconnectedAtMs = Date.now() - 31_000;
  delete state.presences["player-b"];
  const calls = [];
  const dispatcher = {
    broadcastMessage(opcode, data, presences) {
      calls.push({opcode, data: JSON.parse(data), presences});
    }
  };
  const logger = {info() {}, warn() {}, error() {}};

  runtime.sprintMatchLoop(null, logger, null, dispatcher, 1, state, []);

  assert.equal(state.status, runtime.MatchStatus.Finished);
  assert.equal(state.winnerId, "player-a");
  assert.equal(state.endReason, runtime.MatchEndReason.Forfeit);
  assert.deepEqual(calls.map((call) => call.opcode), [
    runtime.ServerOpcode.GameEnded
  ]);
  assert.equal(calls[0].presences[0].userId, "player-a");
  assert.equal(calls[0].data.endReason, runtime.MatchEndReason.Forfeit);
});

test("sprintMatchLoop handles explicit abandon opcode as forfeit", () => {
  const state = createInitializedState(runtime);
  const calls = [];
  const dispatcher = {
    broadcastMessage(opcode, data, presences) {
      calls.push({opcode, data: JSON.parse(data), presences});
    }
  };
  const logger = {info() {}, warn() {}, error() {}};

  runtime.sprintMatchLoop(null, logger, null, dispatcher, 1, state, [
    {
      opCode: runtime.ClientOpcode.AbandonMatch,
      sender: {userId: "player-b", sessionId: "player-b-session"},
      data: ""
    }
  ]);

  assert.equal(state.status, runtime.MatchStatus.Finished);
  assert.equal(state.winnerId, "player-a");
  assert.equal(state.endReason, runtime.MatchEndReason.Forfeit);
  assert.equal(state.resultPersistencePending, true);
  assert.deepEqual(calls.map((call) => call.opcode), [
    runtime.ServerOpcode.GameEnded,
    runtime.ServerOpcode.GameEnded
  ]);
  assert.equal(calls[0].data.endReason, runtime.MatchEndReason.Forfeit);
});

test("waiting quickplay match terminates after lobby timeout", () => {
  const state = runtime.createWaitingMatchState(["player-a", "player-b"]);
  state.createdAtMs = Date.now() - runtime.waitingMatchTimeoutMs - 1;
  const dispatcher = {broadcastMessage() {}};
  const logger = {info() {}, warn() {}, error() {}};
  const nk = {storageDelete() {}};

  const result = runtime.sprintMatchLoop(null, logger, nk, dispatcher, 1, state, []);

  assert.equal(result, null);
});

test("active idle match becomes abandoned and broadcasts gameEnded", () => {
  const state = createInitializedState(runtime);
  state.lastActivityAtMs = Date.now() - runtime.activeIdleTimeoutMs - 1;
  const calls = [];
  const dispatcher = {
    broadcastMessage(opcode, data, presences) {
      calls.push({opcode, data: JSON.parse(data), presences});
    }
  };
  const logger = {info() {}, warn() {}, error() {}};
  const nk = {storageDelete() {}};

  const result = runtime.sprintMatchLoop(null, logger, nk, dispatcher, 1, state, []);

  assert.notEqual(result, null);
  assert.equal(state.status, runtime.MatchStatus.Finished);
  assert.equal(state.winnerId, null);
  assert.equal(state.endReason, runtime.MatchEndReason.Abandoned);
  assert.equal(state.resultPersistencePending, false);
  assert.deepEqual(calls.map((call) => call.opcode), [
    runtime.ServerOpcode.GameEnded,
    runtime.ServerOpcode.GameEnded
  ]);
});

test("abandoned empty match terminates after finished-empty grace", () => {
  const state = createInitializedState(runtime);
  state.status = runtime.MatchStatus.Finished;
  state.winnerId = null;
  state.endReason = runtime.MatchEndReason.Abandoned;
  state.resultPersistencePending = false;
  state.resultPersisted = false;
  state.presences = {};
  state.playerOrder.forEach((userId) => {
    state.players[userId].connected = false;
  });
  state.finishedEmptySinceMs = Date.now() - runtime.finishedEmptyGraceMs - 1;
  const dispatcher = {broadcastMessage() {}};
  const logger = {info() {}, warn() {}, error() {}};
  const nk = {storageDelete() {}};

  const result = runtime.sprintMatchLoop(null, logger, nk, dispatcher, 1, state, []);

  assert.equal(result, null);
});

test("finished match waits for pending result persistence before terminating", () => {
  const state = createInitializedState(runtime);
  state.status = runtime.MatchStatus.Finished;
  state.winnerId = "player-a";
  state.endReason = runtime.MatchEndReason.Normal;
  state.startedAtMs = 1000;
  state.endedAtMs = 2000;
  state.resultPersistencePending = true;
  state.resultPersisted = false;
  state.presences = {};
  state.playerOrder.forEach((userId) => {
    state.players[userId].connected = false;
  });
  state.finishedEmptySinceMs = Date.now() - runtime.finishedEmptyGraceMs - 1;
  const dispatcher = {broadcastMessage() {}};
  const logger = {info() {}, warn() {}, error() {}};
  const nk = {
    storageRead() {
      return [];
    },
    multiUpdate() {
      throw new Error("temporary storage failure");
    },
    storageDelete() {}
  };

  const result = runtime.sprintMatchLoop(null, logger, nk, dispatcher, 1, state, []);

  assert.notEqual(result, null);
  assert.equal(state.resultPersistencePending, true);
  assert.equal(state.resultPersisted, false);
});

test("finished match terminates once persistence is complete and both players left", () => {
  const state = createInitializedState(runtime);
  state.status = runtime.MatchStatus.Finished;
  state.winnerId = "player-a";
  state.endReason = runtime.MatchEndReason.Forfeit;
  state.startedAtMs = 1000;
  state.endedAtMs = 2000;
  state.resultPersistencePending = false;
  state.resultPersisted = true;
  state.presences = {};
  state.playerOrder.forEach((userId) => {
    state.players[userId].connected = false;
  });
  state.finishedEmptySinceMs = Date.now() - runtime.finishedEmptyGraceMs - 1;
  const dispatcher = {broadcastMessage() {}};
  const logger = {info() {}, warn() {}, error() {}};
  const nk = {storageDelete() {}};

  const result = runtime.sprintMatchLoop(null, logger, nk, dispatcher, 1, state, []);

  assert.equal(result, null);
});

function createStuckResetState(runtime) {
  const state = createInitializedState(runtime);
  state.stateVersion = 7;
  state.players["player-a"].hand = [
    card("hand_a", runtime.CardColor.Green, runtime.CardShape.House, 5)
  ];
  state.players["player-b"].hand = [
    card("hand_b", runtime.CardColor.Purple, runtime.CardShape.House, 5)
  ];
  state.centerPiles.pile_1 = [
    card("pile_1_old", runtime.CardColor.Green, runtime.CardShape.Circle, 4),
    card("pile_1_top", runtime.CardColor.Red, runtime.CardShape.Star, 1)
  ];
  state.centerPiles.pile_2 = [
    card("pile_2_old", runtime.CardColor.Yellow, runtime.CardShape.Flag, 5),
    card("pile_2_top", runtime.CardColor.Blue, runtime.CardShape.Diamond, 2)
  ];
  return state;
}

test("stuck detection checks every hand against both center piles", () => {
  const state = createStuckResetState(runtime);
  assert.equal(runtime.hasAnyLegalMove(state), false);
  assert.equal(runtime.isGameStuck(state), true);

  state.players["player-b"].hand.push(
    card("legal", runtime.CardColor.Blue, runtime.CardShape.Circle, 6)
  );
  assert.equal(runtime.hasAnyLegalMove(state), true);
  assert.equal(runtime.isGameStuck(state), false);
});

test("stuck reset shuffles piles separately without changing hands or decks", () => {
  const state = createStuckResetState(runtime);
  const handsBefore = normalize(state.playerOrder.map((id) => state.players[id].hand));
  const decksBefore = normalize(state.playerOrder.map((id) => state.players[id].deck));
  const pile1Ids = state.centerPiles.pile_1.map((item) => item.card_id).sort();
  const pile2Ids = state.centerPiles.pile_2.map((item) => item.card_id).sort();

  assert.equal(runtime.reshuffleCenterPiles(state, () => 0), true);

  assert.equal(state.stateVersion, 8);
  assert.deepEqual(normalize(state.playerOrder.map((id) => state.players[id].hand)), handsBefore);
  assert.deepEqual(normalize(state.playerOrder.map((id) => state.players[id].deck)), decksBefore);
  assert.deepEqual(state.centerPiles.pile_1.map((item) => item.card_id).sort(), pile1Ids);
  assert.deepEqual(state.centerPiles.pile_2.map((item) => item.card_id).sort(), pile2Ids);
  assert.equal(state.centerPiles.pile_1.at(-1).card_id, "pile_1_old");
  assert.equal(runtime.isGameStuck(state), false);
});

test("stuck resolution broadcasts each reset and checks again", () => {
  const state = createStuckResetState(runtime);
  const randomValues = [0.9, 0.9, 0, 0];
  const observedVersions = [];
  const result = runtime.resolveStuckState(
    state,
    (current) => observedVersions.push(current.stateVersion),
    () => randomValues.shift(),
    4
  );

  assert.deepEqual(observedVersions, [8, 9]);
  assert.equal(result.resetCount, 2);
  assert.equal(result.stillStuck, false);
  assert.equal(result.blockedBySingleCardPiles, false);
  assert.equal(state.stateVersion, 9);
});

test("one multi-card pile resets while the single-card pile stays unchanged", () => {
  const state = createStuckResetState(runtime);
  state.centerPiles.pile_2 = [state.centerPiles.pile_2.at(-1)];
  const pile2Before = normalize(state.centerPiles.pile_2);
  const decksBefore = normalize(state.playerOrder.map((id) => state.players[id].deck));

  assert.equal(runtime.reshuffleCenterPiles(state, () => 0), true);

  assert.equal(state.stateVersion, 8);
  assert.equal(state.centerPiles.pile_1.at(-1).card_id, "pile_1_old");
  assert.deepEqual(normalize(state.centerPiles.pile_2), pile2Before);
  assert.deepEqual(normalize(state.playerOrder.map((id) => state.players[id].deck)), decksBefore);
  assert.equal(runtime.isGameStuck(state), false);
});

test("two single-card center piles swap with player decks without changing deck counts", () => {
  const state = createStuckResetState(runtime);
  state.centerPiles.pile_1 = [state.centerPiles.pile_1.at(-1)];
  state.centerPiles.pile_2 = [state.centerPiles.pile_2.at(-1)];
  state.players["player-a"].deck = [
    card("deck_a_top", runtime.CardColor.Blue, runtime.CardShape.Diamond, 2),
    card("deck_a_keep", runtime.CardColor.Purple, runtime.CardShape.House, 6)
  ];
  state.players["player-b"].deck = [
    card("deck_b_top", runtime.CardColor.Green, runtime.CardShape.Circle, 4),
    card("deck_b_keep", runtime.CardColor.Orange, runtime.CardShape.Flag, 6)
  ];
  const handsBefore = normalize(state.playerOrder.map((id) => state.players[id].hand));
  const deckCountsBefore = state.playerOrder.map((id) => state.players[id].deck.length);
  const oldPile1Card = state.centerPiles.pile_1[0];
  const oldPile2Card = state.centerPiles.pile_2[0];

  assert.equal(runtime.replaceSingleCardPilesFromPlayerDecks(state, () => 0), true);

  assert.equal(state.stateVersion, 8);
  assert.equal(state.centerPiles.pile_1[0].card_id, "deck_a_top");
  assert.equal(state.centerPiles.pile_2[0].card_id, "deck_b_top");
  assert.deepEqual(
    state.playerOrder.map((id) => state.players[id].deck.length),
    deckCountsBefore
  );
  assert.deepEqual(normalize(state.playerOrder.map((id) => state.players[id].hand)), handsBefore);
  assert.equal(state.players["player-a"].deck[0].card_id, "deck_a_keep");
  assert.equal(state.players["player-b"].deck[0].card_id, "deck_b_keep");
  assert.equal(state.players["player-a"].deck[1].card_id, oldPile1Card.card_id);
  assert.equal(state.players["player-b"].deck[1].card_id, oldPile2Card.card_id);
  assert.deepEqual(
    [
      state.centerPiles.pile_1[0].card_id,
      state.centerPiles.pile_2[0].card_id,
      ...state.players["player-a"].deck.map((entry) => entry.card_id),
      ...state.players["player-b"].deck.map((entry) => entry.card_id)
    ].sort(),
    [
      "deck_a_top",
      "deck_a_keep",
      oldPile1Card.card_id,
      "deck_b_top",
      "deck_b_keep",
      oldPile2Card.card_id
    ].sort()
  );
});

test("single-card pile replacement is blocked safely when a player deck is too short", () => {
  const state = createStuckResetState(runtime);
  state.centerPiles.pile_1 = [state.centerPiles.pile_1.at(-1)];
  state.centerPiles.pile_2 = [state.centerPiles.pile_2.at(-1)];
  state.players["player-a"].deck = [
    card("deck_a_only", runtime.CardColor.Blue, runtime.CardShape.Diamond, 2)
  ];
  state.players["player-b"].deck = [
    card("deck_b_top", runtime.CardColor.Green, runtime.CardShape.Circle, 4),
    card("deck_b_keep", runtime.CardColor.Orange, runtime.CardShape.Flag, 6)
  ];
  const before = normalize(state);

  assert.equal(runtime.replaceSingleCardPilesFromPlayerDecks(state, () => 0), false);
  assert.deepEqual(normalize(state), before);
});

test("stuck resolution uses single-card pile replacement and broadcasts reset", () => {
  const state = createStuckResetState(runtime);
  state.centerPiles.pile_1 = [state.centerPiles.pile_1.at(-1)];
  state.centerPiles.pile_2 = [state.centerPiles.pile_2.at(-1)];
  state.players["player-a"].deck = [
    card("deck_a_top", runtime.CardColor.Blue, runtime.CardShape.Diamond, 2),
    card("deck_a_keep", runtime.CardColor.Purple, runtime.CardShape.House, 6)
  ];
  state.players["player-b"].deck = [
    card("deck_b_top", runtime.CardColor.Green, runtime.CardShape.Circle, 4),
    card("deck_b_keep", runtime.CardColor.Orange, runtime.CardShape.Flag, 6)
  ];
  const observedVersions = [];

  const result = runtime.resolveStuckState(
    state,
    (current) => observedVersions.push(current.stateVersion),
    () => 0,
    4
  );

  assert.deepEqual(observedVersions, [8]);
  assert.equal(result.resetCount, 1);
  assert.equal(result.stillStuck, false);
  assert.equal(result.blockedBySingleCardPiles, false);
  assert.equal(state.centerPiles.pile_1[0].card_id, "deck_a_top");
  assert.equal(state.centerPiles.pile_2[0].card_id, "deck_b_top");
});

test("stuck resolution reports blocked when single-card replacement cannot run safely", () => {
  const state = createStuckResetState(runtime);
  state.centerPiles.pile_1 = [state.centerPiles.pile_1.at(-1)];
  state.centerPiles.pile_2 = [state.centerPiles.pile_2.at(-1)];
  state.players["player-a"].deck = [
    card("deck_a_only", runtime.CardColor.Blue, runtime.CardShape.Diamond, 2)
  ];
  state.players["player-b"].deck = [
    card("deck_b_top", runtime.CardColor.Green, runtime.CardShape.Circle, 4),
    card("deck_b_keep", runtime.CardColor.Orange, runtime.CardShape.Flag, 6)
  ];
  const before = normalize(state);
  let observerCalls = 0;

  const result = runtime.resolveStuckState(
    state,
    () => observerCalls += 1,
    () => 0,
    4
  );

  assert.equal(result.resetCount, 0);
  assert.equal(result.stillStuck, true);
  assert.equal(result.blockedBySingleCardPiles, true);
  assert.equal(observerCalls, 0);
  assert.deepEqual(normalize(state), before);
});

test("match layer sends targeted opcode 13 views after every reset", () => {
  const state = createStuckResetState(runtime);
  const calls = [];
  const dispatcher = {
    broadcastMessage(opcode, data, presences) {
      calls.push({opcode, data: JSON.parse(data), presences});
    }
  };
  const logger = {info() {}, warn() {}, error() {}};
  const randomValues = [0.9, 0.9, 0, 0];

  runtime.resolveAndBroadcastStuckState(
    dispatcher,
    state,
    logger,
    () => randomValues.shift(),
    4
  );

  assert.deepEqual(calls.map((call) => call.opcode), [
    runtime.ServerOpcode.StuckReset,
    runtime.ServerOpcode.StuckReset,
    runtime.ServerOpcode.StuckReset,
    runtime.ServerOpcode.StuckReset
  ]);
  assert.deepEqual(calls.map((call) => call.data.stateVersion), [8, 8, 9, 9]);
  assert.equal(calls.every((call) => call.presences.length === 1), true);
  assert.notDeepEqual(calls[0].data.myHand, calls[1].data.myHand);
});

function finishedStateForStatistics(runtime) {
  const state = createInitializedState(runtime);
  state.status = runtime.MatchStatus.Finished;
  state.winnerId = "player-a";
  state.endReason = runtime.MatchEndReason.Normal;
  state.startedAtMs = 1000;
  state.endedAtMs = 6000;
  state.resultPersistencePending = true;
  state.resultPersisted = false;
  return state;
}

function storedProfile(userId, version, value) {
  return {
    collection: "player",
    key: "profile",
    userId,
    version,
    permissionRead: 2,
    permissionWrite: 1,
    createTime: 1,
    updateTime: 1,
    value
  };
}

test("game initialization records timing and resets persistence guards", () => {
  const state = createConnectedWaitingState(runtime);
  runtime.initializeGameState(state, () => 0, 123456);

  assert.equal(state.startedAtMs, 123456);
  assert.equal(state.endedAtMs, null);
  assert.equal(state.resultPersistencePending, false);
  assert.equal(state.resultPersisted, false);
});

test("profile persistence atomically updates winner, loser, and best time once", () => {
  const state = finishedStateForStatistics(runtime);
  let reads = 0;
  const updates = [];
  const leaderboardWrites = [];
  const nk = {
    storageRead() {
      reads += 1;
      return [
        storedProfile("player-a", "winner-version", {
          gamesPlayed: 2,
          wins: 1,
          losses: 1,
          bestTimeMs: 7000,
          createdAt: "2026-01-01T00:00:00.000Z"
        }),
        storedProfile("player-b", "loser-version", {
          gamesPlayed: 4,
          wins: 3,
          losses: 1,
          bestTimeMs: null,
          createdAt: "2026-01-02T00:00:00.000Z"
        })
      ];
    },
    multiUpdate(accountUpdates, storageWrites, storageDeletes, walletUpdates) {
      updates.push({accountUpdates, storageWrites, storageDeletes, walletUpdates});
      return {storageWriteAcks: [], walletUpdateAcks: []};
    },
    leaderboardRecordWrite(
      leaderboardID,
      ownerID,
      username,
      score,
      subscore,
      metadata,
      operator
    ) {
      leaderboardWrites.push({
        leaderboardID,
        ownerID,
        username,
        score,
        subscore,
        metadata,
        operator
      });
      return {};
    }
  };

  assert.equal(runtime.persistPendingMatchResult(state, nk), true);
  assert.equal(state.resultPersisted, true);
  assert.equal(state.resultPersistencePending, false);
  assert.equal(reads, 1);
  assert.equal(updates.length, 1);
  assert.equal(updates[0].accountUpdates, null);
  assert.equal(updates[0].storageDeletes, null);
  assert.equal(updates[0].walletUpdates, null);

  const winnerWrite = updates[0].storageWrites.find(
    (write) => write.userId === "player-a"
  );
  const loserWrite = updates[0].storageWrites.find(
    (write) => write.userId === "player-b"
  );
  assert.deepEqual(normalize(winnerWrite.value), {
    gamesPlayed: 3,
    wins: 2,
    losses: 1,
    bestTimeMs: 5000,
    createdAt: "2026-01-01T00:00:00.000Z"
  });
  assert.deepEqual(normalize(loserWrite.value), {
    gamesPlayed: 5,
    wins: 3,
    losses: 2,
    bestTimeMs: null,
    createdAt: "2026-01-02T00:00:00.000Z"
  });
  assert.equal(
    winnerWrite.value.bestTimeMs,
    runtime.calculateElapsedTimeMs(state, state.endedAtMs + 1000)
  );
  assert.equal(winnerWrite.version, "winner-version");
  assert.equal(loserWrite.version, "loser-version");
  assert.equal(winnerWrite.permissionWrite, 0);
  assert.equal(loserWrite.permissionWrite, 0);
  assert.deepEqual(normalize(leaderboardWrites), [
    {
      leaderboardID: "sprint_wins",
      ownerID: "player-a",
      username: "Alice",
      score: 2,
      subscore: 0,
      metadata: {
        gamesPlayed: 3,
        losses: 1,
        bestTimeMs: 5000
      },
      operator: "set"
    }
  ]);

  assert.equal(runtime.persistPendingMatchResult(state, nk), false);
  assert.equal(reads, 1);
  assert.equal(updates.length, 1);
});

test("profile persistence creates missing profiles and preserves a faster best time", () => {
  const state = finishedStateForStatistics(runtime);
  const writes = [];
  const nk = {
    storageRead() {
      return [
        storedProfile("player-a", "winner-version", {
          gamesPlayed: 8,
          wins: 5,
          losses: 3,
          bestTimeMs: 3000,
          createdAt: "created"
        })
      ];
    },
    multiUpdate(_accounts, storageWrites) {
      writes.push(...storageWrites);
      return {storageWriteAcks: [], walletUpdateAcks: []};
    }
  };

  runtime.persistPendingMatchResult(state, nk);

  const winnerWrite = writes.find((write) => write.userId === "player-a");
  const loserWrite = writes.find((write) => write.userId === "player-b");
  assert.equal(winnerWrite.value.bestTimeMs, 3000);
  assert.equal(loserWrite.value.gamesPlayed, 1);
  assert.equal(loserWrite.value.losses, 1);
  assert.equal(loserWrite.version, undefined);
  assert.equal(loserWrite.permissionRead, 1);
  assert.equal(loserWrite.permissionWrite, 0);
});

test("forfeit persistence updates win and loss without changing best time", () => {
  const state = finishedStateForStatistics(runtime);
  state.endReason = runtime.MatchEndReason.Forfeit;
  const writes = [];
  const nk = {
    storageRead() {
      return [
        storedProfile("player-a", "winner-version", {
          gamesPlayed: 2,
          wins: 1,
          losses: 1,
          bestTimeMs: 7000,
          createdAt: "created-a"
        }),
        storedProfile("player-b", "loser-version", {
          gamesPlayed: 3,
          wins: 2,
          losses: 1,
          bestTimeMs: 4000,
          createdAt: "created-b"
        })
      ];
    },
    multiUpdate(_accounts, storageWrites) {
      writes.push(...storageWrites);
      return {storageWriteAcks: [], walletUpdateAcks: []};
    }
  };

  runtime.persistPendingMatchResult(state, nk);

  const winnerWrite = writes.find((write) => write.userId === "player-a");
  const loserWrite = writes.find((write) => write.userId === "player-b");
  assert.equal(winnerWrite.value.gamesPlayed, 3);
  assert.equal(winnerWrite.value.wins, 2);
  assert.equal(winnerWrite.value.bestTimeMs, 7000);
  assert.equal(loserWrite.value.gamesPlayed, 4);
  assert.equal(loserWrite.value.losses, 2);
  assert.equal(loserWrite.value.bestTimeMs, 4000);
});

test("failed profile persistence remains pending for a later tick", () => {
  const state = finishedStateForStatistics(runtime);
  const nk = {
    storageRead() {
      return [];
    },
    multiUpdate() {
      throw new Error("temporary storage failure");
    }
  };

  assert.throws(
    () => runtime.persistPendingMatchResult(state, nk),
    /temporary storage failure/
  );
  assert.equal(state.resultPersistencePending, true);
  assert.equal(state.resultPersisted, false);
});

test("leaderboard write failure does not retry profile persistence", () => {
  const state = finishedStateForStatistics(runtime);
  let profileWrites = 0;
  const nk = {
    storageRead() {
      return [];
    },
    multiUpdate() {
      profileWrites += 1;
      return {storageWriteAcks: [], walletUpdateAcks: []};
    },
    leaderboardRecordWrite() {
      throw new Error("temporary leaderboard failure");
    }
  };

  assert.equal(runtime.persistPendingMatchResult(state, nk), true);
  assert.equal(profileWrites, 1);
  assert.equal(state.resultPersistencePending, false);
  assert.equal(state.resultPersisted, true);
  assert.equal(runtime.persistPendingMatchResult(state, nk), false);
  assert.equal(profileWrites, 1);
});

test("leaderboard creation uses an authoritative descending wins board", () => {
  const calls = [];
  const nk = {
    leaderboardCreate(
      leaderboardID,
      authoritative,
      sortOrder,
      operator,
      resetSchedule,
      metadata,
      enableRank
    ) {
      calls.push({
        leaderboardID,
        authoritative,
        sortOrder,
        operator,
        resetSchedule,
        metadata,
        enableRank
      });
    }
  };

  runtime.ensureSprintWinsLeaderboard(nk, {info() {}});

  assert.deepEqual(normalize(calls), [
    {
      leaderboardID: "sprint_wins",
      authoritative: true,
      sortOrder: "descending",
      operator: "set",
      resetSchedule: null,
      metadata: {title: "Sprint Wins"},
      enableRank: true
    }
  ]);
});

test("leaderboard creation tolerates an existing leaderboard", () => {
  let logCount = 0;
  const nk = {
    leaderboardCreate() {
      throw new Error("already exists");
    }
  };

  assert.doesNotThrow(() =>
    runtime.ensureSprintWinsLeaderboard(nk, {info() { logCount += 1; }})
  );
  assert.equal(logCount, 1);
});

test("wins leaderboard RPC returns UI-safe entries", () => {
  const nk = {
    leaderboardRecordsList(leaderboardID, owners, limit) {
      assert.equal(leaderboardID, "sprint_wins");
      assert.deepEqual(normalize(owners), []);
      assert.equal(limit, 25);
      return {
        records: [
          {
            leaderboardId: "sprint_wins",
            ownerId: "player-a",
            username: "Alice",
            score: 7,
            subscore: 0,
            numScore: 1,
            metadata: {
              gamesPlayed: 9,
              losses: 2,
              bestTimeMs: 4200
            },
            createTime: 1,
            updateTime: 1,
            expiryTime: 0,
            rank: 1
          }
        ]
      };
    }
  };

  const result = runtime.rpcGetWinsLeaderboard(
    {userId: "player-a"},
    {info() {}},
    nk,
    JSON.stringify({limit: 25})
  );

  assert.deepEqual(JSON.parse(result), [
    {
      rank: 1,
      userId: "player-a",
      displayName: "Alice",
      wins: 7,
      gamesPlayed: 9,
      losses: 2,
      bestTimeMs: 4200
    }
  ]);
});

test("wins leaderboard RPC requires an authenticated user", () => {
  assert.throws(
    () => runtime.rpcGetWinsLeaderboard({}, {info() {}}, {}, ""),
    /session is required/
  );
});

test("get_or_create_profile returns an existing owner profile", () => {
  const profile = {
    gamesPlayed: 7,
    wins: 4,
    losses: 3,
    bestTimeMs: 2500,
    createdAt: "2026-01-01T00:00:00.000Z"
  };
  let writes = 0;
  const nk = {
    storageRead(reads) {
      assert.deepEqual(normalize(reads), [
        {
          collection: "player",
          key: "profile",
          userId: "player-a"
        }
      ]);
      return [
        storedProfile("player-a", "profile-version", profile)
      ];
    },
    storageWrite() {
      writes += 1;
    }
  };

  const result = runtime.rpcGetOrCreateProfile(
    {userId: "player-a"},
    {info() {}},
    nk,
    ""
  );

  assert.deepEqual(JSON.parse(result), profile);
  assert.equal(writes, 0);
});

test("get_or_create_profile creates a server-owned default profile when missing", () => {
  const writes = [];
  const nk = {
    storageRead() {
      return [];
    },
    storageWrite(requests) {
      writes.push(...requests);
    }
  };

  const result = runtime.rpcGetOrCreateProfile(
    {userId: "player-a"},
    {info() {}},
    nk,
    ""
  );
  const profile = JSON.parse(result);

  assert.deepEqual(profile, {
    gamesPlayed: 0,
    wins: 0,
    losses: 0,
    bestTimeMs: null,
    createdAt: profile.createdAt
  });
  assert.equal(typeof profile.createdAt, "string");
  assert.equal(writes.length, 1);
  assert.deepEqual(normalize(writes[0]), {
    collection: "player",
    key: "profile",
    userId: "player-a",
    value: profile,
    permissionRead: 1,
    permissionWrite: 0
  });
});

test("get_or_create_profile requires an authenticated user", () => {
  assert.throws(
    () => runtime.rpcGetOrCreateProfile({}, {info() {}}, {}, ""),
    /session is required/
  );
});

test("game-ended view is sent before statistics persist on the following tick", () => {
  const state = createInitializedState(runtime);
  const player = state.players["player-a"];
  player.hand = [card("last_card", runtime.CardColor.Red, runtime.CardShape.Star, 1)];
  player.deck = [];
  state.startedAtMs = 1000;
  state.centerPiles.pile_1 = [
    card("pile_top", runtime.CardColor.Red, runtime.CardShape.Flag, 5)
  ];
  const broadcasts = [];
  let profileWrites = 0;
  const dispatcher = {
    broadcastMessage(opcode, data, presences) {
      broadcasts.push({opcode, data: JSON.parse(data), presences});
    }
  };
  const nk = {
    storageRead() {
      return [];
    },
    multiUpdate() {
      profileWrites += 1;
      return {storageWriteAcks: [], walletUpdateAcks: []};
    }
  };
  const logger = {info() {}, warn() {}, error() {}};

  runtime.sprintMatchLoop(null, logger, nk, dispatcher, 1, state, [
    submitMoveMessage(runtime, "player-a", {
      card_id: "last_card",
      targetPileId: runtime.PileId.Pile1,
      expectedStateVersion: state.stateVersion
    })
  ]);

  assert.equal(broadcasts.length, 0);
  assert.equal(state.pendingMoves.length, 1);
  state.pendingMoves[0].receivedAtMs -= runtime.moveFairnessWindowMs + 1;

  runtime.sprintMatchLoop(null, logger, nk, dispatcher, 2, state, []);

  assert.deepEqual(broadcasts.map((call) => call.opcode), [
    runtime.ServerOpcode.GameEnded,
    runtime.ServerOpcode.GameEnded
  ]);
  assert.equal(broadcasts[0].data.winnerName, "Alice");
  assert.equal(broadcasts[1].data.winnerName, "Alice");
  const winnerView = broadcasts.find(
    (call) => call.presences[0].userId === "player-a"
  );
  const loserView = broadcasts.find(
    (call) => call.presences[0].userId === "player-b"
  );
  assert.equal(winnerView.data.transitions.length, 1);
  assert.equal(winnerView.data.transitions[0].actor, "self");
  assert.equal(winnerView.data.transitions[0].card.card_id, "last_card");
  assert.equal(loserView.data.transitions.length, 1);
  assert.equal(loserView.data.transitions[0].actor, "opponent");
  assert.equal(profileWrites, 0);
  assert.equal(state.resultPersistencePending, true);

  runtime.sprintMatchLoop(null, logger, nk, dispatcher, 3, state, []);
  assert.equal(profileWrites, 1);
  assert.equal(state.resultPersisted, true);
});

test("onboarding read returns zero defaults for a new account", () => {
  const storage = onboardingStorage();
  const result = JSON.parse(runtime.rpcGetOnboardingProgress(
    {userId: "player-a"}, {debug() {}}, storage.nk, ""
  ));
  assert.deepEqual(normalize(result), {
    tutorialCompletedVersion: 0,
    firstPracticeCompletedVersion: 0,
    tutorialPromptDismissedVersion: 0
  });
});

test("onboarding merge is monotonic independently for all fields", () => {
  const storage = onboardingStorage({
    tutorialCompletedVersion: 2,
    firstPracticeCompletedVersion: 0,
    tutorialPromptDismissedVersion: 1
  });
  const result = JSON.parse(runtime.rpcMergeOnboardingProgress(
    {userId: "player-a"}, {debug() {}}, storage.nk,
    JSON.stringify({
      tutorialCompletedVersion: 1,
      firstPracticeCompletedVersion: 3,
      tutorialPromptDismissedVersion: 2
    })
  ));
  assert.deepEqual(normalize(result), {
    tutorialCompletedVersion: 2,
    firstPracticeCompletedVersion: 3,
    tutorialPromptDismissedVersion: 2
  });
  assert.deepEqual(normalize(storage.value()), normalize(result));
});

test("onboarding merge rejects unknown and invalid versions", () => {
  const storage = onboardingStorage();
  assert.throws(() => runtime.rpcMergeOnboardingProgress(
    {userId: "player-a"}, {debug() {}}, storage.nk, '{"unknown":1}'
  ), /Unknown onboarding field/);
  assert.throws(() => runtime.rpcMergeOnboardingProgress(
    {userId: "player-a"}, {debug() {}}, storage.nk,
    '{"tutorialCompletedVersion":-1}'
  ), /must be an integer/);
});
