# Realtime Protocol Contract

## Opcode assignments

Opcode names must become named constants in both TypeScript and Dart when the
gameplay protocol is implemented.

### Client to server

| Opcode | Name | Purpose |
|---:|---|---|
| 1 | `submitMove` | Attempt to play a card onto a center pile. |
| 2 | `abandonMatch` | Explicitly forfeit the active match. |
| 3 | `rematchDecision` | Accept/request or decline a rematch. |

### Server to client

| Opcode | Name | Purpose |
|---:|---|---|
| 10 | `matchStarted` | Deliver the initial private player view. |
| 11 | `stateUpdate` | Deliver a new authoritative player view. |
| 12 | `moveRejected` | Explain why a submitted move was rejected. |
| 13 | `stuckReset` | Report that center piles were separately reshuffled. |
| 14 | `gameEnded` | Report the final state and winner. |
| 15 | `connectionChanged` | Report opponent connection or disconnection. |
| 16 | `rematchStatus` | Report rematch request, decline, expiry, start, or unavailability. |

The backend uses opcode `15` for connection changes. Its payload contains the
changes from the current callback, a full snapshot of connected user IDs, the
configured disconnect grace, server time, and the active disconnect deadline
when one exists.

## Client-to-server payload

### `submitMove` - opcode 1

```json
{
  "card_id": "card_017",
  "targetPileId": "pile_1",
  "expectedStateVersion": 8,
  "reactionTimeMs": 240
}
```

