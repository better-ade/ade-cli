# I3 (ade-cli): ade hub import <url> brings in someone's hub: handover, share or clone

Status: **Approved** (owner, 2026-11-26: "ok go"). Depends on I1 and I2 (ade-brain). Repo: better-ade/ade-cli.
Risk: medium (clones and, for a clone, creates a private GitHub repo; no secret is read or moved).
Found by: the owner wants `ade hub import <url>`.
Verification: ade-cli's `bash tests/run.sh`, plus the e2e job below.

## Goal
`ade hub import <url|path> [--handover|--share|--clone] [--owner <name>] [--name <new>] [--dir <folder>]
[--no-github]`:
- Asks the mode when no flag is given (a terminal), refuses without one otherwise.
- Clones into `<dir>/<name>` (default the same folder `ade hub new` uses), checks it is a hub (`is_hub`), runs the
  hub's `bin/setup`, then `bin/adopt <mode>`; for `--clone` creates the person's own private repo the way `ade hub
  new` does (`hub_first_save`), unless `--no-github`.
- Remembers it as the default hub (`remember_hub`) and prints `bin/adopt`'s "what's left" list.
- A source without `bin/adopt` (a hub older than I2) is refused with "update that hub first".

## Acceptance criteria
1. Each mode clones, runs `bin/setup` and `bin/adopt` with the right flags, and makes the hub the default
   (`tests/test_hub.sh`, fake hub scripts).
2. No mode flag and no terminal: exit 2, nothing cloned. A target folder that exists: refused, nothing changed.
3. `--clone` without `--no-github` runs `gh repo create <name> --private` and pushes; with it, no `gh` call.
4. A source without `bin/adopt`: refused with the reason, the clone removed.
5. `ade hub` usage lists `import`; README and CHANGELOG describe it.
6. **End to end** (`tests/e2e/import.sh`, in CI's e2e jobs on Linux and macOS): `ade hub new --no-github` in HOME A
   from the real template (pinned to the I2 commit), then in HOME B `ade hub import <path> --share`, `--handover`,
   `--clone --no-github`; each ends with `bin/doctor` passing and `ade hub list` showing it.

## Out of scope
Copying secrets, Telegram pairing or launchd jobs (the list tells the person); importing a hub that is not ade-brain.
