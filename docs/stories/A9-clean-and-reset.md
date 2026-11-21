# A9: `ade clean` and `ade reset`

Status: In review (2026-11-21). Risk: high (removes things). Depends on A1–A7.
Owner's intent (2026-11-21): "make sure ade-cli has a reset or clean". Verification command: `bash tests/run.sh`.
Change of design (owner-approved, 2026-11-21): nothing is deleted. `ade reset --hub` moves the hub to the Trash;
`ade clean` removes only ade's and the hub's own housekeeping files, never a user's file.

## Goal
Three commands, from gentlest to strongest. Each shows a list of what it would do and does nothing until confirmed
(`--yes` skips the prompt for `clean` only). Nothing ever deletes a hub's files, a project's code, git history or
uncommitted work. A hub leaves its place only by `--hub`, after its name is typed, and then goes to the Trash.

| Command | Does |
|---|---|
| `ade clean` | Housekeeping only, never a user's file: stale locks whose owner is gone (sync, dispatch, chat), dispatch start markers older than 2 min, event cursors unused for 7 days (`events-seen/`), temp folders `ade` made (`ade.*`, over a day old), tmux sessions `ade-*` with no live agent, git worktrees whose branch is merged, removed with `git worktree remove` only when clean (the branch stays). Safe to run any time. |
| `ade reset` | Undoes `ade setup` on this machine: stops orchestrators (`ade orchestrator stop`), removes the chat and monitor services it installed, removes `~/.config/ade/` (default hub, orchestrator registry), and the `ade@ade-skills` plugin entry it added to settings. Keeps hubs, projects, keys and Claude Code. Options: `--keys` also forgets the keys `ade setup` stored (`bin/keys forget`, one confirmation per key); `--hub <path>` also moves that hub folder to the Trash (never deletes it), only after typing the hub's name, refusing if it has uncommitted, stashed or unpushed work: macOS the Finder Trash (`trash` when installed, else `osascript -e 'tell application "Finder" to delete POSIX file …'`), Linux `~/.local/share/ade/trash/<hub>-<UTC timestamp>/`; it prints where it went and how to restore it. |
| `ade uninstall` | `ade reset`, then removes the `ade` binary. Claude Code and other tools stay. |

## Acceptance criteria (`tests/test_clean.sh`, fixture hubs and projects, fakes for tmux/launchctl/systemctl)
| AC | Criterion |
|---|---|
| 1 | `ade clean` with no flag prints the plan and changes nothing; `--yes` performs exactly the listed items |
| 2 | A lock whose owner is alive, a worktree with uncommitted changes, and a tmux session with a live agent are never removed |
| 3 | `ade reset` stops orchestrators, removes the services and `~/.config/ade/`, and leaves hubs, projects, keys and Claude Code untouched (checked by file listing before and after) |
| 4 | `--keys` forgets only keys recorded as set by `ade setup`, one confirmation each; refusing one keeps it |
| 5 | `--hub <path>` requires typing the hub name, refuses a hub with uncommitted, stashed or unpushed work (or one outside git), moves it to the Trash (macOS: `trash` or Finder; Linux: `~/.local/share/ade/trash/<hub>-<UTC timestamp>/`) and never deletes it, prints where it went and how to restore it, and moves nothing else; a failed move leaves it in place |
| 6 | `ade uninstall` removes the binary last and prints how to reinstall |
| 7 | Every run writes one line to the journal of each affected hub saying what was cleaned or reset |
| 8 | Running any of them twice in a row: the second run finds nothing to do |
