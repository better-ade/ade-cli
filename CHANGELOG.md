# Changelog

## Unreleased
- A first run reads right (F1): `ade work <folder>` checks the hub's Claude Code command (`HUB_CLAUDE`, else
  `claude`) before it starts anything; when it is not found it says so in one line, names `ade setup` as the fix and
  exits 2 (no tab, no agent). `ade setup --check` checks the same command, so the two agree
  (`claude code: missing (<command>)`). `ade hub new` prints one `next:` line, its own (bin/init's hand-run line is
  not shown), and after the first save says in one line that `hub.conf` is not in it and how to commit it by hand
  (nothing commits it). Bare `ade` with no agents says `agents: none running` instead of an empty table header, and
  its next steps no longer offer `ade` itself. `ade help`'s `web` entry says the page asks for the code shown in the
  terminal, with `--tailnet` too.
- `ade web` reads right on a fresh hub (M3): a template's placeholder line in `STATE.md` is not shown as its state
  (`no state yet`; `no STATE.md yet` when there is none); main with no session reads `not running`; the quiet alert
  says how long since the last sign of life (`no check-in for 25m (since 13:45Z)`) and a quiet row's check-in is dim;
  every top-bar count, `sync`, `monitors`, `inbox` and a row's `!` explain themselves on hover; whole folder names in
  the events on a wide screen; a start message of short lines and one hint line on the code page (`?` shows the rest).
  `/api/agents`: `line` is null when there is no `STATE.md`; new `running`.

## 0.2.13
- `ade web` asks for a code before it shows anything (M2): each start prints a code of 8 characters on its own
  terminal only, and the page shows a terminal-line prompt until it is typed. A code opens one page (the next is shown once it is used). 5 wrong codes use it up until Enter is
  pressed in that terminal (a new code); a session lasts 12 hours or until the server stops, and `q` on the page locks
  it. `--tailnet` asks for it too. With no controlling terminal, `ade web` exits 2 and starts nothing. New: `POST /login`.
- `ade web` is a live dashboard of the agents (M1): a terminal UI in the browser, in `ade ui`'s colours (dark first,
  light from the same tokens), with tmux-like panes (status bar, agents, detail, events, keys), keyboard first
  (`j`/`k`, Enter, Tab, `/`, `e`, `?`, `q`/Esc), stacked on a phone, no animation under reduced motion, and one inline
  font (JetBrains Mono, SIL OFL 1.1): no request leaves the page. Each agent's state (busy, idle, ready, quiet,
  blocked), `STATE.md` line, last check-in and time in that state; alerts for a quiet agent, one likely waiting at a
  prompt or not started, an alerting monitor, and unread notes to main; the last sync and the inbox count. New:
  `/api/events?since=<cursor>` (only what is new), `ade web --stop`, `--no-open`; by default it opens your browser
  without putting the token on a command line (never over SSH). Requests naming another site (Origin) are refused; the API wants the link's token in a header
  as well as the cookie (a cookie is not kept to one port). GitLab tokens, Cookie headers and URL-encoded secrets are
  hidden too.

## 0.2.12
- CI tests every hub command against a real hub (C1): `tests/e2e/hub_commands.sh`, in `e2e-linux` and `e2e-macos`,
  makes a hub from the real template and runs `method`, `models`, `roles`, `context`, `sync`, `notify`, `chat`,
  `dispatch` and `agent-run` against it, offline. The suite job installs tmux and poppler on macOS and poppler-utils
  on Linux, so the real-tmux and real-pdftotext tests run instead of skipping.
- `ade keys` sets the missing keys for you (A26): the hub's list as before, then, at a terminal and when an AI tool
  key is missing (deepseek, glm, muse, gemini; the optional Anthropic key is never asked for: `ade keys set anthropic`), one question "Set the missing keys now? [y/N]"; yes asks
  for each at ade's hidden prompt (empty skips; a failed store says so, without the value, and moves on, exit 1)
  and shows the list again. `ade keys --missing` asks without the question; not at a terminal it exits 2. Piped,
  redirected or in an agent session: the list alone, byte for byte. `set`, `share`, `receive` and every other
  argument pass through unchanged. The value goes only to the hub's `bin/keys set <tool>` on stdin.

