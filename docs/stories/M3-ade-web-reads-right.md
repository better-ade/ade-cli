# M3: `ade web` reads right on a fresh hub, and its quiet alert says how long

Status: **Approved** (owner, 2026-11-27: "All", on the devex evaluation's six findings). Risk: **medium** (page and
terminal wording, layout; no change to sign-in, the code, or what the server reads). Verification: `bash tests/run.sh`.
Depends on: M1, M2, C3 (merged).

## Today
The devex walkthrough of 0.2.13 (C3's e2e hub) showed:
1. A fresh hub looks broken: the template's `Updated: (UTC date and time, by whom)` shows as the agent's state line,
   main reads `unknown` and `no STATE.md line yet`.
2. The quiet alert reads `monitoring is quiet (for 0m)` right after detection, while the agent has been silent 12 min:
   `since` is the quiet event's time, not the agent's last sign of life.
3. A quiet agent's row shows a green `✓ checked in 45s ago` beside its ▲.
4. The top bar's `● 0 ○ 0 ◐ 0 ▲ 1 ✖ 0`, `sync –`, `monitors –` and the rows' `!` have no legend outside `?`.
5. On a wide screen the events list cuts sender names (`ops/monito…`) with room to spare.
6. The code page's hint and `ade web`'s start message are long (the start message wraps at 110 columns).

## Acceptance criteria (each named by its test in tests/test_web.sh)
1. **web_state_placeholder**: a STATE.md line whose whole value is a parenthesised placeholder (`Updated: (UTC date
   and time, by whom)`, i.e. `^[^:]{1,40}: \(.*\)$`) is skipped when picking the state line. A STATE.md with only
   headings and placeholders gives no line, and the row reads `no state yet`.
2. **web_main_not_running**: main with no session reads `not running` (dim), not `unknown`; its detail says `no
   STATE.md yet` when the hub root has none.
3. **web_quiet_for**: the quiet alert counts from the folder's last sign of life (the later of its last check-in, its
   last non-quiet event and its LAST), and reads `<name> is quiet: no check-in for <n>m (since HH:MMZ)`.
4. **web_quiet_row**: on a quiet row the check-in reads `last check-in <n> ago` in the dim colour; the green `✓
   checked in` is kept for rows that are not quiet.
5. **web_legend**: every top-bar count, `sync`, `monitors`, `inbox` and a row's `!` carry a `title` naming what they
   are (and, for `!`, the alert's text); `sync –` and `monitors –` read `sync none yet` and `monitors none`.
6. **web_wide_names**: at 1280 px the events list shows a sender's full folder name (up to 32 characters) without
   cutting it; at phone width the layout is unchanged.
7. **web_short_text**: `ade web`'s start message has no line over 100 columns (the link line excepted); the code page
   shows one hint line under the prompt, and the rest moves to `?`.
8. **web_devex_screens**: screenshots of a fresh hub and of a quiet agent (dark, light, phone) are saved for the owner.

M1's and M2's tests still pass unchanged in meaning (update only the wording they assert).

## Out of scope
The quiet event's own text (ade-brain's `bin/checkin`; story S2 there), sign-in and code logic, acting from the page.
