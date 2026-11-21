# A4: `ade claude` opens Claude Code on the hub

Status: Ready for development (2026-11-21). Risk: medium. Depends on A1, A3. Verification: `bash tests/run.sh`.
Owner's intent (2026-11-21): "make this work with Claude Code CLI, the ade CLI."

## Goal
`ade claude` starts Claude Code at the default hub's root (the orchestrator session) with the hub's orchestrator model,
Remote Control named after the hub, and the `ade` plugin from ade-skills enabled for the project; `ade claude <folder>`
is `ade work <folder>`. Extra arguments after `--` go to `claude` unchanged, except `--dangerously-skip-permissions`,
which is refused.

## Acceptance criteria (`tests/test_claude.sh`, fake `claude` and hub)
| AC | Criterion |
|---|---|
| 1 | `ade claude` runs `claude` in the hub root with `--model <hub orchestrator model>` and `--remote-control <hub name>` |
| 2 | The hub's `.claude/settings.json` lists the ade-skills marketplace and enables `ade@ade-skills` (added once, never duplicated, other keys kept) |
| 3 | `ade claude projects/x` runs the hub's `bin/work projects/x` |
| 4 | `ade claude -- --resume` passes `--resume` through; `--dangerously-skip-permissions` anywhere exits 2 |
| 5 | No hub: exits 2 with the `ade hub new` hint |
