# Sprint Nakama Backend

Local Nakama backend for the Sprint Flutter app.

## Services

- Nakama API and realtime socket: `http://127.0.0.1:7350`
- Nakama console: `http://127.0.0.1:7351`
- Nakama gRPC: `127.0.0.1:7349`
- PostgreSQL: `127.0.0.1:5432`

For Android emulator clients, use `10.0.2.2:7350` instead of `127.0.0.1:7350`.
For physical phones, use the Windows machine LAN IP.

## Start

```powershell
cd nakama
docker compose up
```

Rebuild the runtime image after TypeScript changes:

```powershell
docker compose up --build nakama
```

## Runtime

Runtime logic is TypeScript under `src/` and is compiled into the Nakama image.
The first RPC is `healthcheck`, intended as a simple app-to-backend connectivity test.

Run backend validation with:

```powershell
npm run type-check
npm test
```

The test suite validates the runtime catalog against the reviewed CSV, initial
card distribution, privacy of player views, one-time match initialization, and
authoritative move processing. It also covers stuck detection, separate center-
pile resets, repeated stuck checks, and the deferred single-card-pile case.
Finished matches also update both server-authoritative player profiles on the
tick after the final realtime state is sent.

## Verify RPC

Create a local device session and call the runtime healthcheck RPC:

```powershell
$pair = 'defaultkey:'
$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$auth = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:7350/v2/account/authenticate/device?create=true' -Headers @{ Authorization = "Basic $basic" } -ContentType 'application/json' -Body '{"id":"local-healthcheck-device"}'
$rpc = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:7350/v2/rpc/healthcheck' -Headers @{ Authorization = "Bearer $($auth.token)" } -ContentType 'application/json' -Body '""'
$rpc
```

## Database

PostgreSQL data is stored in the Docker volume `nakama_postgres_data`.
Each developer gets their own local database by default.

If shared data is needed later, prefer a shared Nakama server connected to a shared PostgreSQL database. Avoid pointing many different local Nakama servers at one shared database.

## gRPC

Nakama exposes gRPC on port `7349`. The Flutter app should usually use the client API and realtime socket on `7350`; gRPC is mainly useful later for backend-to-backend tooling or low-level integrations.
