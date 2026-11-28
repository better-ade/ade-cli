# F1: a first run reads right: Claude Code is checked before it is started, and one next step at a time

Status: **Approved** (owner, 2026-11-28; hub.conf: leave as is, say so). Risk: **medium** (wording and a check before start; no change to sign-in, keys, sync or what a
session may do). Verification: `bash tests/run.sh`.

## Today
The first-run walkthrough of 0.2.13 (a fresh HOME, `ade hub new demo --no-github`, then `ade`, `ade setup --check`,
`ade work`) showed:
1. `ade setup --check` said `claude code: missing`, yet `ade work ops/monitoring` went ahead: it never checks the
   hub's Claude Code command (`HUB_CLAUDE`, default `claude`) before starting a tab, so on a machine without it the tab
   opens on `claude: command not found` while `ade work` reports success.
2. `ade hub new` printed two `next:` lines that disagree: bin/init's hand-run line (`cd … && bin/setup && bin/brain
   index && bin/doctor, then start claude there`) and ade's own `next: ade (what to do next)`.
3. Bare `ade` with no agents printed an empty table header, then offered `ade` (the command just run) as the next step.
4. `ade help` still says of `ade web --tailnet` that anyone on the tailnet "with the link can read it"; since M2 the
   page also needs the code shown in the terminal.

## Acceptance criteria (each named by its test)
1. **work_needs_claude** (tests/test_work.sh): when the hub's Claude Code command is not found, `ade work <folder>`
   exits non-zero before starting anything (no tmux window, no agent row), with one line naming the missing command
   and `ade setup` as the fix.
2. **check_matches_work** (tests/test_setup.sh): `ade setup --check` checks the same command `ade work` runs (the
   hub's `HUB_CLAUDE`, else `claude`), so the two agree: missing in one is missing in both.
3. **hub_new_one_next** (tests/test_hub_new or the existing hub-new test): `ade hub new` prints exactly one `next:`
   line; bin/init's hand-run line is not shown (it stays in the run's log).
4. **bare_no_agents** (tests/test_ui.sh or the status test): bare `ade` outside the tab view with no agents prints
   `agents: none running` instead of an empty header, and its next steps do not offer `ade` itself.
5. **help_web_code** (tests/test_web.sh): `ade help`'s `web` entry says the page asks for the code shown in the
   terminal, for `--tailnet` too; no line says the link alone is enough.
6. **hub_new_conf_local** (the hub-new test): after the first save, `ade hub new` says in one line that hub.conf is
   not part of the saved version (bin/sync leaves it out) and how to commit it by hand if wanted; nothing commits it.

## Out of scope
- Committing `hub.conf` (owner, 2026-11-28: leave as is; criterion 6 only says so).
- Installing Claude Code from `ade work`.
- Anything in ade-brain.