`reactionTimeMs` is optional: how long the player took to submit the move
after their client processed the state update it responds to, measured on the
device's own clock. The server uses it to resolve contested piles by reaction
speed instead of network arrival order (see the fairness window below). The
claim is clamped to the server-observed time since the last broadcast, and
compensation only applies when `expectedStateVersion` matches the current
state version. A missing or malformed value falls back to arrival-order
resolution, so older clients keep working.

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
  "elapsedTimeMs": 37250,
  "transitions": [
    {
      "type": "card_played",
      "actor": "self",
      "card": {
        "card_id": "card_012",
        "color": "red",
        "shape": "star",
        "count": 2
      },
      "targetPileId": "pile_1"
    }
  ],
  "myRttEstimateMs": 84,
  "myRttSampleSequence": 3,
  "myHand": [
    {
      "card_id": "card_012",
      "color": "red",
      "shape": "star",
      "count": 2
    }
  ],
  "myDeckCount": 24,
  "opponentHandCount": 3,
  "opponentDeckCount": 24,
  "centerPiles": {
    "pile_1": {
      "topCard": {
        "card_id": "card_005",
        "color": "yellow",
        "shape": "star",
        "count": 3
      }
    },
    "pile_2": {
      "topCard": {
        "card_id": "card_052",
        "color": "green",
        "shape": "diamond",
        "count": 4
      }
    }
  },
  "winnerId": null,
  "winnerName": null,
  "endReason": null
}
```

`elapsedTimeMs` is the authoritative elapsed match duration at the time the
payload is created. Active matches use the server's current time relative to
the recorded match start; finished matches keep the final start-to-end
duration. Clients may advance an active value locally with a monotonic clock,
but must freeze the timer at the value in the finished state.

`transitions` describes only public actions confirmed in the authoritative
state change carried by this payload. A confirmed play uses
`type: "card_played"`, the public played `card`, and its `targetPileId`.
`actor` is deliberately viewer-relative: the moving player receives `"self"`
and the other player receives `"opponent"`. The wire payload never exposes the
actor's user ID. When valid moves land on both piles in one fairness batch, the
array contains both transitions in reaction-adjusted resolution order. Initial
round snapshots, reconnect snapshots, and updates without an accepted card play
use an empty array, so clients do not replay an old animation.

`myRttEstimateMs` is the server-smoothed non-negative whole-millisecond RTT
estimate for this snapshot's viewer, or `null` until the server can derive one
from that player's submitted move timing. The first valid sample becomes the
estimate; later samples use an exponential moving average with alpha `0.25`.
`myRttSampleSequence` starts at `0` each round and increments for every fresh
RTT sample, even when rounding leaves the estimate unchanged. Clients can use
the sequence to distinguish a newly sampled value from a repeated snapshot.
A player never receives the opponent's estimate or sequence. These fields are
advisory presentation data for a degraded-only connection indicator; they do
not replace server-authoritative move validation or fairness calculations.

Opcode `10` (`matchStarted`) is sent once per round. Its payload uses
`stateVersion: 1`, `status: "active"`, three cards in `myHand`, deck counts of
26, opponent hand count of 3, and one public top card for each center pile.
Nakama sends the payload separately to each player presence. It never includes
the opponent hand, either private deck, or center-pile history.
When the game is finished, `winnerId` contains the winner's stable user ID and
`winnerName` contains the winner's Nakama account display name for UI
rendering. If the account display name cannot be resolved, the backend falls
back to the realtime presence username and then `"Player"`.
`endReason` is `null` until the match ends, then one of `normal`, `forfeit`,
or `abandoned`.

Opcodes `11` (`stateUpdate`) and `14` (`gameEnded`) are also implemented.
Nakama sends a fresh private player view after every accepted move. Flutter
replaces its local snapshot only from these authoritative messages and does not
move or draw cards optimistically. The transition metadata lets Flutter animate
the confirmed change while the snapshot remains authoritative. A winning final
move is included in the opcode `14` view in the same way.

Opcode `11` is also the reconnection resynchronization message. When a canonical
player joins a match that is already active or finished, Nakama sends the
current private player view only to that newly joined presence. Resynchronizing
does not increment `stateVersion`, redeal cards, reshuffle piles, or restart
the current round. A delayed leave event from an older socket session cannot mark
the replacement session disconnected. Flutter accepts the equal-version
snapshot because presence reconnection may not involve a gameplay-state change.
The targeted snapshot updates only the reconnecting player's private
`lastStateSentAtMs` timing anchor; it cannot change the opponent's reaction-time
anchor.

### Rematch decision and status

After `gameEnded`, either player may send opcode `3` with
`{"accept": true}` or `{"accept": false}`. Requesting counts as acceptance.
The first acceptance broadcasts opcode `16` with `status: "requested"`,
`requestedBy`, and `expiresInMs`. Declining broadcasts `status: "declined"`.
Requests expire after 30 seconds, and a departing player makes the rematch
unavailable.

Once both players accept, the rematch enters a locked preparation phase.
Further decisions and request expiry cannot change it. If the previous result
is still being stored, the server first broadcasts `status: "preparing"`.
Only after persistence succeeds does it broadcast `status: "starting"` with
the next `roundNumber`, `startsInMs: 5000`, the absolute `startsAtMs` deadline,
and `serverTimeMs`. Both clients show a synchronized five-second countdown.
Joining or reconnecting players receive the current deadline directly.

The server then creates a fresh shuffled round,
resets round-specific timers, moves, winner data, fairness state, and persistence
guards, and sends a new private opcode `10` state to both players. The match ID,
player identities, display names, and current presences remain unchanged.

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
player_disconnected
stale_move
game_finished
```

Flutter converts these stable codes into user-facing text. Server code and
tests use the codes, not display sentences.

Opcode `12` (`moveRejected`) is implemented on both Nakama and Flutter. A
rejection leaves the current game snapshot unchanged and displays the stable
reason as user-facing feedback.

Nakama does not apply a valid submitted move immediately. It first validates the
move against the current authoritative state, queues the valid candidate, and
waits a fairness window from the first queued move. Obvious invalid moves are
still rejected immediately.

