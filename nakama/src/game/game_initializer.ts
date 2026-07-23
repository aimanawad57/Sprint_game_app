type RandomSource = () => number;

function cloneAndShuffleCards(
  catalog: ReadonlyArray<Card>,
  random: RandomSource = Math.random
): Card[] {
  const cards = catalog.map((card) => ({
    card_id: card.card_id,
    color: card.color,
    shape: card.shape,
    count: card.count
  }));
  
  // This is a Fisher-Yates shuffle implementation that uses the provided random source.
    // Idea: iterate from the last into the first, choose random index and swap current with that, 
    // repeat until the first index is reached. This ensures a uniform shuffle.
  for (let index = cards.length - 1; index > 0; index -= 1) {
    const randomValue = random();
    if (!Number.isFinite(randomValue) || randomValue < 0 || randomValue >= 1) {
      throw new Error("Random source must return a finite value from 0 inclusive to 1 exclusive.");
    }

    const swapIndex = Math.floor(randomValue * (index + 1));
    const current = cards[index];
    cards[index] = cards[swapIndex];
    cards[swapIndex] = current;
  }

  return cards;
}

function bothPlayersConnected(state: SprintMatchState): boolean {
  if (state.playerOrder[1] === UNASSIGNED_PLAYER_ID) {
    return false;
  }

  return state.playerOrder.every(
    (userId) => state.players[userId].connected && state.presences[userId] !== undefined
  );
}

function initialCardStateIsEmpty(state: SprintMatchState): boolean {
  return (
    state.playerOrder.every((userId) => {
      const player = state.players[userId];
      return player.hand.length === 0 && player.deck.length === 0;
    }) &&
    state.centerPiles.pile_1.length === 0 &&
    state.centerPiles.pile_2.length === 0
  );
}

type InitialDraw = {
  deck: Card[];
  hand: Card[];
};

function drawCards(deck: Card[], count: number): InitialDraw {
  if (deck.length < count) {
    throw new Error("Cannot draw more cards than the player deck contains.");
  }

  const remainingCount = deck.length - count;
  const hand: Card[] = [];
  for (let index = deck.length - 1; index >= remainingCount; index -= 1) {
    const card = deck[index];
    if (!card) {
      throw new Error("Cannot draw an empty card from the player deck.");
    }
    hand.push(card);
  }

  return {
    deck: deck.slice(0, remainingCount),
    hand: hand
  };
}

function assertInitializedCardState(state: SprintMatchState): void {
  const playerA = state.players[state.playerOrder[0]];
  const playerB = state.players[state.playerOrder[1]];
  const cardGroups = [
    playerA.hand,
    playerA.deck,
    playerB.hand,
    playerB.deck,
    state.centerPiles.pile_1,
    state.centerPiles.pile_2
  ];
  const allCards: Card[] = [];
  const uniqueIds: {[cardId: string]: boolean} = {};

  cardGroups.forEach((cards, groupIndex) => {
    cards.forEach((card, cardIndex) => {
      if (!card) {
        throw new Error(
          "Initialized game contains an empty card entry in group " +
            groupIndex +
            " at position " +
            cardIndex +
            "."
        );
      }
      if (uniqueIds[card.card_id]) {
        throw new Error(
          "Initialized game contains duplicate card ID " + card.card_id + "."
        );
      }
      uniqueIds[card.card_id] = true;
      allCards.push(card);
    });
  });

  if (
    allCards.length !== CARD_CATALOG_SIZE ||
    Object.keys(uniqueIds).length !== CARD_CATALOG_SIZE ||
    playerA.hand.length !== 3 ||
    playerA.deck.length !== 26 ||
    playerB.hand.length !== 3 ||
    playerB.deck.length !== 26 ||
    state.centerPiles.pile_1.length !== 1 ||
    state.centerPiles.pile_2.length !== 1
  ) {
    throw new Error("Initialized game violates the 60-card distribution contract.");
  }
}

function initializeGameState(
  state: SprintMatchState,
  random: RandomSource = Math.random,
  nowMs: number = Date.now()
): boolean {
  if (state.status !== MatchStatus.Waiting || !bothPlayersConnected(state)) {
    return false;
  }
  if (!initialCardStateIsEmpty(state)) {
    throw new Error("Cannot initialize a waiting match with existing card state.");
  }

  const shuffledCards = cloneAndShuffleCards(CARD_CATALOG, random);
  const pile1Starter = shuffledCards[shuffledCards.length - 1];
  const pile2Starter = shuffledCards[shuffledCards.length - 2];
  if (!pile1Starter || !pile2Starter) {
    throw new Error("Cannot initialize center piles from the card catalog.");
  }

  const playerA = state.players[state.playerOrder[0]];
  const playerB = state.players[state.playerOrder[1]];
  const playerCards = shuffledCards.slice(0, shuffledCards.length - 2);
  if (playerCards.length !== 58) {
    throw new Error("Card allocation requires exactly 58 non-center cards.");
  }
  const playerADraw = drawCards(playerCards.slice(0, 29), 3);
  const playerBDraw = drawCards(playerCards.slice(29, 58), 3);
  playerA.deck = playerADraw.deck;
  playerA.hand = playerADraw.hand;
  playerB.deck = playerBDraw.deck;
  playerB.hand = playerBDraw.hand;
  state.centerPiles.pile_1 = [pile1Starter];
  state.centerPiles.pile_2 = [pile2Starter];
  state.status = MatchStatus.Active;
  state.stateVersion = 1;
  state.winnerId = null;
  state.endReason = null;
  state.startedAtMs = nowMs;
  state.endedAtMs = null;
  state.resultPersistencePending = false;
  state.resultPersisted = false;
  state.pendingMoves = [];
  state.nextPendingMoveSequence = 0;
  state.nextTieBreakerPlayerId = state.playerOrder[0];

  assertInitializedCardState(state);
  return true;
}

function initializeRematchRound(
  state: SprintMatchState,
  random: RandomSource = Math.random,
  nowMs: number = Date.now()
): boolean {
  if (
    state.status !== MatchStatus.Finished ||
    !state.resultPersisted ||
    state.resultPersistencePending ||
    state.rematchStartsAtMs === null ||
    nowMs < state.rematchStartsAtMs ||
    !bothPlayersConnected(state) ||
    !state.playerOrder.every(
      (userId) => state.rematchResponses[userId] === "accepted"
    )
  ) {
    return false;
  }

  state.playerOrder.forEach((userId) => {
    const player = state.players[userId];
    player.hand = [];
    player.deck = [];
    player.disconnectedAtMs = null;
    player.rttEstimateMs = null;
  });
  state.centerPiles = {pile_1: [], pile_2: []};
  state.status = MatchStatus.Waiting;
  state.stateVersion = 0;
  state.winnerId = null;
  state.endReason = null;
  state.startedAtMs = null;
  state.endedAtMs = null;
  state.resultPersistencePending = false;
  state.resultPersisted = false;
  state.lastBroadcastAtMs = null;
  state.pendingMoves = [];
  state.nextPendingMoveSequence = 0;
  state.nextTieBreakerPlayerId = state.playerOrder[0];
  state.lastActivityAtMs = nowMs;
  state.finishedEmptySinceMs = null;
  state.roundNumber += 1;
  state.rematchRequestedAtMs = null;
  state.rematchStartsAtMs = null;
  state.rematchExpired = false;
  state.rematchUnavailable = false;
  state.playerOrder.forEach((userId) => {
    state.rematchResponses[userId] = "pending";
  });

  return initializeGameState(state, random, nowMs);
}
