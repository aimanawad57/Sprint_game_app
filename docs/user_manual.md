# Sprint user manual

## 1. About Sprint

Sprint is a two-player speed card game. Both players play at the same time, and
the first player to empty their hand and private deck wins.

Each card has three attributes:

- **Color**
- **Shape**
- **Count**: the number of shapes shown on the card

A card can be played when at least one attribute matches the top card of the
chosen center pile. For example, a blue star can be played on any blue card or
any star card.

## 2. Signing in

On the first screen, choose one option:

- **Sign in with Google** uses a Google account and display name.
- **Continue as Guest** creates a local guest identity for quick access.

The home screen shows backend availability. Multiplayer features require the
backend to be connected.

## 3. Game modes

Open **Play** from the home screen, then select a mode:

| Mode | Description |
| --- | --- |
| Tutorial | Guided lessons for selecting cards, matching attributes, using both piles, and recognizing invalid moves |
| Practice vs Bot | A complete local match against the computer |
| Quick Match | Searches for another online player automatically |
| Create Private Match | Creates a private match and displays a code to share |
| Join Private Match | Joins a waiting private match using its code |

New players may be offered the tutorial automatically. It can be restarted or
skipped at any time.

## 4. Playing a match

At the start of a round, each player has three visible cards and a private deck.
Two shared center piles appear in the middle. Multiplayer rounds begin after a
synchronized five-second countdown.

To play:

1. Select one card in your hand.
2. Decide which center pile it matches.
3. Select that pile.

After a valid move, the played card becomes the pile's new top card. If cards
remain in your deck, your hand is automatically refilled. An invalid move is
rejected and does not change the game.

There are no turns. Both players may submit moves simultaneously. The server
resolves competing moves and sends the confirmed result to both screens.

If neither player can play, Sprint reshuffles or replaces the center-pile cards
automatically. A **Piles reshuffled** notification confirms the reset.

## 5. Results and rematches

A normal match ends when one player has no cards left in either their hand or
deck. The result screen shows the winner and match time.

After a normal ending, either player can request a rematch. A new round begins
only after both players accept, using the same opponent and a fresh deal. A
rematch is not offered after a disconnect forfeit.

## 6. Connection recovery

If a connection becomes slow, a latency indicator appears. It remains hidden
when the connection is healthy.

If your connection drops during a match:

1. The arena remains visible and moves are paused.
2. Sprint retries the connection automatically.
3. Use **Retry now** if automatic recovery has not succeeded.
4. Use **Return to menu** after the recovery period expires.

If the app closes during a live match, the home screen may offer the saved match
again. Choose **Reconnect** to resume it or **Abandon** to leave it permanently.
An opponent who remains disconnected until the server deadline loses by
forfeit. If both players disconnect, the match may be abandoned without a
winner.

## 7. Profile, leaderboard, and feedback

- **Profile** shows games played, wins, losses, win rate, current win streak,
  best win streak, best winning time, and join date.
- **Leaderboard** is ranked by total wins and also displays win rate, current
  streak, and best time.
- The settings button in a multiplayer match controls sound effects and
  vibration independently. These preferences are saved locally.
- Reduced-motion device settings replace large animations with simpler visual
  feedback.

  