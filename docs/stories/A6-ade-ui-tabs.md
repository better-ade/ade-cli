# A6: `ade ui`: a visual terminal workspace with a tab per agent

Status: Ready for development (2026-11-21, revised). Risk: medium. Depends on A1, A4; ade-brain V1's tmux mode.
Owner's intent (2026-11-21): "add the tab capability on the CLI and just make it visual" (in place of the desktop app's
panes, fleet view and plan preview). Verification command: `bash tests/run.sh`.

## Goal
`ade ui` opens (or re-attaches to) tmux session `ade-<hub>` with a themed, visual layout:
- **Tab bar** (tmux status, colours from one theme file): one tab per agent with a state icon (● orchestrator,
  ⟳ busy, ○ idle, ⚠ blocked), folder, role and ticket; `[+ new]` at the end; unread C6 events mark the tab.
- **Fleet sidebar** (`ade dash`, toggled with prefix `f`): a light live panel (refresh every 2 s, plain ANSI, no extra
  runtime beyond bash and python3) showing each agent's state, ticket, run time and tokens when known; tickets ready
  and waiting for the owner; the last 8 events.
- **Popups** (tmux display-menu / display-popup): prefix `n` new agent (pick folder and role from lists), `a` approve a
  waiting ticket (runs `ade dispatch --approve` in the popup's own terminal, so the owner types the ticket back),
  `t` tickets, `p` preview the selected agent's plan (`glow` when installed, else plain text), `?` help.
- Agents keep running when the window closes or SSH drops; `ade ui` re-attaches to the same layout.

## Acceptance criteria (`tests/test_ui.sh`: a fake `tmux` records calls; real tmux where available)
| AC | Criterion |
|---|---|
| 1 | `ade ui` creates `ade-<hub>` with tab 0 running the orchestrator; a second `ade ui` attaches and never duplicates |
| 2 | `ade work <folder>` while the session exists opens a tab named `<folder>[:<ticket>]` |
| 3 | The tab bar renders the state icon, folder, role and ticket per tab from `bin/sessions`, using the theme file's colours |
| 4 | `ade dash --once` prints the fleet panel (agents, tickets ready/waiting, last events) matching a golden file for fixture data |
| 5 | The key table binds n, a, t, p, f, ? to the documented menus and popups |
| 6 | The approve popup runs `ade dispatch --approve <ref> <folder>` inside the popup terminal (never with a fake TTY) |
| 7 | A tab with unread events is marked; marking clears after the agent reads them |
| 8 | Without tmux, exits 2 with the platform's install command; without glow, preview falls back to plain text |
