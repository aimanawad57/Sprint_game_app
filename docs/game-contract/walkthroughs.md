# Contract Walkthroughs

These are examples to validate the behavior we want.

## 1. Normal move

Initial facts:

```text
stateVersion = 8
Player A hand contains card_012: red star x2
pile_1 top is card_005: yellow star x3
Player A private deck is not empty
```

Player A submits:

```json
{
  "card_id": "card_012",
  "targetPileId": "pile_1",
  "expectedStateVersion": 8
}
```

Result:

1. Nakama identifies Player A from the message sender.
2. `card_012` is confirmed in Player A's hand.
3. The move matches because both cards have the `star` shape.
4. The server removes `card_012` from the hand.
5. The server appends `card_012` to `pile_1`.
6. The server draws one replacement from Player A's private deck.
7. The server increments `stateVersion` to 9.
8. Each player receives their own private state view with one confirmed
   `card_played` transition. Player A sees `actor: "self"`; Player B sees
   `actor: "opponent"`. Neither payload exposes an actor user ID.

## 2. Illegal move

Initial facts:

```text
stateVersion = 9
Player A card: red star x2
pile_2 top: blue tree x5
```

No color, shape, or count matches.

Result:

1. The server rejects the move with `card_does_not_match`.
2. No card changes location.
3. No replacement card is drawn.
4. `stateVersion` remains 9.
5. Only Player A needs the rejection response.

## 3. Concurrent moves

Initial facts:

```text
stateVersion = 12
Player A submits a valid move for pile_1.
Player B submits a valid move for pile_2 inside the same fairness window.
```

Result:

1. Nakama validates and queues both candidates against version 12.
2. When the fairness window closes, both moves are revalidated.
3. Because the moves target different piles, both are applied in
   reaction-adjusted response-time order.
4. The batch increments `stateVersion` once, to 13.
5. Each private state view contains two ordered `card_played` transitions.
6. Each recipient sees its own transition as `self` and the other transition as
   `opponent`.

If both candidates target the same pile, only the reaction-adjusted winner is
applied. The losing candidate receives `stale_move` and is not included in the
transition array.

## 4. Final move

Initial facts:

```text
stateVersion = 27
Player A private deck is empty
Player A hand contains one legal card
```

Result:

1. The server validates and plays the card.
2. No replacement is drawn because the private deck is empty.
3. Player A's hand and deck are both empty.
4. The server declares Player A the winner.
5. Match status becomes `finished`.
6. The state version increments.
7. Both players receive `gameEnded` with their appropriate private views.
8. The final private views include the winning `card_played` transition so the
   placement can finish before the result presentation.
9. Later move submissions are rejected with `game_finished`.

## 5. Reconnect countdown

Initial facts:

```text
Player B disconnects during an active round.
disconnectTimeout = 30 seconds
```

Result:

1. Nakama records Player B's disconnect timestamp.
2. Opcode `15` includes `disconnectGraceMs: 30000`, `serverTimeMs`, and the
   absolute `disconnectDeadlineMs`.
3. Both clients pause move controls; a connected client may render the remaining
   time using the shared server deadline.
4. If Player B reconnects in time, a new opcode `15` carries a null deadline and
   Player B receives a private resynchronization snapshot with no transitions.
   That targeted send refreshes Player B's reaction-time anchor without changing
   Player A's anchor.
5. If the deadline expires, only Nakama decides the outcome and sends opcode
   `14`; clients never declare the forfeit from their local timer.
