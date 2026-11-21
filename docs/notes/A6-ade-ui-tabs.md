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
- Faked in tests and needed from ade-brain: bin/work's tmux mode (V1), `bin/inbox --count` (C6), `bin/dispatch --list`.
