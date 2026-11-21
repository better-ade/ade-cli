# Changelog

## Unreleased
- Update notifications and auto-update (A12): once a day per component in use (ade-cli, ade-brain, ade-method,
  ade-skills, ade-agent-registry) ade reads its `release.json` (2 s at most; offline = tomorrow); a banner once per new
  version (security: every command), a badge in `ade ui`'s tab bar, one Telegram line through the hub's `bin/chat send`.
  ade-cli patch and minor releases install themselves (security at once); majors and `min_supported` jumps ask first;
  `ADE_NO_AUTO_UPDATE=1` only notifies, `ADE_NO_UPDATE_CHECK=1` makes no request. `ade update` and `install.sh` refuse
  a file whose sha256 does not match `release.json`.
- `ade update [--check]` (A11): replaces ade by one rename after the new file passes `ade version` (a running ade keeps
  its code; `ade dash` re-execs on a new version), pulls the hub with `--ff-only` (local changes or a merge refuse),
  runs `bin/method sync`, `claude plugin update` for ade-skills plugins and `claude update`, reloads `ade ui` with
  `tmux source-file`, restarts an orchestrator on new chat code only when it is idle (else later), and sends one
  `bin/notify all` line. Nothing is killed. `--check` changes nothing.
- `.ade/connections.json` and `ade restore [--check] [--label <name>]` (A10): `ade setup`, `skills add`, `agent add`,
  `init`, `orchestrator new --channel` and `chat setup` record what the work depends on, by name only (the Claude
  account as a label and a one-way fingerprint). `ade restore` walks each gap with a yes; `--check` prints one line per
  connection. Another Claude account stops `work`, `dispatch`, `agent-run`, `claude` and `orchestrator start` until
  the question is answered (remembered per machine in `~/.config/ade/accounts`).
- `ade clean [--yes]`, `ade reset [--keys] [--hub <path>]`, `ade uninstall` (A9): each lists what it would do first.
  clean removes stale locks, old dispatch markers and event cursors, ade's old temp folders, dead `ade-*` tmux sessions
  and clean merged worktrees; reset stops orchestrators, removes the chat and monitor services, the `ade@ade-skills`
  entry and `~/.config/ade/`, keeps hubs, projects, keys and Claude Code; `--hub` moves the hub to the Trash (never
  deletes it) after its name is typed, refusing uncommitted, stashed or unpushed work; uninstall removes the installed
  binary last. `ade setup` notes which keys it stored (names only, `~/.config/ade/keys-set`).
- Testing (A8): CI on macOS Bash 3.2 and Ubuntu bash 5, pinned shellcheck, a hostile-input table over every
  name-taking command, clean-machine, upgrade and interactive e2e jobs, `ade ui` snapshots at two sizes, and a kcov
  coverage floor. Fixes it found: names starting with `-`, names with newlines, `projects/..`, `setup --test ""`,
  a 64-character cap on hub and orchestrator names, the sidebar layout below 70 columns.
- `ade skills list|add|enable|disable|search` (A7): BMAD skills via `skillOverrides` (absent = on; disable = name-only;
  ade-method's never list cannot be enabled), ade-skills plugins from the marketplace file; after a change the folder's
  running sessions get the reload hint through the hub's `bin/notify`; unknown names exit 2 with the closest ones.
- `ade ui [--detach]` and `ade dash [--once]` (A6): tmux session `ade-<hub>` on ade's own tmux server, tab 0 the
  orchestrator, a themed tab bar (● ⟳ ○ ⚠, folder, role, ticket, unread ✉), the fleet sidebar (prefix f) and popups
  (n new agent, a approve, t tickets, p plan preview, ? help); `ade work` opens a tab while it runs.
- `ade setup [--check | --test [provider|telegram] | --top | --telegram]` (A5): installs Claude Code (asks first), makes
  a hub when there is none, picks one everything agent and any focus providers (each signed in and live-tested; only
  ready ones enter `HUB_PROVIDERS_ALLOWED`), offers Telegram, then a guided `ade claude` session. Keys and the bot
  token go only to the hub's `bin/keys set <tool>` on stdin.
- `ade claude [<folder>] [-- args]` (A4): Claude Code at the hub root with the hub's `HUB_ROOT_MODEL` and Remote
  Control named after the hub, the `ade@ade-skills` plugin enabled in the hub's settings; `--dangerously-skip-permissions`
  is refused.
- `ade hub new <name> [--private|--public] [--dir] [--no-github]`, `ade hub list|use`, and `ade` alone saying what
  to do next (A3); `install.sh` piped from curl installs the release tag main's `VERSION` names.
- `ade orchestrator new|start|stop|list|logs|remove` (A2): named orchestrators, one per hub, in
  `~/.config/ade/orchestrators` (0600); the hub's `bin/chat` does the work (`.ade/context/hub-interface.md`).

## 0.1.0
- `ade`: hub commands (work, status, dispatch, notify, chat, method, keys, models, roles, doctor, sync, context,
  agent-run) run the hub's own `bin/` scripts; the hub is found by `$ADE_HUB`, walking up, or `~/.config/ade/hub`.
- `ade init`, `ade agent list|add`, `ade skills add`: project setup from ade-method and ade-agent-registry at pinned tags.
- `ade open` (inside the ADE app), `ade version`, `ade help`; `install.sh`; tests in `tests/` (`bash tests/run.sh`).
