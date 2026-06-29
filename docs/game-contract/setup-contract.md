# Match Setup Contract

## Player ordering

Player order comes from the matchmaker result and is stored explicitly:

```text
Player A = first user in the matchmaker result
Player B = second user in the matchmaker result

playerOrder = [playerAId, playerBId]
```

Do not use JavaScript object iteration order to assign cards. Player order is
an internal stable identifier and must not grant a gameplay advantage.

## Array convention

The last array element is the top:

```text
deck[deck.length - 1] = next card to draw
pile[pile.length - 1] = visible top card
```

- Drawing removes the last element from the private deck.
- Playing appends the card to the selected center pile.

## Initialization algorithm

The authoritative Nakama match performs setup:

```text
1. Copy all 62 catalog cards.
2. Shuffle the copy on the Nakama server.
3. Pop 1 card into center pile 1.
4. Pop 1 card into center pile 2.
5. Give the next 30 cards to Player A.
6. Give the remaining 30 cards to Player B.
7. Pop 3 cards from Player A's private deck into Player A's hand.
8. Pop 3 cards from Player B's private deck into Player B's hand.
9. Set the initial state version to 1.
10. Start the match only after both expected players have joined.
```

The connection-change event for the second player is broadcast before setup.
After setup, Nakama sends one targeted `matchStarted` event to each player.
Initialization is guarded by match status and empty card state, so a reconnect
cannot reshuffle or redeal an active match.

## Initial state

```text
Player A:
  hand: 3
  private deck: 27

Player B:
  hand: 3
  private deck: 27

Center pile 1: 1
Center pile 2: 1
```

## Setup acceptance checks

- Exactly 62 card IDs exist across all state locations.
- Every catalog ID occurs exactly once.
- Both hands contain exactly 3 cards.
- Both private decks contain exactly 27 cards.
- Both center piles contain exactly 1 card.
- The two center cards do not belong to either player's allocated 30 cards.
- Player A cannot receive Player B's hand or deck contents.
- Player B cannot receive Player A's hand or deck contents.
- Neither player receives the order of their own remaining private deck.

These checks are enforced by permanent backend tests and by a runtime
card-conservation assertion after every initial deal.