## 0.2.11
- `ade hub import <url|path> [--share|--handover|--clone] [--owner <name>] [--name <new>] [--dir <folder>]
  [--no-github]` (I3): bring in someone's hub. It is cloned into `~/hubs/<name>` (or `--dir`), checked to be a hub,
  then the hub's own `bin/setup` and `bin/adopt` run: `--share` joins it, `--handover` makes you its owner (`--from`: the previous owner's memory folder), `--clone`
  makes a new hub of your own with its own private GitHub repo (`--no-github`: none). No mode: asked at a terminal,
  refused otherwise (exit 2). A hub without `bin/adopt` (older than ade-brain I2) is refused, "update that hub first",
  and its clone removed. The hub becomes the default; `bin/adopt` lists what is left by hand. No secret is copied.
- `ade shot` on macOS no longer stalls on the login Keychain (A25): Chromium gets `--use-mock-keychain` and
  `--password-store=basic`, as Playwright does; the throwaway profile holds nothing the Keychain guards (CI runners and
  SSH sessions used to hang at Page.navigate).
- `ade shot` on Ubuntu 23.10+ (A24): AppArmor lets the user namespace be made but gives it no rights, so Chromium's
  sandbox failed and the shot said only "the browser closed before it answered". On Linux a Chromium that closes before
  it answers, with its sandbox on, is started once more with `--no-sandbox`. Its stderr goes to
  `~/.local/share/ade/chromium.log` (0600); when it still closes, the error names its last lines (keys hidden).

## 0.2.10
- The guide asks which tools you use (A23): a new optional step after your hub lists the services ade has a recipe
  for at the pinned ade-skills tag, then the coming ones, then any other; a ready pick runs `ade connect <service>`
  in the hub (you sign in yourself), a coming or other pick is noted by name in the hub's `.ade/tools.json`. Enter
  skips; `ade setup` again shows what is connected and offers the rest. Names only: nothing secret is read or kept.

