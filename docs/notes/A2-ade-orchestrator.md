# A2 design note: `ade orchestrator`

- The registry is `~/.config/ade/orchestrators` (`name<TAB>hub`), rewritten atomically through a 0600 temp file in a
  0700 folder. `ade` stores no channel or secret; channels come from the hub's `HUB_CHANNELS`.
- `new` validates first (name, hub, duplicates), then runs `bin/chat setup <channel>` for each `--channel`, and
  registers only when every setup succeeded: a refusal (e.g. an unknown channel, exit 2) is returned unchanged and
  leaves nothing registered.
- `list` asks each hub's `bin/chat status`; a hub that is gone (or has no `bin/chat`) shows `missing`.
- `logs` delegates to `bin/chat logs -n N` (default 50) so the hub, not `ade`, decides what its log holds.
- `remove` stops a running orchestrator first; when the stop fails it stays registered (exit 1).
- The `bin/chat` calls `ade` relies on are in `.ade/context/hub-interface.md`; C5 must provide `logs` and the
  `status` first-line shape.
