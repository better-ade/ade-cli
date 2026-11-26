# M1: `ade web`, a live web dashboard of the hub's agents

Status: **Approved** (owner, 2026-11-26: "approve m1"). Risk: **high** (it serves hub data on a local port: access).
Found by: the owner (2026-11-26): "we need a really good UI interface to monitor the agents"; the owner chose a web
dashboard over the terminal dash.
Verification: `bash tests/run.sh`.
Depends on: ade-brain S1 (check-ins and `quiet` events). M1 shows them when present and works without them.

## Goal
`ade web` starts a small read-only server on 127.0.0.1 and opens the dashboard in the browser. It updates every few
seconds with:
- **One card per agent** (orchestrator and each focus session): state (busy, idle, ready, blocked, quiet), folder,
  role, engine and model, how long in that state, the last STATE.md line, and the time since its last check-in.
- **Alerts at the top:** a quiet agent, an agent waiting on a prompt (busy with an old time), a monitor ALERT, unread
  notes to main.
- **An event feed:** notes, check-ins, pushes, contracts, ended sessions, and the last hub syncs from sync.log.
- **A click on a card** shows that folder's STATE.md and its recent journal lines. To act, it shows the command to
  run (`ade work …`, `ade ui`); the page itself never acts.

## Look and feel: a premium terminal UI in the browser (owner, 2026-11-26: "make the dashboard premium feel
please", then "the web frontend can be a terminal UI")
- **Feel.** The page *is* a terminal UI: a monospace grid, box-drawing panes, keyboard first. It is as crisp as a
  well-made TUI (btop, lazygit, k9s), but sharper than a real terminal can be: true pixel hairlines, smooth
  scrolling, and subpixel text. It should not look like a website imitating a terminal; it should look like the best
  terminal you have used.
- **One product.** It uses `ade ui`'s colour tokens (bg, fg, accent, orchestrator, busy, idle, blocked, unread),
  read from the user's `~/.config/ade/theme`, so the browser and the tmux view match. It is dark first; a light
  variant uses the same tokens.
- **Type.** One bundled monospace font (inline, no external request) with ligatures off and tabular figures. Text is
  sized on a character grid, so panes align to whole cells.
- **Layout.** A tmux-like frame:
  - a top status bar: hub name, a count per state, sync and monitor health, and a live clock;
  - the left pane: the agent list, one row each with a state glyph (● busy, ○ idle, ◐ ready, ▲ quiet, ✖ blocked),
    folder, role, model, a live time-in-state counter, and the last STATE line;
  - the right pane: the selected agent's STATE.md and journal;
  - the bottom pane: the event feed, scrolling like a log;
  - alerts appear as a highlighted line in the status bar and a marked row, like a TUI.
- **Motion.** Terminal-honest: a blinking cursor in the filter prompt, a busy glyph that cycles (a braille spinner),
  and rows that update in place without layout jumps. All of it is off under `prefers-reduced-motion`.
- **Keyboard.** `j`/`k` or the arrows move, Enter focuses a pane, Tab cycles panes, `/` filters, `e` jumps to events,
  `?` shows a help overlay, and `q` or Esc closes it. The mouse works too: clicking selects.
- **Small screens.** At phone width the panes stack (list, then detail, then events), with no sideways scrolling.
- **States.** Designed empty, error and "reconnecting" states, written as terminal lines (for example
  `· waiting for the hub… retrying in 3s`), never a broken page.
- **Review.** The owner sees screenshots with a realistic fake hub (dark, light, phone width) before the PR is marked
  ready; the build does not finish on tests alone.

## Acceptance criteria (each named by its test in tests/test_web.sh)
1. **web_loopback_only**: the server binds 127.0.0.1 only, on a free port, and refuses a non-loopback bind.
2. **web_token_required**: every request needs the random per-run token from the URL ade opens. Without it the
   answer is 403 and nothing is read. The token never appears in logs or `ps`.
3. **web_read_only**: only GET; any other method is 405. No route runs a hub command that changes state.
4. **web_agents_json**: `/api/agents` matches `bin/sessions` plus the orchestrator, with each STATE line and check-in
   time (a fake hub in the test).
5. **web_events_json**: `/api/events?since=` returns the event log's entries after the cursor. Text is escaped on
   the page, and key-shaped strings are hidden (as `ade shot` hides them).
6. **web_alerts**: quiet, stuck-at-prompt, monitor ALERT and unread-to-main each appear as an alert in the fake hub.
7. **web_page_renders**: the page loads with no external network (all assets inline). It works in light and dark,
   and at phone width. A headless check with `ade shot url` sees the cards.
8. **web_stops_cleanly**: Ctrl-C, or `ade web --stop`, ends the server; `ade web` again reuses nothing stale.
9. **web_no_hub_writes**: running the dashboard for a whole test leaves the hub, its state folder and the real
   `~/.config/ade` unchanged.
10. **web_premium_checks**: an automated check of the design rules: the page makes no external requests; both themes
    pass WCAG AA contrast for text; nothing scrolls sideways at 375px; reduced motion turns the animations off; and
    screenshots (dark, light, phone) are saved for the owner's review.

## Out of scope
- Remote access (from a phone or another machine). That is a later story, needing sign-in.
- Acting from the page (approve, start or stop agents).
- The terminal `ade dash`, which stays as it is.
