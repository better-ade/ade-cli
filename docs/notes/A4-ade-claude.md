# A4 design note: `ade claude`

- `ade claude` = `claude [--model $HUB_ROOT_MODEL] --remote-control <HUB_NAME> [args after --]`, run at the hub root
  with `HUB` (and `CLAUDE_CONFIG_DIR` from `HUB_CLAUDE_CONFIG_DIR`) exported, using `HUB_CLAUDE` when the hub names
  another claude command. No `HUB_ROOT_MODEL`: no `--model`, so the hub's `.claude/settings.json` model applies.
- `ade claude <folder> [args]` is exactly `ade work <folder> [args]`.
- `--dangerously-skip-permissions` anywhere in the arguments is refused (exit 2) before anything runs.
- The settings merge is idempotent and writes only when something changed (temp file, then rename).
- The `ade` plugin itself is not in ade-skills yet; enabling it ahead of time is harmless until it ships.
- A non-Anthropic orchestrator provider (A5's top agent) is not launched here yet; that needs the hub's provider path.
