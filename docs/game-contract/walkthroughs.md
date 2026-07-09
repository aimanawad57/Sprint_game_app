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
8. Each player receives their own private state view.

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
Both players submit a move for pile_1 before the next match tick.
```

Result:

1. Nakama processes the first message against version 12.
2. If valid, the first card becomes the top of `pile_1` and the version becomes 13.
3. Nakama processes the second message against the updated pile top.
4. A submitted version of 12 does not automatically reject the second move.
5. If the second card matches the new top, it is accepted and the version becomes 14.
6. Otherwise it is rejected and the version remains 13.

  (We will see if we face problems with this decision or there is better logic)

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
8. Later move submissions are rejected with `game_finished`.
