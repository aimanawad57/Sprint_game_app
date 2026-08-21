# Sprint

Sprint is a real-time two-player speed card game built with Flutter and an
authoritative Nakama backend. Players race to empty their hands by matching a
center-pile card by color, shape, or count.

## Highlights

- Quickplay matchmaking and private matches with short join codes
- Server-authoritative cards, move validation, timers, results, and rematches
- Automatic reconnect and locally persisted resumable-match recovery
- Practice bot and guided tutorial using the same card-matching rules
- Animated match feedback, optional sound and vibration, and reduced-motion UI
- Player profiles and a wins-first leaderboard with win and streak statistics

## Architecture

The Flutter app owns presentation, input, local preferences, and connection
coordination. The Nakama TypeScript runtime owns competitive game state and
decides whether moves are valid. Clients receive privacy-filtered views rather
than the complete match state.

See [Architecture](docs/architecture.md) for component responsibilities and
[Game contract](docs/game-contract/README.md) for the card catalog and realtime
protocol.

## Requirements

- Flutter with a Dart SDK compatible with `^3.11.5`
- Docker Desktop with Docker Compose
- Node.js 22 when running backend tests directly outside Docker

## Run locally

Start the backend:

```powershell
cd nakama
Copy-Item .env.example .env
docker compose up -d --build
cd ..
```

Then install Flutter packages and launch the app:

```powershell
flutter pub get
flutter run
```

The default client host is `10.0.2.2`, which reaches the host machine from an
Android emulator. Desktop, iOS simulator, and web development normally use:

```powershell
flutter run --dart-define=NAKAMA_HOST=127.0.0.1
```

Physical devices must use a reachable LAN or deployed hostname. The host value
must not include `http://` or `https://`.

Google sign-in can be configured with `GOOGLE_SERVER_CLIENT_ID`; guest sign-in
remains available for local development and demos.

## Verify changes

```powershell
flutter test
flutter analyze --no-pub
cd nakama
npm test
```

The backend test command includes TypeScript compilation. For a clean runtime
check, rebuild the service with `docker compose up -d --build nakama`.

## Project map

| Path | Responsibility |
| --- | --- |
| `lib/screens/` | Player-facing pages and navigation composition |
| `lib/controllers/` | Long-lived game-session state and lifecycle coordination |
| `lib/services/` | Nakama transport, decoding, reconnect, persistence, and feedback |
| `lib/models/` | Immutable client-facing data contracts |
| `lib/gameplay/` | Shared client-side card matching helpers |
| `lib/practice/` | Offline practice state and bot logic |
| `lib/widgets/` | Reusable UI and match presentation |
| `nakama/src/` | Authoritative TypeScript runtime, RPCs, and match handlers |
| `docs/` | User, developer, architecture, and protocol documentation |
| `test/`, `nakama/test/` | Flutter and backend regression suites |

## Documentation

- [Documentation index](docs/README.md)
- [User manual](docs/user_manual.md)
- [Developer guide](docs/dev_guide.md)
- [Architecture](docs/architecture.md)
- [Backend guide](nakama/README.md)
- [Realtime game contract](docs/game-contract/README.md)

Local defaults such as `defaultkey`, development database credentials, and
example application identifiers are intentionally convenient for development.
Replace them with production values before exposing a build publicly.
