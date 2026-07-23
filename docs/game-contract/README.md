# Sprint Game Contract

This directory contains the reviewed contract for the Sprint game core. Nakama
implements the catalog, initial deal, private player views, gameplay moves,
connection events, stuck resets, game ending, and profile statistics. Flutter
renders the authoritative server state and submits player moves.

## Documents

- [Card catalog inventory](card-catalog.csv) - the approved 60-card catalog.
- [Card catalog rules](card-catalog.md) - allowed attributes and validation rules.
- [Setup contract](setup-contract.md) - shuffle, deal, player ordering, and invariants.
- [Realtime protocol](realtime-protocol.md) - opcodes, payloads, rejection codes, and version policy.
- [Contract walkthroughs](walkthroughs.md) - normal, illegal, concurrent, and winning examples.

## Frozen decisions

- The game has exactly two players.
- The catalog has exactly 60 physical cards.
- Two cards become the initial center-pile cards.
- The remaining 58 cards are split evenly, so each player receives 29 cards.
- Each player initially draws 3 cards, leaving 26 in their private deck.
- The server shuffles and owns all authoritative state.
- Player A is the first user in the matchmaker result.
- Player B is the second user in the matchmaker result.
- The last array element is always the top of a deck or pile.
- A move matches by color, shape, or count.
- A successful move automatically refills the hand when the deck is not empty.
- A rejected move does not change state or increment the state version.
- A version mismatch causes revalidation, not automatic rejection.
- Presence-only connection changes do not increment the gameplay state version.
- Initial dealing is complete when both expected players connect and establishes gameplay version `1`.
- Every round starts from one authoritative server deadline; reconnecting
  players receive the remaining countdown directly.
- Reconnection never reshuffles, redeals, or restarts the current round;
  the rejoining player receives a targeted opcode `11` private state snapshot.
- A mutually accepted rematch creates a fresh round inside the same authoritative
  match after result persistence and sends one new `matchStarted` event per player.
