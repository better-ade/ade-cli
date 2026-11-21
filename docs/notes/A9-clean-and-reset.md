# A9 design note: ade clean, ade reset, ade uninstall

- Nothing is deleted that a user made. `clean` removes only housekeeping: lock folders (`pid`, `start` removed, then
  `rmdir`; a lock with anything else in it stays), `dispatch/<name>` markers over 2 minutes old, `events-seen/<id>`
  cursors unused for 7 days (the hub's own rule), `$TMPDIR/ade.*` folders of this user over a day old (the `rm_tmp`
  rule), `ade-*` sessions on ade's tmux server whose panes are all dead, and worktrees whose branch is in the base
  branch (ACCESS.md's Branch, else origin's HEAD, else main/master; local or `origin/`) with an empty `git status`,
  removed with `git worktree remove` (no `--force`; the branch stays). A lock is stale only when its pid names no
  process (`ps -p`), or it has no pid and is over 2 minutes old; it is checked again just before removal.
- Without `--yes`, `clean` at a terminal asks; otherwise it prints the plan and changes nothing.
- `reset` checks everything first (arguments, the `--hub` refusals, `uninstall`'s checkout refusal: all exit 2 with
  nothing changed), lists the plan, asks once, then for `--hub` asks for the hub's name (a wrong one: exit 1, nothing
  changed). Order: orchestrators stopped, services unloaded and removed, the `ade@ade-skills` entry dropped, keys
  forgotten (one question each, EOF = keep), journal lines, the hub moved, then `~/.config/ade/` and the binary.
- `--hub` refusals: not its own git top level, `git status --porcelain` not empty, a stash, no remote, or commits on
  any branch not on a remote (`git log --branches --not --remotes`).
- The Trash: macOS uses `$ADE_TRASH_CLI` (default `trash`) when on PATH, else Finder through `osascript` with the
  path as an argument (`on run argv`), never spliced into the script. Linux moves the folder with `mv` into
  `~/.local/share/ade/trash/<folder>-<UTC yyyymmddThhmmssZ>/` (0700) and prints the `mv` line that restores it. The
  move is checked: if the folder is still there, exit 1 and `~/.config/ade` is kept.
- The services are `ai.agent-hub.<HUB_NAME>.{chat,monitor}` (bin/schedule's labels): plists in
  `$AGENT_LAUNCHAGENTS` (`~/Library/LaunchAgents`), units in `~/.config/systemd/user/`; whichever files exist are
  removed, `launchctl bootout` / `systemctl --user disable --now` run when the tool is there.
- `ade setup` records `<hub>\t<tool>` in `~/.config/ade/keys-set` when it stores a key (names only); `--keys` offers
  only those.
- Unverified here: the real Finder call (tests fake `uname`, `trash` and `osascript`; no real Trash is touched). The
  AppleScript compiles (`osacompile`).
