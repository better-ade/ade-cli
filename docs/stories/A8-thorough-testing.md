# A8: thorough testing of the CLI

Status: Ready for development (2026-11-21). Risk: medium. Depends on A1–A7 (tests what they built).
Owner's decision (2026-11-21): layers 1–8 now; the nightly live smoke (a real Claude Code session with a CI secret
and a spending cap) is a later story. Verification command: `bash tests/run.sh` plus the new CI jobs below.

## Goal
Catch what fakes cannot: shell differences, unsafe quoting, hostile input, clean-machine installs, upgrades,
interactive prompts and the visual `ade ui`, with coverage that cannot silently drop.

| Layer | Implementation |
|---|---|
| 1. Shells | CI matrix through better-ade/.github verify: `macos-latest` running `/bin/bash` 3.2 and `ubuntu-latest` bash 5; `tests/run.sh` prints the bash version it used |
| 2. Lint | `shellcheck -S warning ade install.sh` in CI (pinned shellcheck version), failing on any warning |
| 3. Hostile input | `tests/test_hostile.sh`: one table of inputs (spaces, quotes, `$(…)`, backticks, leading `-`, `--dangerously-skip-permissions`, unicode, newline, 300-char names) run against every command that takes a name; each must exit 2 or treat the input as data, never run it |
| 4. Clean machine | `tests/e2e/clean.sh` in a fresh `ubuntu:24.04` container and on a fresh macOS runner: install with `install.sh` from this commit, `ade hub new --no-github`, `ade init` in a real git repo, `ade agent add frontend` and `ade skills add git` against the pinned real repos, `ade status`, `ade doctor`; real git and tmux |
| 5. Upgrade | `tests/e2e/upgrade.sh`: install the previous release tag, create a hub and a project, upgrade to this commit, re-run status, doctor and init (no file lost or overwritten) |
| 6. Interactive | `tests/e2e/setup.exp` (expect) and tmux `send-keys` drive `ade setup` with fakes for the sign-in steps; assert screen text, and that a typed key never appears on screen, in argv (`ps`) or in any file |
| 7. Visual `ade ui` | real tmux at 120×36 and 80×24: `capture-pane -p` snapshots of the tab bar, fleet sidebar and each popup compared with golden files in `tests/golden/`; `UPDATE_GOLDEN=1` rewrites them |
| 8. Coverage | `kcov` over `tests/run.sh` on Linux; the report is a CI artifact; the job fails when line coverage of `ade` drops below the floor in `tests/coverage-floor` (set to the first measured value, rounded down) |

## Acceptance criteria
| AC | Criterion |
|---|---|
| 1 | CI runs the suite on macOS (bash 3.2) and Ubuntu (bash 5); both must pass for the `ci` check |
| 2 | shellcheck runs pinned and fails the build on a planted warning (checked once by a test PR or a self-test) |
| 3 | The hostile-input table covers every name-taking command; adding a command without adding it to the table fails the test (the test lists `ade help` commands) |
| 4 | The clean-machine job passes on ubuntu:24.04 and macOS from a fresh install of this commit |
| 5 | The upgrade job passes from the previous release tag |
| 6 | The interactive test proves a typed key is never shown, in argv or in a file |
| 7 | The `ade ui` snapshots match golden files at both sizes; a deliberate layout change fails until goldens are updated |
| 8 | The coverage job publishes a report and fails below the floor |
| 9 | README "Contributing" describes the layers and how to run each locally |
