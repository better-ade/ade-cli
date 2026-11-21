# A2: `ade orchestrator`: run orchestrators across hubs

Status: Ready for development (2026-11-21). Risk: medium. Depends on ade-brain C5 (`bin/chat`) and ADR 0006
(orchestrators and channels). Verification command: `bash tests/run.sh`.

## Goal
Manage named orchestrators, one per hub, each with its channels (Telegram first), from any terminal.

```
ade orchestrator new <name> --hub <path> [--channel telegram]   register; runs the hub's `bin/chat setup <channel>`
ade orchestrator start|stop <name>                              runs the hub's `bin/chat start|stop`
ade orchestrator list                                           name, hub, channels, running or stopped, since
ade orchestrator logs <name> [-n N]                             the hub's chat log, last N lines
ade orchestrator remove <name>                                  unregister (stops it first; never deletes the hub)
```

The registry is `~/.config/ade/orchestrators` (one line per orchestrator: `name<TAB>hub`, file 0600). Names are
`[a-z0-9-]+`, unique; one orchestrator per hub. All work is done by the hub's own `bin/chat`; `ade` only finds the hub.

## Acceptance criteria (`tests/test_orchestrator.sh`, fake hubs with a fake `bin/chat`)
| AC | Criterion |
|---|---|
| 1 | `new` registers name and hub and calls the hub's `bin/chat setup telegram`; a bad name, a duplicate name or a second orchestrator for the same hub exits 2 |
| 2 | `start`/`stop` call the right hub's `bin/chat` with `HUB` exported to that hub |
| 3 | `list` shows every orchestrator with the status its hub's `bin/chat status` reports; a hub that is gone shows `missing` |
| 4 | `logs` prints the last N lines of that hub's chat log, never a secret (the log is the hub's; `ade` adds nothing) |
| 5 | `remove` stops a running orchestrator, then drops its line; the hub's files are untouched |
| 6 | The registry file is created 0600 and its folder 0700 |
| 7 | An unknown channel is passed through and the hub's refusal (exit 2) is returned unchanged |
