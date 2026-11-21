# A11: `ade update` without stopping anything

Status: Ready for development (2026-11-21). Risk: high (replaces running code). Depends on A1–A6.
Owner's intent (2026-11-21): updates must not need to terminate the session. Verification command: `bash tests/run.sh`.

## Goal
`ade update` brings everything current while every session, agent and orchestrator keeps running:
- **ade itself:** download the release named in VERSION to a temp file in the same folder, verify it runs
  (`--version`), then one atomic `mv` over the old file. Never write the running file in place (bash reads scripts as it
  runs them).
- **the hub:** `git pull --ff-only` (refuse and explain when it would merge or the hub has local changes); then
  `bin/method sync` at the hub's pin.
- **plugins:** `claude plugin update` for each installed ade-skills plugin.
- **Claude Code:** `claude update` (A4's rule; running sessions keep their version until restarted).
- **`ade ui`:** `tmux source-file` reloads the theme and key table; `ade dash` re-execs itself when it sees a new version.
- **notify:** one `ade notify all` line: what changed, and "applies on your next prompt" (plus `/reload-plugins` when
  plugins changed).
- **restart-needed parts** (e.g. a new bin/chat for a running orchestrator): never kill; schedule a graceful restart
  for when the session is idle (bin/sessions shows idle), or ask; a busy session is never interrupted.
- A daily check (stamp file) offers `ade update` when a newer release exists; it never installs by itself.
- `ade update --check` prints what would change and changes nothing.

## Acceptance criteria (`tests/test_update.sh`; fake release server dir, fake claude/tmux, fixture hub)
| AC | Criterion |
|---|---|
| 1 | A running `ade` process (a long-running fake `ade dash` loop) keeps running correctly while `ade update` replaces the binary; the file is replaced by rename (inode changes), never written in place |
| 2 | A new binary that fails `--version` is not installed; the old one stays |
| 3 | The hub updates with `--ff-only`; local changes or a non-fast-forward refuse with the reason and change nothing |
| 4 | No session, agent or orchestrator process is killed during `ade update` (the fakes record no signals) |
| 5 | A restart-needed part on a busy session is scheduled for idle, not applied; on an idle session the graceful restart happens and is journaled |
| 6 | Running sessions get one notify line naming what changed |
| 7 | `--check` changes nothing; the daily check only offers |
| 8 | `ade ui` reloads its config without detaching; `ade dash` re-execs on a version change |
