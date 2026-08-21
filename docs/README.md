# Sprint documentation

Use this directory as the starting point for understanding or deploying Sprint.

| Document | Purpose |
| --- | --- |
| [User manual](user_manual.md) | Rules, game modes, controls, and recovery steps |
| [Developer guide](dev_guide.md) | Setup, design, source ownership, and verification |
| [Architecture](architecture.md) | System boundaries, data flow, and source ownership |
| [Game contract](game-contract/README.md) | Reviewed cards, setup rules, and realtime wire contract |
| [Backend guide](../nakama/README.md) | Local Nakama stack and runtime checks |

When gameplay or protocol behavior changes, update the game-contract documents
and both Dart and TypeScript tests in the same change.
