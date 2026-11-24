# A6 design note: `ade ui` and `ade dash`

- ade runs its own tmux server (`tmux -L ade`): its key table, status bar and theme never change the user's tmux.
- `ade ui` creates `ade-<hub>` once (tab 0 = `ade claude` with `AGENT_TERMINAL=tmux`), loads a generated config, and
  attaches; when the session exists it only attaches. `--detach` creates without attaching (scripts, tests).
- The tab bar is one `#(ade ui --bar <session>)` in `status-left` (refresh 2 s): ade lists the windows, reads
  `bin/sessions` and `bin/inbox --count`, and renders each tab with the theme's colours; the default window list is
  hidden. Rendering (bar and dash) is one embedded python3 block; no other runtime.
- Menus are `display-menu` built when the key is pressed (folders from `projects/` and `ops/`, roles from `bin/roles`,
  waiting tickets from `bin/dispatch --list`); approve runs `ade dispatch --approve <ref> <folder>` with
  `display-popup -E`, a real terminal where the owner types the ref back. Refs and folders are checked before they go
  into a tmux command.
- `ade dash` redraws every 2 s; `--once` prints once (colour only on a terminal without `NO_COLOR`); `ADE_NOW` fixes the
  clock for the golden file. Tokens show `-` until the hub reports them.
- Tabs, never a window (owner, 2026-11-23: "the cli is creating a new terminal instead of just creating a new tab"):
  the main agent was started with `ade claude`, so there was no ade ui session, `ade work` changed nothing and the
  hub's `bin/work` opened a Terminal window. Now `ade work` makes the session when it is missing and `ade claude`
  (no arguments, at a terminal) runs inside it. A main agent that already runs outside tmux is not started twice:
  tab 0 then holds `ade ui --place`, which says so and starts it on Enter. Found on the way: the hub's tmux mode
  never used ade's session (it looks for `ade-<hub>` on the default tmux server; ade's is `ade-<hub>-<hash>` on its
  own server), so `ade` passes `TMUX` (its server's socket) and takes the session the hub opens into its own as a
  tab; checked with a real tmux on a private socket (`work_real_tmux`). `ADE_UI=off` is the way out; the tests set
  it by default (`fresh`), so no test reaches a real tmux server.
- Faked in tests and needed from ade-brain: bin/work's tmux mode (V1), `bin/inbox --count` (C6), `bin/dispatch --list`.