The fairness window is sized adaptively per match from the gap between the two
players' measured round-trip times (`(max(RTT) - min(RTT)) / 2`, clamped to
100-300ms), so two
low-latency players resolve near-instantly while a real latency gap gets a
wider window. RTT is derived from each player's own moves
(`receivedAt - lastStateSentAt - reactionTime`) and is smoothed server-side;
until an estimate exists a 150ms default is used. `lastStateSentAt` is private
to each player and records when the server last sent that player a full or
targeted state snapshot. This prevents a reconnect snapshot sent to one player
from shifting the other player's fairness timing.

When the fairness window is processed, Nakama revalidates all ready candidates.
If two ready valid moves target different center piles, both moves can be
applied in the same authoritative update. If two ready valid moves target the
same center pile, only one can win that pile. The winner is the move with the
smaller reaction-adjusted response time
(`lastStateSentAtMs + reactionTimeMs`), so the player who genuinely reacted
faster wins regardless of whose packet arrived first. Only on an exact tie
does the server fall back to an alternating tie-break priority between the two
players. The losing same-pile candidate is rejected as `stale_move`.

Nakama rejects a submitted move with `player_disconnected` unless both
canonical players have an active match presence. This server-side rule is
authoritative; Flutter also disables move controls while opcode `15` reports
that either player is disconnected.

### Connection change - opcode 15

```json
{
  "changes": [
    {"userId": "player-b", "status": "disconnected"}
  ],
  "connectedUserIds": ["player-a"],
  "connectedCount": 1,
  "expectedCount": 2,
  "disconnectGraceMs": 30000,
  "disconnectDeadlineMs": 1784800851954,
  "serverTimeMs": 1784800821954
}
```

`serverTimeMs` is the server timestamp at which the connection snapshot was
created. `disconnectGraceMs` is the configured disconnect grace duration and is
present on every connection snapshot; its current value is 30 seconds. During
an active match, `disconnectDeadlineMs` is the absolute server deadline at
which the current disconnect state can resolve the match; it is `null` when no
active disconnect timer exists. If both players are disconnected with different
timestamps, the payload uses the earliest deadline because that is when
abandonment can first become authoritative. Clients calculate the visible
remaining time from these server-clock values, but they never declare a timeout
or winner locally. A reconnect event carries `disconnectDeadlineMs: null`, and
the eventual opcode `14` remains the only authority for a forfeit or
abandonment result.

### Stuck reset - opcode 13

After every accepted non-winning move, Nakama checks both players' current
hands against both center-pile top cards. If no legal move exists, every center
pile with more than one card is shuffled independently; a one-card pile remains
unchanged while the other pile can still be shuffled. Cards never move between
the two piles during normal pile reshuffles. Player hands and private decks are
unchanged for this normal reset path.

If both center piles contain exactly one card and no legal move exists, Nakama
uses the player decks to replace those pile tops while preserving deck counts.
The first card from Player A's deck becomes the new `pile_1` top card, and the
old `pile_1` card is inserted back into Player A's deck at a non-front
position. The same rule applies to Player B's deck and `pile_2`. This special
replacement only runs when both players have enough deck cards to avoid putting
the old pile card back as the next draw.

Each reset increments `stateVersion`, sends a private opcode `13` player view,
and is checked again. Reset attempts are bounded to prevent an infinite loop.
Flutter handles opcode `13` as an authoritative state replacement.

## State-version policy

1. Every authoritative gameplay-state change increments `stateVersion` exactly once.
2. Rejected moves do not increment it.
3. The client submits the version it was viewing.
4. A version mismatch does not automatically reject the move.
5. The server validates the card against the current target-pile top before
   queueing it.
6. Valid candidates wait in the adaptive fairness window.
7. When the window is processed, the server revalidates each ready candidate
   against the current target-pile top.
8. A batch of one or more accepted moves increments `stateVersion` once.
9. If the changed state makes a queued candidate illegal, the server rejects it.

This permits a valid move when an opponent changed only the other center pile.
It also lets two players who reacted to the same visible state compete fairly
inside the server-side window, resolving contested piles by reaction-adjusted
response time instead of making raw network arrival order the deciding factor.

