# C3: an end-to-end test of check-ins and `ade web` on a real hub

Status: **Approved** (owner, 2026-11-27: "Add e2e", then approved C3). Risk: **medium** (test and CI only; no change to `ade` or the hub). Verification: `bash tests/run.sh`.

## Today and the gap
S1 (ade-brain: focus agents check in, a quiet one reaches main), M1 (`ade web` dashboard) and M2 (its auth code) each
have unit tests, but only against fakes: test_web.sh uses a fake hub, and ade-brain's test_checkin.sh never runs
`ade web`. Nothing shows that a quiet agent in a real hub ends up on the real dashboard, behind the real code.

## Goal
A new e2e file, `tests/e2e/web.sh`, run by both `e2e-linux` and `e2e-macos`. It makes a hub from the real ade-brain
template (`ade hub new --no-github`, as hub_commands.sh does), drives a focus session's hooks with fake_claude, starts
`ade web` under a pty, and reads the dashboard over HTTP as the page does. It runs offline, with no real Claude and no secret.

## Acceptance criteria (each is a step in tests/e2e/web.sh)
1. **e2e_checkin_nudge**: with `HUB_CHECKIN_MINUTES=1` and a busy focus folder, the folder's PostToolUse hook prints
   the check-in instruction once the period is up, and not before.
2. **e2e_checkin_resets**: `bin/notify` to main from that folder is its check-in (the event has `"checkin": true`)
   and the next tool call is not nudged.
3. **e2e_quiet_reaches_main**: with no check-in after a nudge, `bin/monitor` writes one `quiet` event to main with
   the folder name; running it again writes no second one.
4. **e2e_web_code**: `ade web --no-open` under a pty prints its link on stdout and its code on the terminal only;
   `/api/agents` answers 401 until `POST /login` with that code, then 200.
5. **e2e_web_shows_quiet**: after login, `/api/agents` lists the focus folder with its quiet alert and its last
   check-in, and `/api/events` has the `quiet` event.
6. **e2e_web_stop**: `ade web --stop` ends it; the port no longer answers and the hub's git status is unchanged by
   ade web.
7. **ci_e2e_web**: ci.yml runs tests/e2e/web.sh in both e2e jobs; a test reads ci.yml and fails if it is missing.

## Out of scope
A real browser (test_web.sh already covers the page with Chromium), Telegram forwarding of `quiet`, `--tailnet`.
