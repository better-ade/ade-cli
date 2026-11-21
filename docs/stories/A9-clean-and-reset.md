# A9: `ade clean` and `ade reset`

Status: Ready for development (2026-11-21). Risk: high (deletes things). Depends on A1–A7.
Owner's intent (2026-11-21): "make sure ade-cli has a reset or clean". Verification command: `bash tests/run.sh`.

## Goal
Three commands, from gentlest to strongest. Each shows a list of what it would do and does nothing until confirmed
(`--yes` skips the prompt for `clean` only). Nothing ever deletes a hub's files, a project's code, git history or
uncommitted work unless named explicitly and confirmed by typing its name.

| Command | Does |
|---|---|
| `ade clean` | Housekeeping only: stale locks whose owner is gone (sync, dispatch, chat), dispatch start markers older than 2 min, expired event cursors, temp folders `ade` made, tmux sessions `ade-*` with no live agent, git worktrees whose branch is merged (never one with uncommitted changes). Safe to run any time. |
| `ade reset` | Undoes `ade setup` on this machine: stops orchestrators (`ade orchestrator stop`), removes the chat and monitor services it installed, removes `~/.config/ade/` (default hub, orchestrator registry), and the `ade@ade-skills` plugin entry it added to settings. Keeps hubs, projects, keys and Claude Code. Options: `--keys` also forgets the keys `ade setup` stored (`bin/keys forget`, one confirmation per key); `--hub <path>` also removes that hub folder, only after typing the hub's name, refusing if it has uncommitted or unpushed work. |
| `ade uninstall` | `ade reset`, then removes the `ade` binary. Claude Code and other tools stay. |

## Acceptance criteria (`tests/test_clean.sh`, fixture hubs and projects, fakes for tmux/launchctl/systemctl)
| AC | Criterion |
|---|---|
| 1 | `ade clean` with no flag prints the plan and changes nothing; `--yes` performs exactly the listed items |
| 2 | A lock whose owner is alive, a worktree with uncommitted changes, and a tmux session with a live agent are never removed |
| 3 | `ade reset` stops orchestrators, removes the services and `~/.config/ade/`, and leaves hubs, projects, keys and Claude Code untouched (checked by file listing before and after) |
| 4 | `--keys` forgets only keys recorded as set by `ade setup`, one confirmation each; refusing one keeps it |
| 5 | `--hub <path>` requires typing the hub name, refuses a hub with uncommitted or unpushed work, and removes nothing else |
| 6 | `ade uninstall` removes the binary last and prints how to reinstall |
| 7 | Every run writes one line to the journal of each affected hub saying what was cleaned or reset |
| 8 | Running any of them twice in a row: the second run finds nothing to do |
