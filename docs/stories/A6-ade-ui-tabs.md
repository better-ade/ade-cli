# A6: `ade ui`: one terminal window, a tab per agent

Status: Ready for development (2026-11-21). Risk: medium. Depends on A1, A4; ade-brain's tmux terminal mode (V1).
Owner's intent (2026-11-21): "a tab-like interface for focus agents, like our desktop terminal."

## Goal
`ade ui` opens (or re-attaches to) a tmux session `ade-<hub>`: tab 0 is the orchestrator (`ade claude`), each focus
agent gets its own tab. While it runs, `bin/work` (with `AGENT_TERMINAL=tmux`, set by `ade ui`) opens new agents as
tabs in it. The tab bar shows each agent's folder, role, ticket and busy/idle (from `bin/sessions`, every 5 s) and marks
a tab with unread events (C6). Keys: prefix + number or arrows to switch; prefix `n` starts a focus agent (asks folder
and role); prefix `x` closes a tab, asking first when the agent is busy. Detaching never stops agents.

## Acceptance criteria (`tests/test_ui.sh`, a fake `tmux` recording calls; real tmux where available)
| AC | Criterion |
|---|---|
| 1 | `ade ui` creates session `ade-<hub>` with tab 0 running the orchestrator; a second `ade ui` attaches, never duplicates |
| 2 | `ade work <folder>` while the session exists opens a new tab named `<folder>[:<ticket>]` running that agent |
| 3 | The status line shows folder, role, ticket and busy/idle per tab, from `bin/sessions` |
| 4 | A tab with unread events (C6 log) is marked |
| 5 | `prefix n` asks folder and role and runs `ade work`; `prefix x` asks before closing a busy tab |
| 6 | Without tmux installed, `ade ui` exits 2 with the install command for the platform |
