# Changelog

## 0.2.5
- bun is installed as part of set-up. It is a required tool now: the guide's tools step, `ade setup --tools` and
  `install.sh` install it after a yes, before any Telegram step, and `ade doctor` lists it. It needs neither Homebrew
  nor the Xcode Command Line Tools (on a Mac with outdated Command Line Tools and an untrusted tap, `brew install`
  could not install it): `ade` downloads the pinned release, bun 1.4.4, for your OS and CPU from bun's GitHub
  releases (`bun-darwin-aarch64.zip`, `bun-darwin-x64.zip`, `bun-linux-x64.zip`, `bun-linux-aarch64.zip`), checks the
  zip's sha256 against the `SHASUMS256.txt` of the same release, and puts the one program in it at `~/.bun/bin/bun`.
  A sha256 that does not match installs nothing, and no script is piped to a shell. A bun you already have
  (Homebrew's, or one in `~/.bun/bin`) is left alone; `ade` never runs `brew install bun`.
- PATH: when `~/.bun/bin` is not on your PATH, `ade` says so and adds one marked line to `~/.zshrc` (zsh),
  `~/.bashrc` (bash) or `~/.profile`, once; `ade` and the hub commands it runs (`ade chat start`) find bun there in
  the same session.
- A bun install that fails (the download, the sha256, unpacking, a CPU bun has no build for) is one plain line, then
  the usual question: try again, show the manual steps, stop. The Telegram step still checks for bun; when it is
  missing there all the same, it offers the same install (and "skip Telegram for now").

## 0.2.4
- The guide's Telegram step finishes, one step at a time. The token is asked once (the hub's own prompt no longer
  shows as a second one). Then `ade` does each step it can, said before and checked after: bun (after a yes, as
  `ade setup --tools` installs), the Telegram plugin (`claude plugin install ... --scope user`), the hub's test
  message (`bin/chat test`), `HUB_CHAT=telegram` and `bin/schedule install`. The three steps only you can do
  (start the session in a second terminal window, `/telegram:access pair <code>`, `/telegram:access policy
  allowlist`) are shown alone, with the exact text to type, waited for and checked with the hub's `bin/chat status`.
  It ends in one of two lines: "Telegram is working" (the bot passed its test and its session runs), or "Telegram
  is not finished" with the one thing left; `ade setup --telegram` resumes there and shows nothing already done.
  `ade`, `ade setup --check` and the guide's list show Telegram as `on`, `not finished` or `off`. The hub's list of
  seven manual steps (`bin/chat setup telegram`) is no longer printed by `ade setup`.
- `gitleaks` is a required tool: `ade setup --tools`, the guide's tools step and `install.sh` install it with the
  others (Homebrew or apt), so the hub's first save is no longer skipped on a new machine. A failed install is said
  in one plain line taken from the installer's message (Homebrew's outdated Command Line Tools; a tap that is not
  trusted yet); `ade` never runs `brew trust`, a system update or an installer from the network itself.