Presence-only changes do not increment `stateVersion`. Connecting or
disconnecting does not move cards and must not make a submitted gameplay move
stale. Initial card dealing will still establish gameplay version `1`.

## Crash-safe match resumption

Each waiting or active match publishes a server-owned recovery pointer for
every assigned player. Authenticated RPC `get_resumable_match` reads only the
caller's pointer, verifies that the referenced authoritative match still
exists, and signals the match to confirm that the caller is assigned and that
the match has not finished. Invalid or stale pointers are removed and the RPC
returns `{ "matchId": null }`.

Flutter also stores the joined match ID locally under a per-user key as soon as
joining succeeds. At startup it reconciles that local hint with the RPC: the
live server match wins, an authoritative empty result clears stale local data,
and an unavailable server falls back to the local hint. Authoritative game end
and explicit abandonment clear both projections. Conditional server cleanup
checks the stored match ID before deletion so an older match cannot erase a
newer recovery pointer.

## Disconnect timeout and abandonment

When a player leaves an active match, Nakama records the disconnect time and
pauses gameplay by rejecting moves with `player_disconnected`. If the player
reconnects before timeout, the disconnect timer is cleared and the player
receives the existing opcode `11` private resynchronization snapshot.

If exactly one player remains disconnected for 30 seconds, the disconnected
player forfeits. Nakama marks the match `finished`, sets the connected opponent
as `winnerId`, sets `endReason: "forfeit"`, increments `stateVersion`, and
sends opcode `14` to connected presences. Flutter shows the winner
`Opponent disconnected, You Won!`; a forfeiting player who later reconnects to
the finished match sees the forfeit loss state.

If both players are disconnected when the timeout fires, Nakama finishes the
match with `winnerId: null` and `endReason: "abandoned"`. This abandoned result
does not update player statistics.

Flutter can also send opcode `2` (`abandonMatch`) while joined to an active
match. Nakama validates that the sender is one of the match players, declares
the opponent winner immediately, and uses the same `endReason: "forfeit"` as
the automatic timeout path.

## Match cleanup and termination

Nakama terminates matches that no longer need to stay alive:

- waiting quickplay matches and match-code lobbies expire after 5 minutes if
  the game never starts;
- active matches with no meaningful activity for 15 minutes become
  `finished` with `endReason: "abandoned"`;
- abandoned matches terminate after both players are gone;
- normal and forfeit finished matches terminate only after result persistence
  is no longer pending and both players are gone;
- empty finished matches use a short 5-second grace period before termination.

Match-code storage records are deleted when a code lobby expires or when the
associated match is cleaned up. Codes remain valid while an assigned player is
still connected so a dropped player can continue to resolve the match ID for
reconnection.

## Match-result statistics

Flutter loads the current player profile through authenticated RPC
`get_or_create_profile`. The RPC reads `player/profile` for `ctx.userId`,
creates a default server-owned profile when missing, and returns the profile
JSON. Clients do not write profile storage directly.

When a player empties both their hand and private deck, Nakama sends opcode
`14` before scheduling profile persistence for the following match tick. Both
profiles increment `gamesPlayed`; the winner increments `wins` and
`currentWinStreak`, while the loser increments `losses` and resets
`currentWinStreak` to zero. `bestWinStreak` preserves the highest completed
streak. The winner's `bestTimeMs` becomes the lower of its existing value and
the authoritative match duration.

Forfeit results also update wins, losses, and win streaks, but do not update
`bestTimeMs`. Abandoned results do not update profile statistics. The wins
leaderboard score is total wins only; win rate, current streak, and best time
are display metadata and do not affect rank.

Both profile updates use one atomic Nakama storage operation. Match-state
guards prevent the same result from being applied twice, and a failed write
remains pending for retry on a later tick. Profile objects are owner-readable
but client read-only so gameplay statistics remain server-authoritative.
