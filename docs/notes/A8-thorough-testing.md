# A8 design note: thorough testing

- Layer 1: `ci.yml` calls the org's `verify.yml` in a matrix (`ubuntu-latest`, `macos-latest`); a setup step puts a
  `bash` -> `/bin/bash` link first on `PATH`, so macOS runs every test file under Bash 3.2. `tests/run.sh` prints the
  bash it used. The checks are now `ci (ubuntu-latest) / verify` and `ci (macos-latest) / verify`: branch protection
  must require both (owner setting).
- Layer 2: `tests/lint.sh` (shellcheck `-S warning` over `ade`, `install.sh`, `tests/e2e/*.sh`, then a planted SC2164
  file that must fail); CI pins shellcheck v0.10.0. Three intentional `~` strings carry a `disable=SC2088` comment.
- Layer 3: `tests/test_hostile.sh` keys its table by `ade help`, so a new command without a row fails. Kinds: R
  (must exit 2), D (a hub script receives the input as one intact argument), S (search: 0/1/2). A canary file
  proves no input ran. Its first run found five bugs, fixed in `ade`: leading `-` names, newline names passing per-line
  `grep` checks (now one whole-string `matches` helper), `projects/..` passing the folder check, `setup --test ""`, and
  no length cap (64).
- Layers 4-6: `tests/e2e/` (network: the pinned real repos and the real ade-brain template; a fake `claude`, no
  secret). `interactive.sh` hands the key to expect on stdin (never argv) and checks the screen log, every `ps`
  listing taken while `bin/keys` reads, and every file.
- Layer 7: `ui_snapshots.sh` attaches a client inside an outer tmux (prefix moved to C-q) so `capture-pane` sees the
  tab bar and popups; goldens `tests/golden/ui-<W>x<H>-<view>.txt` (Linux tmux); `UPDATE_GOLDEN=1` rewrites. Found and
  fixed: the 44-column sidebar wrapped every row (now a compact layout below 70 columns), the help popup clipped.
- Layer 8: `tests/coverage.sh` runs kcov (container `kcov/kcov`, ptrace allowed) over the suite; the floor in
  `tests/coverage-floor` is the first measured figure rounded down.
