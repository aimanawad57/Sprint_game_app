# Realtime Protocol Contract

## Opcode assignments

Opcode names must become named constants in both TypeScript and Dart when the
gameplay protocol is implemented.

### Client to server

| Opcode | Name | Purpose |
|---:|---|---|
| 1 | `submitMove` | Attempt to play a card onto a center pile. |

### Server to client

| Opcode | Name | Purpose |
|---:|---|---|
| 10 | `matchStarted` | Deliver the initial private player view. |
| 11 | `stateUpdate` | Deliver a new authoritative player view. |
| 12 | `moveRejected` | Explain why a submitted move was rejected. |
| 13 | `stuckReset` | Report that center piles were separately reshuffled. |
| 14 | `gameEnded` | Report the final state and winner. |
| 15 | `connectionChanged` | Report opponent connection or disconnection. |

The backend uses opcode `15` for connection changes. Its payload contains the
changes from the current callback and a full snapshot of connected user IDs.

## Client-to-server payload

### `submitMove` - opcode 1

```json
{
  "card_id": "card_017",
  "targetPileId": "pile_1",
  "expectedStateVersion": 8
}
```

Valid pile IDs:

```text
pile_1
pile_2
```

## Server-to-client payloads

### Player-specific state

Used by `matchStarted`, `stateUpdate`, `stuckReset`, and `gameEnded` as needed:

```json
{
  "stateVersion": 9,
  "status": "active",
  "myHand": [
    {
      "card_id": "card_017",
      "color": "red",
      "shape": "star",
      "count": 3
    }
  ],
  "myDeckCount": 24,
  "opponentHandCount": 3,
  "opponentDeckCount": 24,
  "centerPiles": {
    "pile_1": {
      "topCard": {
        "card_id": "card_009",
        "color": "blue",
        "shape": "star",
        "count": 5
      }
    },
    "pile_2": {
      "topCard": {
        "card_id": "card_052",
        "color": "yellow",
        "shape": "circle",
        "count": 2
      }
    }
  },
  "winnerId": null
}
```

Opcode `10` (`matchStarted`) is implemented. Its initial payload uses
`stateVersion: 1`, `status: "active"`, three cards in `myHand`, deck counts of
27, opponent hand count of 3, and one public top card for each center pile.
Nakama sends the payload separately to each player presence. It never includes
the opponent hand, either private deck, or center-pile history.

Opcodes `11` (`stateUpdate`) and `14` (`gameEnded`) are also implemented.
Nakama sends a fresh private player view after every accepted move. Flutter
replaces its local snapshot only from these authoritative messages and does not
move or draw cards optimistically.

### Move rejection - opcode 12

```json
{
  "stateVersion": 9,
  "card_id": "card_017",
  "targetPileId": "pile_1",
  "reason": "card_does_not_match"
}
```

## Stable rejection codes

```text
invalid_payload
match_not_active
player_not_in_match
card_not_in_hand
invalid_target_pile
card_does_not_match
stale_move
game_finished
```

Flutter converts these stable codes into user-facing text. Server code and
tests use the codes, not display sentences.

Opcode `12` (`moveRejected`) is implemented on both Nakama and Flutter. A
rejection leaves the current game snapshot unchanged and displays the stable
reason as user-facing feedback.

### Stuck reset - opcode 13

After every accepted non-winning move, Nakama checks both players' current
hands against both center-pile top cards. If no legal move exists, every center
pile with more than one card is shuffled independently; a one-card pile remains
unchanged while the other pile can still be shuffled. Cards never move between
the two piles. Player hands and private decks are unchanged.

Each reset increments `stateVersion`, sends a private opcode `13` player view,
and is checked again. Reset attempts are bounded to prevent an infinite loop.
Flutter handles opcode `13` as an authoritative state replacement. Reset is
deferred without changing player decks only when both center piles contain one
card; that edge case is intentionally reserved for a later rule decision.

## State-version policy

1. Every authoritative gameplay-state change increments `stateVersion` exactly once.
2. Rejected moves do not increment it.
3. The client submits the version it was viewing.
4. A version mismatch does not automatically reject the move.
5. The server validates the card against the current target-pile top.
6. If the move remains legal, the server accepts it.
7. If the changed state makes the move illegal, the server rejects it.

This permits a valid move when an opponent changed only the other center pile.

Presence-only changes do not increment `stateVersion`. Connecting or
disconnecting does not move cards and must not make a submitted gameplay move
stale. Initial card dealing will still establish gameplay version `1`.
