# C1: every hub command is tested against a real hub in CI

Status: **Approved** (owner, 2026-11-26: "make sure we add all test cases for all commands on the ci", then "yes
please" to C1 and C2). Risk: **medium**. Verification: `bash tests/run.sh`.

## Today and the gap
An audit found every `ade` command has a test that runs in CI on macOS and Ubuntu, but:
- `ade notify`, `chat`, `method`, `models`, `roles`, `sync`, `context`, `dispatch` and `agent-run` are tested only
  against a fake hub script (test_hostile D1: the arguments arrive intact). Nothing runs them against a real hub made
  from the ade-brain template; only `status` and `doctor` do (tests/e2e/clean.sh).
- The `suite` job installs tmux only on Linux, so on macOS the real-tmux tests (test_ui real_tmux, work_real_tmux;
  test_files explorer_in_real_tmux) print "skip".
- test_files pdf_real_tools skips when `pdftotext` is absent, which it is on both runners.

## Goal
A new e2e file, `tests/e2e/hub_commands.sh`, run by both `e2e-linux` and `e2e-macos`, makes a hub from the real
template (as clean.sh does, `ade hub new --no-github`) and runs each passed-through command against it, read-only or
offline forms only: no network, no real Claude (fake_claude), no Telegram, no secret. CI installs tmux and poppler
on macOS for the suite job, and poppler-utils on Linux, so those tests stop skipping.

## Acceptance criteria (each is a step in hub_commands.sh, or a CI change checked by a test)
1. **real_method**: `ade method check` runs the hub's bin/method and exits as it would run directly.
2. **real_models**: `ade models` shows the hub's models; `ade models set focus <model>` changes hub.conf and the next
   `ade models` shows it.
3. **real_roles**: `ade roles` lists the four core roles with their engines.
4. **real_context**: `ade context` prints the hub's context (its rules heading is there).
5. **real_sync**: `ade sync` with a local bare remote commits and pushes the hub's change; nothing left uncommitted.
6. **real_notify_chat**: `ade notify --from e2e "hello"` reaches the hub's journal or inbox as bin/notify does
   directly; `ade chat status` runs without Telegram set up and says it is not set up (exit as bin/chat).
7. **real_dispatch_agent_run**: `ade dispatch --list` and `ade agent-run --help` (or the nearest offline form) run the
   hub's scripts and exit as they do directly.
8. **ci_real_tools**: ci.yml installs tmux and poppler on macOS and poppler-utils on Linux for the suite, and both e2e
   jobs run hub_commands.sh; a test (test_releases or a new one) reads ci.yml and fails if any of these is missing.

Where a criterion's exact subcommand does not exist in the template's script, use the nearest real offline form and
say so in the PR; never a network call, never a real key.

## Out of scope
The real Gemini CLI, real Keychain, launchd, systemd and pass: they stay tested through fakes and the owner's manual
checks. ade-brain's own coverage is C2.