## 0.2.9
- A raw Ubuntu 24.04 server or desktop (A22): the one-line install downloads with `wget` when there is no `curl`, and
  names a missing `curl`/`wget` or `python3` before any download (a missing `python3` used to read as "the
  release.json ... is not valid ()"); after a yes at the terminal it installs them with `sudo apt-get update && sudo
  apt-get install -y`. curl is a required tool. Every apt install runs `apt-get update` first. The guide asks for your
  git name and email before it makes the hub when git has none. The README lists what Ubuntu needs.
- `ade connect` (A16): the connectors ADE knows, from recipes read only at the pinned ade-skills tag and only when
  their sha256 matches that release's `release.json`; `ade connect <service>` at a person's terminal installs the
  guard and the service's plugin in project scope, records the name in `.ade/connectors.json` (names only) and prints
  the sign-in step the person does themselves; `status` and `disconnect`. ade never reads, stores or prints a token.
  Until ade pins an ade-skills release with recipes it says so (exit 2).
- Pins: ade-skills `v0.1.0` -> `v0.9.0` (the README's `ade skills add notes` works, and `ade connect` has recipes),
  ade-method `v2.1.0` -> `v2.2.0`; ade-agent-registry stays at `v1.1.0`, its latest release.

## 0.2.8
- `ade project add <path-or-git-url>... [--name N] [--no-init] [--yes]` (A21): load repos you already have into the hub.
  Each becomes a project folder made by the hub's own `bin/new`, with the Code row of its `ACCESS.md` filled from the
  repo (the remote in https form and never with credentials, the checkout, the default branch, the CI it can see), so
  the hub finds the checkout. A URL (or `owner/repo` on GitHub) is cloned into your code folder (`ADE_CODE_DIR`, else
  `~/Project`, else `~/code`), never into the hub. It offers `ade init` in each repo (never overwrites), adds the
  repo's `README.md` and `docs/` to the hub's memory, and offers to start the focus agents. A folder that is already
  in the hub is left as it is; a failure for one repo does not stop the others.
- `ade project add --scan <folder>`: the git repos directly under a folder, those already in the hub marked; pick with
  `1 3 4`, `1-3`, `all` or names.
- `ade project list`: each project folder's name, checkout, branch, focus agent and its `STATE.md` "Updated" line.
- `ade shot`: screenshots as proof (A20). `ade shot url <address>` saves a PNG of a page through the headless Chromium
  the hub already has (Playwright's; `ade` downloads nothing, and says how to get it when it is missing), with
  `--full-page` and `--width W`; only `http`, `https` and `file` addresses, a file only inside the project.
  `ade shot screen` captures the whole screen (macOS: `screencapture -x`; Linux and the ADE Computer: the X display)
  after a yes at the terminal; an agent can run it only with `--yes-screen` where its session asks you before that
  command. `ade shot agent <name>` saves a focus agent's tab in `ade ui` as a picture, keys and tokens hidden first.
  Shots go to `<project>/.ade/evidence/<date>/<time>-<name>.png` with a `.txt` beside it (0700 folders, 0600 files,
  never overwritten, ignored by git); `--name N` names one. A page or screen shot cannot be redacted. `--tg [caption]`
  sends the picture to you on Telegram through the hub's new `bin/chat send`, only while the bot is locked to you.
  `ade doctor` lists Chromium. A page never gets a file outside the project, a `.env`, key or `.git` file of it, or a
  link-local or metadata address. `ade reset`, `ade files` and the other commands that ask a person now also see an
  agent session by `CLAUDE_PID`, `CLAUDE_CODE_CHILD_SESSION` and `CLAUDE_CODE_EXECPATH`.

## 0.2.7
- Telegram: the guide's step is not "working" until the bot is locked to you, as the hub's own `bin/chat status` says
  it ("locked to you": the policy allowlist, your account in it, no groups), not by the policy's name alone. Once it
  is, the guide says what follows (before you lock, and again once it is so): the chat runs in auto mode, so your main agent acts on your Telegram messages
  without asking at the terminal; Claude Code's auto mode still refuses risky actions; `HUB_CHAT_MODE=manual` in
  `hub.conf` turns that off. Needs a hub whose `bin/chat` chooses the mode this way; an older hub is read as before.
- `ade`, `ade setup --check`: the line reads `telegram: on (auto)`, `telegram: on (manual: not locked)`, or
  `telegram: on (<mode>)` when `HUB_CHAT_MODE` is set.
- `ade setup --telegram` on a bot that is on but not locked shows the one line to type and checks it. A session that
  started before the lock is restarted so the new mode applies, only when your main agent is idle; a busy one is
  never interrupted, and you are told what to type (`ade chat stop && ade setup --telegram`).
- `ade web` ([A19](docs/stories/A19-web-view.md)): a read-only page of the hub in your browser: the agents and their
  state, the picked agent's log (its events and its `STATE.md`), today's and yesterday's journal and the chat log,
  refreshed every 3 seconds. It listens on 127.0.0.1 only, on port 8765 or a free one (`--port N`), and prints an
  address with a random token; without the token, 403. Ctrl-C stops it. Keys and tokens are hidden as in
  `ade chat logs`, plus GitHub tokens, `sk_` keys, AWS access key ids, `Authorization:` headers, the user and
  password of a URL, the value after a name ending in `password`, `secret`, `token` or `key`, and private key
  blocks; escape sequences are removed and a line over 4096 characters is cut. GET only: it changes nothing and runs nothing but the hub's `bin/sessions`.
- `ade web --tailnet`: the same page on this machine's Tailscale address only (never every interface), for your
  phone. Anyone on your tailnet with the link can read these logs; the link changes every start. `ade` never installs
  Tailscale or signs in to it: it says how when it is missing or signed out.
- `ade web --print-link`: the running page's address, else nothing and exit 1.

## 0.2.6
- bun already in `~/.bun/bin` but not on the PATH (bun's own installer, or an earlier ade): `ade setup` and
  `ade setup --tools` now add the one marked PATH line to the shell's start file, as after ade's own install, so a new
  terminal (and the hub's `bin/chat start`) finds it. Never from an agent session.

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