- Focus work opens a tab, never a new window. `ade work <folder>` opens the agent as a tab of the hub's `ade ui`
  session; when that session is not there, `ade` makes it (detached, tab 0 the orchestrator's place) and says in one
  line where the tab is (`ade ui` shows it). When your main agent already runs outside tmux, tab 0 only keeps its
  place and no second one is started. `ade claude` with no arguments, at a terminal, now runs the main agent as tab
  0 of that session and attaches you to it. `ADE_UI=off` keeps the old way (`ade claude -- <args>` and `ade claude
  <folder>` mean what they did); without tmux everything is as before, with one line saying tabs need tmux (`ade
  setup --tools`); inside the ADE app nothing changes.
- The tab view is the default: `ade` alone, at a terminal with tmux and a hub that is set up, opens it (as `ade ui`:
  the main agent as tab 0, or the session that is there). A hub with a step of the guide left shows the steps and
  the offer. Without a terminal or tmux, in an agent session, with `ADE_UI=off` or typed inside the tab view, `ade`
  prints the summary as before (inside the tab view with the key hint; without tmux with one line on how to get
  it). `ade home` prints that summary anywhere; `ade status` is unchanged (the hub's sessions). The guide ends with
  "type ade to open your workspace".

## 0.2.3
- The guide, when a step fails (A18b): one plain line of at most 80 columns says what went wrong (never another
  tool's raw text), a `details:` line says where the rest is, and a numbered question offers what fits, with a
  default; `stop`, the end of input and Ctrl-C leave with the line on how to come back. A live test that fails says a
  usage limit and when it resets, or that Claude Code is not signed in, or the engine's reason, and offers: sign in
  with a different Claude account (Claude Code's own sign-in; ade reads no token) or enter the key again, try again,
  use another AI service, go on without the test. An everything agent chosen without its test is recorded as that
  (`HUB_PROVIDERS_UNTESTED` in `hub.conf`), is in no focus role, shows as "not tested" in `ade setup --check` and the
  guide's list, and `ade setup --test` settles it; focus agents, GLM and Muse still need a passed test. The same
  question follows a failed Claude Code install, Claude or Gemini sign-in, `gh` install, GitHub sign-in,
  `gh repo create` (a taken name asks for another; a half-made clone is removed), the hub's `bin/init`, an early end
  of the guided session, the Telegram set-up and a key that `bin/keys` did not store. `gh repo create` and `bin/init`
  no longer print their errors on the screen: they are kept in `~/.config/ade/last-failure`.
- `ade hub new` (and the guide's hub step) saves the hub's first version: once `bin/init` has rendered the hub, its
  own `bin/sync --yes` commits it (your git identity, the hub's secret scan) and pushes it, so the repository on
  GitHub shows the hub's README and not the template's. Never without the secret scan (no gitleaks: one line with
  the command for later), never a forced push; with `--no-github` it is a commit and no push. A failure asks: try
  again, go on (the command is shown), stop.
- Visual Studio Code for code viewing: `c` in `ade files`, in the viewer's own screens and in the link picker (a
  number then `c`) opens the file at its line and column (`code --goto <path>:<line>:<col>`, the path one argument,
  never a shell string) and a folder as a folder; `ade view --code <path[:line[:col]]>` does it from the command
  line; `ADE_VIEWER=code` makes `ade view` open code and text files there by default at a terminal, while images,
  PDFs and Markdown keep the built-in viewer. A path outside the hub and its projects asks first, as `o` does. No
  `code` command: one line and the built-in viewer, never an error; a `code` inside the hub or project being viewed
  is never run; over SSH with no display the path is offered. `ade setup --tools` installs it with the other extras
  (Homebrew cask `visual-studio-code`; on Linux it names Microsoft's page and adds no repository) and `ade doctor`
  lists it.

## 0.2.2
- The guided first run (A18): `ade` with no hub lists the steps with their state and, at a terminal, asks
  `Set up now? [Y/n]`; `ade setup` is the guide, one step at a time (Claude Code, sign in to Claude, sign in to
  GitHub, your hub, your first project, Telegram), each said before it runs and checked after, resuming where you
  are. GitHub is required: `gh` is installed after a yes and signed in with GitHub's own browser flow on your
  terminal (`gh auth login --web`); ade never sees a token. Every question numbers its choices and accepts the
  number, the name in any case or spelling, or a prefix only one has, and asks again otherwise. `ade hub new` asks the
  persona, client and owner the same way, passes them to `bin/init` as flags, and picks up a hub whose set-up
  stopped. In an ADE Computer (`/etc/ade-computer`) the GitHub address can open in its browser and the one-time code
  is shown large. The update notice is one line of at most 80 columns.

## 0.2.1
- Security: ade could write outside a repository through a symbolic link committed in it. Who is affected: anyone who
  ran `ade` in a repository they did not write themselves (a clone of someone else's project, a customer's repository).
  The record and settings writes (`.ade/connections.json`, the project's and the hub's `.claude/settings.json`,
  `hub.conf`) wrote a fixed-name temp file (`<file>.ade-tmp`) and renamed it; a repository that committed that temp
  name as a link, for example `.ade/connections.json.ade-tmp -> ../../../.zshrc`, had the person's `~/.zshrc` replaced
  with JSON by a command that records a connection (`ade skills add`, `ade init`, `ade agent add`, `ade setup`,
  `ade restore --label`), and the record itself became that link. `ade init` also wrote through a committed link
  (dangling or not) or a linked `.ade` folder. Now every such write makes its temp file with O_EXCL in the same folder,
  fsyncs and renames it, refuses (one line, nothing written) a target that is a link or not a regular file and a
  `.ade` or `.claude` folder that is a link, and holds a lock on the folder around read, check and write, so two runs
  at once no longer lose an entry. The fetch of the pinned repositories never prompts for a password nor reaches a git
  credential helper. Check a repository you ran ade in for committed links under `.ade/` and `.claude/` if in doubt.

## 0.2.0
- `ade files [<folder>]`, `ade view <path[:line[:col]]>` and `ade ui` keys `prefix e` (files) and `prefix l` (the file
  paths and URLs in this pane, opened in `ade view` at their line or in the browser) (A15): a read-only explorer with
  name search and preview (yazi only with `ADE_FILES=yazi`, and then neither read-only nor held to the hub), code with
  bat or `less -N` (pagers in `LESSSECURE` mode), Markdown with glow,
  images and PDF pages inline on graphics terminals (else size or text; `n`, `p`, `g`, `/`), `o` open, `f` reveal,
  `y` copy the path, shell-quoted when it must be (over SSH the path and an `scp -s` line). `o` opens documents only
  (an allow list, on the real path). Paths outside the hub and its checkouts, and escaping links, ask first at a
  terminal, and are listed, never previewed; no control, bidi or zero-width character is drawn. `ade setup --tools [required|extras]`, `ade setup`'s
  first steps and `install.sh` install missing tools with Homebrew or apt after one yes at a terminal; `ade doctor`
  lists every tool.
- Update notifications and auto-update (A12): once a day per component in use (ade-cli, ade-brain, ade-method,
  ade-skills, ade-agent-registry) ade reads its `release.json` (2 s at most; offline = tomorrow); a banner once per new
  version (security: every command), a badge in `ade ui`'s tab bar, one Telegram line through the hub's `bin/chat send`.
  ade-cli patch and minor releases install themselves (security at once); majors and `min_supported` jumps ask first;
  `ADE_NO_AUTO_UPDATE=1` only notifies, `ADE_NO_UPDATE_CHECK=1` makes no request. `ade update` and `install.sh` refuse
  a file whose sha256 does not match `release.json`. From 0.2.0 on a missing or invalid manifest installs nothing (the manifest must
  be ade-cli's, for that version; its url is ignored; never a downgrade). The day's check runs in a detached job
  (2 s for all components; no command waits); the auto-install runs detached, only from a terminal and never in an
  agent session; `ade update --auto on|off` switches it.
- `ade update [--check | --rollback]` (A11; the previous ade is kept as `.ade.prev`, untracked hub files never
  block): replaces ade by one rename after the new file passes `ade version` (a running ade keeps
  its code; `ade dash` re-execs on a new version), pulls the hub with `--ff-only` (local changes or a merge refuse),
  runs `bin/method sync`, `claude plugin update` for ade-skills plugins and `claude update`, reloads `ade ui` with
  `tmux source-file`, restarts an orchestrator on new chat code only when it is idle (else later), and sends one
  `bin/notify all` line. Nothing is killed. `--check` changes nothing.
- `.ade/connections.json` and `ade restore [--check] [--label <name>]` (A10): `ade setup`, `skills add`, `agent add`,
  `init`, `orchestrator new --channel` and `chat setup` record what the work depends on, by name only (the Claude
  account as a label and a one-way fingerprint). `ade restore` walks each gap with a yes; `--check` prints one line per
  connection. Another Claude account stops `work`, `dispatch`, `agent-run`, `claude` and `orchestrator start` until
  the question is answered (remembered per machine in `~/.config/ade/accounts`). The record is checked value by value
  and rejected whole when anything in it is off; answers come from a person at the terminal, never a pipe or an agent;
  plugins are verified at their recorded version, for the hub and its projects.
- `ade init` installs ade-method's `install_templates` (`.github/pull_request_template.md`, `.ade/commit-template.txt`,
  never overwriting) and sets `git config commit.template .ade/commit-template.txt` in that repo unless one is set;
  the default `ADE_METHOD_REF` is now `v2.1.0`; the temp checkout is removed again (the exit trap no longer fails).
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
