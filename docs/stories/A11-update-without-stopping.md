# A11: `ade update` without stopping anything

Status: In review (2026-11-22; fix round after the adversarial review); the daily check (AC7, second half) comes with A12. Risk: high (replaces running code). Depends on A1–A6.
Owner's intent (2026-11-21): updates must not need to terminate the session. Verification command: `bash tests/run.sh`.

## Goal
`ade update` brings everything current while every session, agent and orchestrator keeps running:
- **ade itself:** download the release named in VERSION to a private temp folder (never a folder on PATH), check it
  there without making it executable (shebang, `bash -n`, the end-of-file marker as its last line, `ade version`),
  then keep the installed file as `.ade.prev` beside it (not executable) and rename the new one over it in one `mv`.
  Never write the running file in place (bash reads scripts as it runs them). A trap removes every temp file on EXIT,
  INT and TERM. `ade update --rollback` puts `.ade.prev` back (and keeps the current one as `.ade.prev`).
- **the hub:** `git pull --ff-only` (refuse and explain when it would merge or the hub has local changes to tracked
  files; untracked files such as a journal entry never block, and `merge --ff-only` itself refuses to overwrite one); then
  `bin/method sync` at the hub's pin.
- **plugins:** `claude plugin update` for each installed ade-skills plugin.
- **Claude Code:** `claude update` (A4's rule; running sessions keep their version until restarted).
- **`ade ui`:** `tmux source-file` reloads the theme and key table; `ade dash` re-execs itself when it sees a new version.
- **notify:** one `ade notify all` line: what changed, and "applies on your next prompt" (plus `/reload-plugins` when
  plugins changed).
- **restart-needed parts** (e.g. a new bin/chat for a running orchestrator): never kill; schedule a graceful restart
  for when the session is idle (bin/sessions shows idle), or ask; a busy session is never interrupted.
- A daily check (stamp file) runs the auto-update policy of A12 (patch/minor install automatically, majors ask).
- `ade update --check` prints what would change and changes nothing.

## Acceptance criteria (`tests/test_update.sh`; fake release server dir, fake claude/tmux, fixture hub)
| AC | Criterion |
|---|---|
| 1 | A running `ade` process (a long-running fake `ade dash` loop) keeps running correctly while `ade update` replaces the binary; the file is replaced by rename (inode changes), never written in place |
| 2 | A new binary that fails its check (shebang, `bash -n`, end-of-file marker, `ade version`) is not installed; the old one stays; while it is checked nothing new in the install folder is executable; an interrupted update leaves no temp file |
| 3 | The hub updates with `--ff-only`; local changes to tracked files or a non-fast-forward refuse with the reason and change nothing; an untracked file does not block |
| 4 | No session, agent or orchestrator process is killed during `ade update` (the fakes record no signals) |
| 5 | A restart-needed part on a busy session is scheduled for idle, not applied; on an idle session the graceful restart happens and is journaled |
| 6 | Running sessions get one notify line naming what changed |
| 7 | `--check` changes nothing; the daily check follows A12's auto-update policy |
| 8 | `ade ui` reloads its config without detaching; `ade dash` re-execs on a version change |
| 9 | The previous ade is kept as `.ade.prev`; `ade update --rollback` swaps it back, refusing a kept file that fails its check |
