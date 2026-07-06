type StuckResetResult = {
  resetCount: number;
  stillStuck: boolean;
  blockedBySingleCardPiles: boolean;
};

type StuckResetObserver = (state: SprintMatchState) => void;

const MAX_STUCK_RESET_ATTEMPTS = 32;

function hasAnyLegalMove(state: SprintMatchState): boolean {
  const pile1Top = state.centerPiles.pile_1[state.centerPiles.pile_1.length - 1];
  const pile2Top = state.centerPiles.pile_2[state.centerPiles.pile_2.length - 1];
  if (!pile1Top || !pile2Top) {
    throw new Error("Cannot check stuck state without two center-pile top cards.");
  }

  for (let playerIndex = 0; playerIndex < state.playerOrder.length; playerIndex += 1) {
    const player = state.players[state.playerOrder[playerIndex]];
    for (let cardIndex = 0; cardIndex < player.hand.length; cardIndex += 1) {
      const card = player.hand[cardIndex];
      if (cardsMatch(card, pile1Top) || cardsMatch(card, pile2Top)) {
        return true;
      }
    }
  }

  return false;
}

function isGameStuck(state: SprintMatchState): boolean {
  return state.status === MatchStatus.Active && !hasAnyLegalMove(state);
}

function shuffledPile(cards: Card[], random: RandomSource): Card[] {
  const shuffled = cards.slice();
  for (let index = shuffled.length - 1; index > 0; index -= 1) {
    const randomValue = random();
    if (!Number.isFinite(randomValue) || randomValue < 0 || randomValue >= 1) {
      throw new Error(
        "Random source must return a finite value from 0 inclusive to 1 exclusive."
      );
    }

    const swapIndex = Math.floor(randomValue * (index + 1));
    const current = shuffled[index];
    shuffled[index] = shuffled[swapIndex];
    shuffled[swapIndex] = current;
  }
  return shuffled;
}

function reshuffleCenterPiles(
  state: SprintMatchState,
  random: RandomSource = Math.random
): boolean {
  if (!isGameStuck(state)) {
    return false;
  }

  const canShufflePile1 = state.centerPiles.pile_1.length > 1;
  const canShufflePile2 = state.centerPiles.pile_2.length > 1;
  if (!canShufflePile1 && !canShufflePile2) {
    return false;
  }

  if (canShufflePile1) {
    state.centerPiles.pile_1 = shuffledPile(state.centerPiles.pile_1, random);
  }
  if (canShufflePile2) {
    state.centerPiles.pile_2 = shuffledPile(state.centerPiles.pile_2, random);
  }
  state.stateVersion += 1;
  return true;
}

function resolveStuckState(
  state: SprintMatchState,
  onReset: StuckResetObserver,
  random: RandomSource = Math.random,
  maxAttempts: number = MAX_STUCK_RESET_ATTEMPTS
): StuckResetResult {
  if (!Number.isInteger(maxAttempts) || maxAttempts < 1) {
    throw new Error("Stuck reset maxAttempts must be a positive integer.");
  }

  let resetCount = 0;
  while (isGameStuck(state) && resetCount < maxAttempts) {
    if (!reshuffleCenterPiles(state, random)) {
      return {
        resetCount: resetCount,
        stillStuck: true,
        blockedBySingleCardPiles: true
      };
    }

    resetCount += 1;
    onReset(state);
  }

  return {
    resetCount: resetCount,
    stillStuck: isGameStuck(state),
    blockedBySingleCardPiles: false
  };
}
