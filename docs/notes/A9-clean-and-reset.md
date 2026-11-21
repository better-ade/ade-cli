# A9 design note: ade clean, ade reset, ade uninstall

- Nothing is deleted that a user made. `clean` removes only housekeeping: the hub's locks `sync.lock`,
  `dispatch.lock`, `chat/lock` (under the hub's `<lock>.gc` guard, taken with `mkdir` around the stale check and the
  removal; `pid` and `start` removed, then `rmdir`), `dispatch/<name>` markers over 2 minutes old, `events-seen/<id>`
  cursors unused for 7 days, `$TMPDIR/ade.*` folders of this user in which nothing changed for a day (the newest file
  counts), `ade-*` sessions on ade's tmux server whose panes are all dead, and worktrees removed with
  `git worktree remove` (no `--force`; the branch stays) only when all hold: a branch (not detached, not locked), its
  tip differs from the base tip and is not on the base's first-parent line (a fresh or fast-forwarded branch is never
  "merged"), the tip is in the base, `git status --porcelain --ignored` is empty (ignored files such as `.env` count),
  and no live tmux pane (default or ade's server) works inside it.
- A lock is stale only when its pid names no process (`ps -p`), or it has no pid and is over 2 minutes old.
- Without `--yes`, `clean` at a terminal asks; otherwise it prints the plan and changes nothing.
- `reset` and `uninstall` answer only a person: every question (the go-ahead, the hub's name, each key) is read from
  `/dev/tty`, and they refuse (exit 2, nothing changed) when stdin is not a terminal or a Claude Code session is
  detected (`CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_SESSION_ID`). Tests type the answers on a pty.
- `--hub` refusals (exit 2, before any question): `/`, `$HOME`, or any folder holding `$HOME` or `~/.config/ade`
  (physical paths); not its own git top level; `git status --porcelain --ignored` not empty; a stash; a linked
  worktree; a nested `.git`; no remote; any commit not on a remote (`git log HEAD --branches --tags --not --remotes`);
  a live `ade ui` session; a live agent (`bin/sessions` rows busy, idle or blocked); a hub lock with a live pid; on
  Linux, the hub's parent and ade's trash root on different filesystems (ade moves only by rename).
- Order after the answers: orchestrators stopped, services removed, the `ade@ade-skills` entry dropped, keys
  forgotten (one question each), then for `--hub` a "moving" line in the other hubs' journals, the hub's
  `bin/schedule uninstall`, the move; then `~/.config/ade/` and the binary. A failed orchestrator stop or a failed
  move keeps `~/.config/ade` (and the binary), and exits 1. One summary line per other hub says only what happened.
  Nothing is ever written into the hub that moves, so a restored hub is as clean as it was.
- The Trash: macOS uses `$ADE_TRASH_CLI` (default `trash`) when on PATH, else Finder through `osascript` with the
  path as an argument (`on run argv`). If a folder of that name was already in the Trash, ade prints only the Put Back
  hint (no path, no `mv` line). Linux renames into `~/.local/share/ade/trash/<folder>-<UTC yyyymmddThhmmssZ>/`
  (0700) and prints the `mv` line that restores it; a partial move is reported as such, never as "still at".
- `~/.local/share/ade/moved-hubs` (`path<TAB>where<TAB>UTC time`) lets a second `reset --hub` say "nothing to do".
- The services are `ai.agent-hub.<HUB_NAME>.{chat,monitor}` (bin/schedule's labels): plists in
  `$AGENT_LAUNCHAGENTS` (`~/Library/LaunchAgents`), units in `~/.config/systemd/user/`; `launchctl bootout` /
  `systemctl --user disable --now` run when the tool is there.
- `ade setup` records `<hub>\t<tool>` in `~/.config/ade/keys-set` when it stores a key (names only); `--keys` offers
  only those.
- Unverified here: the real Finder call and the cross-device refusal on macOS (tests fake `uname`, `trash` and
  `osascript`; the cross-device test runs where `/dev/shm` is another filesystem, as on Linux CI).
