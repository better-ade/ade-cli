# What `ade` expects from a hub (contract)

`ade` stays thin: the hub's `bin/` scripts do the work; `ade` finds the hub, exports `HUB` to it and returns the
script's exit code unchanged. A hub is a folder with `bin/lib.sh` and `hub.conf`.

## `~/.config/ade/` (folder 0700, files 0600, names and paths only, never secrets)
- `hub`: the default hub's path (A1).
- `hubs`: every hub `ade hub new` made or `ade hub use` chose, one path per line (A3).
- `orchestrators`: one `name<TAB>hub` line per orchestrator (A2). Names `[a-z0-9-]+`, unique; one per hub.
- `accounts`: `hub<TAB>recorded fingerprint<TAB>current fingerprint<TAB>continue` once the owner chose to continue
  with another Claude account (A10).
- `keys-set`: one `hub<TAB>tool` line per key `ade setup` stored (A9), names only; `ade reset --keys` offers only these.

## `hub.conf` keys `ade` reads
- `HUB_NAME`: the hub's display name (`ade` alone, `ade hub list`); default the folder name.
- `HUB_CHANNELS` (space-separated channel types, ADR 0006): shown by `ade orchestrator list`.

- `HUB_ROOT_MODEL` (the orchestrator's model), `HUB_CLAUDE` (the claude command, default `claude`),
  `HUB_CLAUDE_CONFIG_DIR` (exported as `CLAUDE_CONFIG_DIR`): `ade claude` (A4).

- `ade setup` writes two keys (A5), each one line, shell-quoted, replaced in place: `HUB_ROOT_PROVIDER` (the everything
  agent's provider: `anthropic`, `deepseek`, `glm` or `muse`) and `HUB_PROVIDERS_ALLOWED` (the top provider plus every
  focus provider whose live test passed). It reads `HUB_PROVIDERS_ALLOWED` for `ade setup --test`. A18b adds
  `HUB_PROVIDERS_UNTESTED` (below).

## `ade setup` and the hub (A5)
- Provider ids: `anthropic`, `gemini`, `deepseek`, `glm`, `muse`. GPT and Codex are never offered. Gemini is a focus
  provider only.
- `bin/keys set <tool>` reads the value on stdin (tools `anthropic`, `deepseek`, `glm`, `muse`, `gemini`, `telegram`);
  `bin/keys` (no arguments) prints `<tool> stored` lines for stored keys and never a value.
- `bin/agent --live-test <provider> --dir <throwaway folder>`: the task (one line) on stdin, run from that folder through
  the path a real focus agent uses; exit 0 with a line that is exactly `READY` (spaces and CR ignored) = ready; else the last output line,
  with key-shaped strings and Telegram bot tokens hidden, is the reason. It runs with provider key and backend
  variables (`ANTHROPIC_*`, `CLAUDE_CODE_OAUTH_TOKEN`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`, ...) unset.
  `ade` makes and removes the folder (never a checkout) and sets `AGENT_TIMEOUT=120`.
- `bin/chat test telegram` (`ade setup --test telegram`, and the guide's Telegram step, below). `ade setup` never
  runs `bin/chat setup telegram` (the hub's list of every step).
- Claude Code: `claude auth status` (exit 0 = signed in with an account) and `claude auth login`.

## `ade ui` and `ade dash` and the hub (A6)
- tmux: ade's own server (`tmux -L ade`, `ADE_TMUX_SOCKET`), session `ade-<HUB_NAME>`, config
  `~/.config/ade/ui-<session>.tmux.conf`, theme `~/.config/ade/theme` (`bg fg accent orchestrator busy idle blocked
  unread` = `#rrggbb` or a tmux colour word; anything else falls back to the default).
- `ade work` (tabs, never a window): unless `ADE_UI=off`, the caller chose a terminal (`AGENT_TERMINAL`; `tmux`
  counts only together with `ADE_UI_SESSION`, as tab 0 has them), the ADE app (`ADE_HOOK_BIN` executable with
  `ADE_HOOK_PORT`, `ADE_HOOK_TOKEN`, `ADE_PTY_ID`) or no tmux, `ade` makes the session when it is not there and runs
  `bin/work` with `AGENT_TERMINAL=tmux`, `ADE_UI_SESSION=<session>` and `TMUX=<socket path of ade's tmux server>`
  (so the hub's plain `tmux` reaches that server). The session name is `ade-<HUB_NAME>-<6 hex>`; the hub's tmux mode
  (V1) looks for `ade-<HUB_NAME>`, does not find it, and opens a detached session of its own, so `ade` moves every
  session that appeared during `bin/work` into its session as a window named `<folder>` (`rename-window`,
  `move-window -d`). **Needed from the hub:** bin/work's tmux mode should open its window in `$ADE_UI_SESSION` when
  that is set (then there is nothing to move). Tab 0 is `ade claude`, or `ade ui --place` (it waits for Enter, then
  runs `ade claude`) when a process with `--remote-control <HUB_NAME>` already runs (`pgrep -f`).
- `ade claude` with no arguments, at a terminal, outside an agent session and outside the session, is `ade ui`
  (tab 0 runs the orchestrator, the person is attached); the same exceptions as `ade work`.
- `ade` alone is `ade ui` at a terminal when the hub is set up (`claude` on PATH, `HUB_ROOT_PROVIDER` set, a folder
  under `projects/`), outside an agent session, the ADE app and ade's tmux server, unless `ADE_UI=off`; `ade home`
  is the summary (hub, `bin/sessions`, next commands).
- `ade ui --tab-name <folder> [ticket]` prints a tab's name: `<folder>` or `<folder>:<ticket>`.
- `bin/sessions` columns as today; a row's ticket is its NAME when that differs from the folder's last part; STATUS
  `busy`, `idle` or `blocked`.
- `bin/inbox --count <session name|main>` (C6): the number of unread events, `0` once read.
- `bin/dispatch --list` (C3 follow-up): `ready|waiting<TAB><ref><TAB><folder>` lines for every folder;
  `ade dispatch --approve <ref> <folder>` runs in a popup's own terminal.
- Events: the last 8 lines of `${AGENT_STATE:-~/.agent-hub/<HUB_NAME>}/events.jsonl` (C6: `time from to kind text`).
- Plan preview: `<hub>/<folder>/PLAN.md`, else `STATE.md`.

## `ade skills` (A7)
- The project's `.claude/settings.json` `skillOverrides`: absent = on, `"name-only"`, `"off"`. `enable` removes the
  entry, `disable` sets `"name-only"`; nothing else changes. ade-method `ade.json` `bmad.never` (at `ADE_METHOD_REF`)
  cannot be enabled.
- Plugins: ade-skills `.claude-plugin/marketplace.json` at `ADE_SKILLS_REF` (default `main`, as the marketplace Claude
  Code adds); installed = `enabledPlugins["<name>@ade-skills"]` in the project's settings.
- The folder of a project: the hub folder it sits in, or the folder whose `ACCESS.md` table lists it as a checkout
  (third column, absolute or `~/` path). The hint goes to `bin/notify <folder> <text>` (C6).

## The hub's `.claude/settings.json` (A4)
- `ade claude` adds, only when absent: `extraKnownMarketplaces["ade-skills"] = {"source": {"source": "github", "repo":
  "better-ade/ade-skills"}}` and `enabledPlugins["ade@ade-skills"] = true`. Every other key is kept; invalid JSON is
  refused (exit 1) and left as it is.

## `bin/chat` (ade-brain C5) as `ade orchestrator` calls it
- `bin/chat setup <channel>`: interactive; exit 2 for an unknown channel (`ade` shows the hub's message and exit). Called
  with `ADE_ORCHESTRATOR=<name>` in the environment.
- `bin/chat start` / `bin/chat stop`.
- `bin/chat status`: first line starts `running` or `stopped`; a running one carries `since <time>` (one word).
  Anything else shows as `unknown`.
- `bin/chat logs -n <N>`: the last N lines of the hub's chat log, printed as is (`ade` adds nothing).

## The hub template (A3)
- `ade hub new` creates the hub from `better-ade/ade-brain` (`gh repo create --template`, or `git clone` with
  `--no-github`) and then runs its `bin/init --persona P --client C --owner O --name <name>` at the hub root (missing answers are asked;
  `bin/init --list` names the personas); the hub counts as made only when `bin/init`
  exits 0 and `hub.conf` exists.

## `ade hub import` and the hub (I3; ade-brain I1, I2)
- The source must be a hub (`bin/lib.sh`, `hub.conf`) with an executable `bin/adopt` (ade-brain I2, its contract
  `.ade/context/adopt.md` there); without it ade refuses (exit 2, "update that hub first") and removes the clone.
- Order, in the fresh clone `<dir>/<name>` (`HUB` set, no input): `bin/setup`, then `bin/adopt --share`,
  `bin/adopt --handover --owner <name> [--from <x>]` or `bin/adopt --clone --owner <name> --name <name>`. ade prints their output as
  is (bin/adopt's "Left to do by hand:" list). Either one failing: the clone is removed, exit 1.
- Folder name: `--name`, else (share, handover) the source's last path part without `.git`; `^[a-z0-9][a-z0-9-]{0,63}$`.
- `--clone` (not `--no-github`): `gh repo create <name> --private --source . --remote origin --push` in the hub, after
  it is saved as the default; failures use the `repo-*` kinds. Share and handover keep the source's `origin`.

## Install (A3)
- `install.sh` piped from curl reads `main/VERSION` and downloads `ade` from the tag `v<VERSION>`; release tags are
  `vX.Y.Z` (the org release workflow).

## `ade clean`, `ade reset`, `ade uninstall` and the hub (A9)
- State: `${AGENT_STATE:-~/.agent-hub/<HUB_NAME>}`. Locks `sync.lock`, `dispatch.lock`, `chat/lock`: folders
  holding `pid` (and `start`); stale when the pid names no process, or no pid and over 2 minutes old. `ade clean`
  takes the hub's `<lock>.gc` guard (`mkdir`) around the stale check and the removal. `dispatch/<name>`
  start markers (only the last 120 s count). `events-seen/<id>` cursors (expire after 7 days).
- Projects: `projects/<name>/ACCESS.md`, a `| Repo | Checkout | Branch |` table; `clean` reads Checkout and Branch.
- `bin/journal <folder> <text>`: `ade` writes one line as folder `ade` (`ade clean: …`, `ade reset: …`).
- `bin/keys forget <tool>`: `ade reset --keys`, after a yes per key.
- Services: launchd `ai.agent-hub.<HUB_NAME>.<job>` in `${AGENT_LAUNCHAGENTS:-~/Library/LaunchAgents}`, systemd
  user units `~/.config/systemd/user/ai.agent-hub.<HUB_NAME>.<job>.service`; `reset` removes jobs `chat` and `monitor`.
- ade's trash on Linux: `~/.local/share/ade/trash/<folder>-<UTC yyyymmddThhmmssZ>/`; on macOS the Finder Trash.
  `~/.local/share/ade/moved-hubs`: `path<TAB>where<TAB>UTC time` per hub moved.
- `bin/schedule uninstall`: `reset --hub` runs it (all the hub's jobs) before the move. `bin/sessions`: a row (after
  the header) with `busy`, `idle` or `blocked` is a live agent; `reset --hub` refuses then.

## `.ade/connections.json` and `ade restore` (A10)
- The record (committed, JSON, `format` 1, names only): `account` {`label`, `fingerprint` = first 16 hex of
  sha256("ade-account-v1:<organizationUuid>:<accountUuid>") from `${HUB_CLAUDE_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-~}}/.claude.json`
  `oauthAccount`}, `top` {`provider`, `sign_in` account|key, `model`}, `focus` [{`provider`, `sign_in`}], `channels`
  [{`type`, `bot`}], `marketplaces` [{`name`, `repo`}], `plugins` [{`name`, `marketplace`, `ref`}], `specialists`
  [names], `pins` {`ade-method`, `ade-agent-registry`, `ade-skills`}, `services` [chat|monitor|sync]. Never a key,
  token, email, account id or machine path.
- Checked on every read, rejected whole on any failure (exit 1, the reason; nothing in it is used, the account gate
  fails closed): only the keys above; names `^[a-z0-9][a-z0-9._-]{0,63}$`; refs `^v[0-9]+\.[0-9]+\.[0-9]+$`; `repo`
  `https://github.com/<owner>/<repo>`, `<owner>/<repo>` or `local` (this machine's `ADE_SKILLS_REPO`; only for
  `ade-skills`); `ade-skills` bound to another repo is rejected; `label` `^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$`;
  `fingerprint` 16 hex; `bot` `@name` or empty; at most 64 entries per list and 64 KiB. Writers record a repo only
  when it is a public GitHub URL (else `local`) and refuse a write the check would reject.
- Project records: `.ade/connections.json` in the hub's `projects/*` and `ops/*` folders (and the git checkouts their
  `ACCESS.md` lists); `ade restore` installs their plugins in their own folder.
- Needed from the hub (ade-brain builder): `bin/chat info <channel>` prints `bot @<username>` (the public bot name, no
  token); `bin/chat setup telegram --repair` drops this device's old pairing and pairs again; `bin/schedule install`
  installs the hub's services for this platform (launchd or systemd). Tests fake all three.
- Installed plugins: Claude Code's `${HUB_CLAUDE_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-~/.claude}}/plugins/installed_plugins.json`
  (`plugins` keys `<name>@<marketplace>`, entries with `scope`, `projectPath`, `version`; a project-scoped entry counts
  only in its folder); marketplaces: a whole word of `claude plugin marketplace list`. A plugin is ready only when the
  installed `version` is the recorded ref without its `v`.

## `ade update` and the hub (A11)
- Releases: `$ADE_CLI_BASE/main/VERSION` and `$ADE_CLI_BASE/v<version>/ade` (default
  `https://raw.githubusercontent.com/better-ade/ade-cli`, as `install.sh`); the new file is stamped like `install.sh`.
- The `ade` file ends with the line `# ade: end of file (ade update checks this line; keep it last)`; `ade update`
  refuses a file without it. The previous installed file is kept beside it as `.ade.prev` (mode 644);
  `ade update --rollback` swaps the two.
- The hub: `git pull --ff-only` on its upstream (local changes to tracked files refuse; untracked files do not), then `bin/method sync`. A pull that changes `bin/chat`, `bin/chat.py`,
  `bin/brain` or `bin/brain.py` needs a running orchestrator restarted: only when `bin/sessions` shows the row `main`
  as `idle` (`bin/chat stop`, then `bin/chat start`, journaled); else `~/.config/ade/restart-pending` (one hub path
  per line) keeps it for the next `ade update`.
- `bin/notify all <text>`: one line per `ade update` that changed something.

## Release manifests and update checks (A12)
- `https://github.com/better-ade/<repo>/releases/latest/download/release.json` (and `.../download/v<X.Y.Z>/release.json`),
  written by better-ade/.github's `release.yml`: `component`, `version`, `released`, `notes_url`, `summary`, `urgency`
  (`normal`|`security`), `min_supported` (X.Y.Z or null), `files` [{`name`, `url`, `sha256`}].
- Trust (review round): from `MANIFEST_SINCE` = 0.2.0 (hard-coded in `ade` and `install.sh`) every ade-cli release
  has `.../download/v<X.Y.Z>/release.json`; without a valid one nothing is installed. It must say `component`
  `ade-cli` and `version` = the requested version and name a 64-hex `sha256` for `ade`; its `url` is ignored (the file
  is always `$ADE_CLI_BASE/v<X.Y.Z>/ade`, compared before stamping). A version lower than the installed one is refused
  (only `ade update --rollback`). Printed manifest text loses control characters.
- **Residual risk (stated, follow-up):** the sha256 and the file come from the same release pipeline (the repo and its
  Actions), so the check proves integrity (a cut-short, swapped or stale file), not authenticity: whoever can publish
  a release can publish a matching manifest. A signature or `gh attestation verify` is a later owner decision; not
  built now.
- ade-cli's `release.yml` passes `assets: ade` to the shared workflow; its manifest script refuses an empty file list
  when the caller named assets (`ASSETS`).
- `~/.config/ade/updates/`: `checked` (epoch of the day's fetch, one for all components), `fetching` (the detached
  job's lock, stale after a minute), `<component>.latest` (version, urgency, min_supported, summary; tabs, `-` for
  empty), `.seen` (the last version announced), `ade-cli.tried` (the last version auto-install acted on),
  `installing` and `auto.log` (a running or finished auto-install; the next command prints it whole, then removes it).
- `~/.config/ade/auto-update`: `on` or `off` (`ade update --auto on|off`); absent = on. `ADE_NO_AUTO_UPDATE=1` = off.
- Installed versions: ade-cli the stamped version; ade-brain the hub's `VERSION`; ade-method the project's
  `.ade/method-version`; ade-skills and ade-agent-registry their pins, when in use.
- Needed from the hub: `bin/chat send <text>` sends one line on the hub's channel (Telegram); faked in tests.

## `ade files`, `ade view`, the link picker and the tools ade installs (A15)
- Roots (no question): the hub's physical path, every checkout in `projects/*/ACCESS.md` and `ops/*/ACCESS.md`
  (`| Repo | Checkout | Branch |`, absolute or `~/`), and the git top level of the working folder (`ade view --cwd
  <folder>` sets it). Anything else, or a link under a root whose target is not, needs a yes typed at a terminal
  (refused in an agent session or without a terminal, exit 2). `/`, the home folder and any parent of it are never a
  root, whatever ACCESS.md says; a folder opened after a yes is listed, never previewed, and a yes to one of those wide
  folders allows nothing under it. Read-only: nothing is written outside ade's temp folders, with one exception:
  `~/.config/ade/hints` (below). Pagers run with `LESSSECURE=1` and an empty `LESSOPEN` (bat's pager is always
  `less -RF`, glow's `less -r`). The built-in browser is the explorer; yazi only with `ADE_FILES=yazi`, and yazi is neither read-only nor held to the hub and its projects (it deletes, renames, moves, runs commands and walks anywhere without asking).
- `ade view <path[:line[:col]]>`: a name that exists wins over a `:line` suffix; relative to the working folder.
- `ade files --act open|reveal|copy <absolute path>` and `--act url <http(s) URL>`: what `o`, `f`, `y` and a picked
  link run (macOS `open --`, `open -R --`, `pbcopy`; Linux `xdg-open <path>`, `xdg-open <folder>`, `wl-copy`, `xclip
  -selection clipboard` or `xsel --clipboard --input`); over SSH (`SSH_CONNECTION`, `SSH_CLIENT` or `SSH_TTY`) the
  path and `scp -s '<host>:<real path>' .` instead. `open` opens documents only: an allow list of extensions (pdf,
  images, text and Markdown, office files, audio, video), compared without case on the real path; refused: anything
  else, an executable, a folder, and anything inside a bundle (`.app`, `.prefPane`, `.kext`, ...). `copy` puts the
  path on the clipboard shell-quoted when it holds anything outside `[A-Za-z0-9_./@%+=:,-]`. `url` takes printable
  ASCII only. Messages show names with control, C1, bidi and zero-width characters (and non-UTF-8 bytes) as `?`.
- `ade ui`: `prefix e` = `display-popup -E -w 90% -h 90% "ade files"`; `prefix l` = `run-shell "ade ui --menu links
  #{pane_id}"`, which writes `pane` (`capture-pane -p -J -S -2000`) and `cwd` (`#{pane_current_path}`) into an
  `$TMPDIR/ade.*` folder and runs `ade ui --links <folder>` in a popup; that folder is removed after.
- `~/.config/ade/hints`: one tool name per line, each missing viewer tool's hint shown once (the one file A15 writes
  outside ade's temp folders).
- Visual Studio Code: `ade files --act code <absolute path> [line [col]]` (the key `c`), `ade view --code`, and
  `ADE_VIEWER=code` (text files, at a terminal) run `<code> --goto <path>:<line>:<col>` (line and column default 1;
  always both, so a name ending in `:5` stays the name) or `<code> <folder>`. `<code>` is `command -v code`, an
  absolute path outside the roots (by its real path too), found once per run. Over SSH it runs only with `DISPLAY`
  or `WAYLAND_DISPLAY` set or in Visual Studio Code's own terminal (`TERM_PROGRAM=vscode`). `ade view`'s `where`
  line ends with the column (`FT_COL`). The link picker takes `<number>c`.
- Tools: required `git python3 curl tmux gh gitleaks bun` (curl since A22; bun: its own section below); extras `yazi bat glow poppler chafa code` (code = Visual Studio Code:
  Homebrew `visual-studio-code`, not in apt, named with https://code.visualstudio.com/download, no repository added)
  (bat may be `batcat`; poppler =
  `pdftotext` and `pdftoppm`). Homebrew packages: `git python curl tmux gh gitleaks yazi bat glow poppler chafa`. apt (Ubuntu 24.04):
  `git python3 curl tmux gh gitleaks bat poppler-utils chafa`; yazi and glow are not in apt and are not downloaded (their release
  pages are named). Installs run only after one yes at a terminal: `brew install <pkgs>`, `[sudo] apt-get update && [sudo]
  apt-get install -y <pkgs>` (A22: the update always first; not root and no sudo: the root command is named, nothing runs); never in an agent session; never a script piped to a shell. V2's `ade server install` uses the apt list.

## `ade connect` and `.ade/connectors.json` (A16)
- Contract: ade-skills `.ade/context/connectors.md` (sections 1, 2, 3, 6) and decision 0001. This is what ade-cli built.
- Recipes are read only from the ade-skills checkout at `ADE_SKILLS_REF` (`ADE_SKILLS_REPO`), which must be a `vX.Y.Z`
  tag, at `plugins/guard/connectors/<service>.json`. `CONNECT_SINCE=0.7.0` (hard-coded, no override) is the first
  ade-skills release taken to ship recipes; a lower pin prints one line and exits 2. The release manifest is
  `$ADE_RELEASES_BASE/better-ade/ade-skills/releases/download/<ref>/release.json` (A12's `manifest_py`: component
  `ade-skills`, version = the pin); each recipe needs a 64-hex `sha256` there as `connector-<service>.json`, compared
  with the checked-out file before it is read. A recipe that is a link, not `<service>.json`, unnamed, mismatched or
  not format 1 is refused alone, in one line; the list then exits 2.
- Format 1 checks: the contract's section 1 "Checks" as of amendment 1 (2026-11-22), all in `recipes_py`: the file
  opened without following a link and `fstat`ed as regular, hashed on those bytes; every string refusing Unicode Cc Cf
  Cs Co Cn Zl Zp; unknown keys anywhere; the per-kind rules; `guard.commands` `free` entries `{"words","flags","args"}`
  and `deny` runs (shape only, in the one function `commands`); across files (prefixes that overlap, a shared
  `sign_in.connector` or `sign_in.plugin`, two `guard.commands.gh` or `.git`, a `ready` recipe without
  `plugins/guard/hooks/hooks.json` and `guard.sh`) refuses the whole folder (exit 2). Choices of ade-cli where the
  contract is silent: required `format service title job tier state sign_in reaches`, `guard` when ready;
  `sign_in.plugin` must equal the service for every kind (ade installs only `guard` and that plugin).
- Commands and exits: `ade connect` (anywhere; rows `service job tier state here`, then the tier key; 0, 2 pin or a
  recipe not verified, or the record invalid); `ade connect <service>` (terminal only, `tty_ready`; 0 connected, 1 a no
  or a failed sign-in or `gh` missing, 2 refused, 3 held or tier 4); `ade connect status [<service>]` (anywhere; lines
  `connector <service>: ready|missing|unknown (<detail>)`, a `held` recipe `missing (held: <held>)`, `outside` never (A17); 0 no gap, 1 a gap or not recorded, 2 record invalid or pin
  not verified); `ade connect disconnect <service>` (terminal only; `plugin`: `claude mcp logout plugin:<p>:<p>`;
  `cli` and `claude-ai` change nothing and print where to sign out; prints `pages.revoke`; the record is not changed;
  0, 1 failed, 2 refused). `ade connect test` and `--check` exit 2 (A17).
- Installed means Claude Code's `installed_plugins.json` entry for that folder (A10's `plugin_version`); installs go
  through `plugin_add` (the same path as `ade skills add`) and are recorded in `.ade/connections.json`.
- `gh`: only `gh auth status` (output discarded) to read; `gh auth login` on the terminal only after a typed yes (the
  contract's step 8). Never `gh auth token`; ade never reads or prints a token.
- The record: `<folder>/.ade/connectors.json` (`<folder>` the git top level, else the current folder), written as
  `{"format": 1, "connectors": [...]}` (sorted, unique, at most 64 names `^[a-z][a-z0-9-]{0,31}$`, at most 64 KiB);
  anything else, a duplicate key or a link rejects the whole file (exit 2). One journal line
  `ade connect: <service> connected in <folder name>` through the hub's `bin/journal` when a name is added.
- Fix round (review of PR #42):
  - **Terminal only stops accidents; an agent running as you can get round it.** `connect <service>` and
    `disconnect` refuse when any of ten Claude Code session variables is set (even empty: `CLAUDECODE
    CLAUDE_CODE_CHILD_SESSION CLAUDE_PID CLAUDE_CODE_SESSION_ID CLAUDE_CODE_BRIDGE_SESSION_ID CLAUDE_PROJECT_DIR
    CLAUDE_PLUGIN_ROOT CLAUDE_CODE_EXECPATH CLAUDE_CODE_SSE_PORT CLAUDE_CODE_ENTRYPOINT`, the A13 list, kept in
    `CONNECT_SESSION_VARS` until the shared one lands), and unless stdin is a terminal and `/dev/tty` opens; a
    pseudo-terminal with those variables unset passes.
  - The project folder is never `$HOME` or `/` (a dotfiles repository whose top level is `$HOME` included): `connect
    <service>`, `disconnect` and `ade skills add` exit 2 there.
  - The trust chain does not move silently: when `ADE_SKILLS_REPO` or `ADE_RELEASES_BASE` is not ade's default,
    every `ade connect` command prints `ade: connect uses <...>, not ade's defaults` on stderr first, and the connect
    question names those sources, so nothing is installed without a yes to them. `file://` URLs count only when
    `ADE_TEST_ALLOW_FILE_URLS=1` and the tests-only marker `ADE_TEST_SUITE=1` are both set (`tests/helpers.sh`
    sets the marker), and `ade` then says so on stderr. The manifest download is capped at 64 KiB (`curl
    --max-filesize`, and checked after); redirects are https only (`--proto-redir =https`).
  - The manifest: a key twice, a file named twice, a malformed `connector-` entry, or a recipe it names that the
    checkout lacks refuses the pin (exit 2, one line); a checkout without a connectors folder or with an empty one
    is refused.
  - `gh`: `gh auth status --hostname github.com --active` (read-only; without `--active` on a gh older than
    multi-account gh) and `gh auth login --hostname github.com` after a yes; `status` says when the sign-in comes
    from `GH_TOKEN` or `GITHUB_TOKEN` (never the value). `gh` and `claude` are resolved to absolute paths before ade
    enters the folder; a copy inside the project is refused (exit 2, one line).
  - A project-scope plugin entry with no `projectPath` counts as installed nowhere.
  - **Stated limit** (next to A12's): `claude plugin install <p>@ade-skills` installs from whatever marketplace Claude
    Code has under the name `ade-skills`; ade checks that name exactly (a whole word of `claude plugin marketplace
    list`), not where it points.

## The guided first run (A18)
- Step ids, in order (`GUIDE_STEPS` in `ade`): `claude-code`, `claude-sign-in`, `github`, `hub`, `tools` (optional,
  A23), `project`, `telegram` (optional). A step is done by its state alone: `claude` on PATH; `claude auth status`
  exit 0 or a key in the hub's `bin/keys`; `gh auth status --hostname github.com` exit 0; a hub with
  `HUB_ROOT_PROVIDER` set; the hub's `.ade/connectors.json` or `.ade/tools.json` naming something; a folder under
  `projects/`; `telegram` in `HUB_CHANNELS`. `telegram` is offered only in a run that did a required step; `tools` in
  every run once the hub is there (at a terminal), offering what is not connected or noted yet.
- `tools` (A23): the list is the recipes at the pinned ade-skills tag, checked as `ade connect` checks them: `ready`
  ones first, then `held` ones labelled coming, then `other` (one line of free text). A ready pick runs `ade connect
  <service>`'s own code in the hub. A coming or other pick is noted in the hub's `.ade/tools.json`:
  `{"format": 1, "tools": [...]}`, names only, sorted, unique, at most 64 names `^[a-z][a-z0-9-]{0,31}$`, at most
  64 KiB, read and written as `.ade/connectors.json` is (a duplicate key, a link or any other shape rejects the whole
  file and nothing is written). A typed name with `@ : / . = _`, or a part of 24 or more characters (16 or more with
  a digit), is refused as a possible address, key or token and never shown. Enter, the end of input or no terminal
  skips the step and writes nothing.
- Exit codes of `ade setup` (the guide) and of `ade` alone when it starts it: 0 = it ran to its end (the last line
  says "All set" or which step is left); 1 = it stopped at a step (end of input, a declined install, a sign-in that
  did not finish), with one line saying how to come back; 2 = refused (an agent session, no terminal for a sign-in,
  a bad `ADE_HUB`, usage).
- The ADE Computer marker: the file `/etc/ade-computer` (any content; `ADE_COMPUTER_MARKER` points elsewhere in
  tests). In one, the guide's first line says so, the GitHub step says the sign-in stays in the computer's home,
  `xdg-open` opens the GitHub address only after a yes and only when `DISPLAY` is set (else `GH_BROWSER=true`), and
  the one-time code is shown again in block letters.
- GitHub: `gh auth status --hostname github.com` (checks), `gh auth login --hostname github.com --git-protocol https
  --web` (signs in, on the person's terminal), `gh api user --jq .login` (the name shown, control characters removed).
  Never `gh auth token`, `--show-token` or `--with-token`.
- `ade hub new`: a clone whose `bin/init` has not finished holds `.git/ade-hub-new` (the hub name); `ade hub new
  <name>` with that folder picks up there, and the guide's hub step picks up the first one under `~/hubs`. `bin/init`
  gets every answer as a flag, with stdin closed. `--no-github` stays for tests and scripts; no message offers it.
- Every question ade asks goes through `ask_text` or `ask_choice` (A18); `CHOICE` is never inherited.
- `ade setup` with no flags (the guide) refuses inside an agent session (exit 2); `--check`, `--test`, `--top`,
  `--telegram` and `--tools` keep their own rules.

## When a guide step fails (A18b)
- One function, `failed <kind> <line> [details] [default] [note]`, and one table, `FAILS` (`kind|default|choice=words;...`),
  in `ade`: a plain line (ASCII, no control character, key-shaped text hidden, at most 80 columns), a `details:` line,
  the numbered choices, the answer in `CHOICE`. `stop` and the end of input exit 1, Ctrl-C exits 130, each with
  `ade: stopped...; to come back, run <command>`. A new step adds its row and calls `failed`.
- The hub's first version (`ade hub new`, after `bin/init` and after the hub is saved in `~/.config/ade`): the hub's
  `bin/sync --yes`, run with `HUB` set and no input, only when `gitleaks` is on PATH and the hub's `core.hooksPath`
  is `.githooks` (`bin/init` sets it); else two lines with the command for later and no commit. `bin/sync --yes`
  does not push a commit an earlier run made, so after it `ade` runs `git push -q` when `@{u}..HEAD` is not empty.
  Never `--force`. No `bin/sync` in the hub: nothing is done. Kind `first-save`.
- Kinds: `live-top-account`, `live-top-key`, `live-top-check` (GLM, Muse), `live-focus-account`, `live-focus-key`,
  `install` (Claude Code, `gh`), `sign-in` (Claude, Gemini), `gh-sign-in`, `repo-taken`, `repo-auth`, `repo-create`,
  `hub-init`, `session`, `key-store`, `bun` (try again, the manual steps, stop), and Telegram's `tg-token`, `tg-bun`
  (the same, and skip Telegram for now), `tg-step`, `tg-wait`.
- `~/.config/ade/last-failure` (0600): the output of the last `gh repo create` or `bin/init` that failed, control
  characters removed and key-shaped text hidden. Both run with no input and their output captured (shown when they
  work). Tools that own the terminal (sign-ins, installers, the session, `bin/chat setup`) keep their own lines.
- `hub.conf` `HUB_PROVIDERS_UNTESTED` (written by `ade setup`, read only by `ade`): the everything agent's provider
  when it was chosen without a passed live test ("go on without the test"), else empty or absent. While it is set,
  that provider is `HUB_ROOT_PROVIDER` but is left out of `HUB_PROVIDERS_ALLOWED`, so the rule that only a tested
  provider enters a role (A5) holds; a pass in `ade setup --test`, `ade setup --top` or the focus step empties it and
  adds the provider to `HUB_PROVIDERS_ALLOWED`. GLM and Muse, and every focus provider, are never offered it.
  Known limit: the hub reads an empty `HUB_PROVIDERS_ALLOWED` as `anthropic`, so an untested `anthropic` everything
  agent with no other provider is still usable by the hub's focus agents; `ade` cannot say otherwise in that list.
- The live test's failure line: the hub's `agent: live test of <p>:<m> failed: <why>; details: <file>`. `ade` shows the
  file when it exists, its folder when the hub hid the name, else `ade setup --test <p>`.

## The guide's Telegram step (`ade setup --telegram`, step 6 of `ade setup`)
- The `telegram:` line (`ade`, `ade setup --check`): `on (auto)`, `on (manual: not locked)` (a bot that passed its
  test and still has the policy `allowlist`, but is no longer locked: the hub runs it in manual mode), `on (<mode>)`
  (`HUB_CHAT_MODE`), `on (<running mode>: restart for <mode>, ade setup --telegram)`, or `on` (a hub that names no
  mode). After the last step `ade setup --telegram` offers the lock to a bot that is not locked, restarts a session
  whose mode is not the one a start would use (`bin/chat stop`, `bin/schedule install`, `bin/chat status`) only when
  `bin/sessions` shows `main` idle (else it prints what to type and does not say "working"). What auto mode means
  (three lines) is said before the chat switches to it: in the `allowlist` step, before the person locks, and before
  a restart that brings auto; when the run did something it is said again at the end, as what is now so.
- What is left is read from the state alone, in this order (`tg_left` in `ade`): `token` (`bin/keys` lists `telegram`
  as stored), `bun` (on PATH or `~/.bun/bin/bun`), `plugin` (`telegram@claude-plugins-official` in Claude Code's
  `installed_plugins.json`), `start`, `pair`, `allowlist` (from `bin/chat status`), `test` (`HUB_CHAT=telegram` in
  `hub.conf`, which `ade` writes once `bin/chat test telegram` exits 0), `service` (`bin/chat status` says running).
  Shown as `on` (nothing left), `not finished: <what to do>` or `off` (no token and no `HUB_CHAT=telegram`) by
  `ade` alone, `ade setup --check` (`telegram:` line) and the guide's list.
- `bin/chat status` as `ade` reads it: the first line holds `running` (`running, channel not connected` does not
  count as running) or `stopped`, at its start or after `<name>: `; a line `telegram: policy <name>, groups: <n>`
  (else not paired). **The lock and the mode are the hub's to say** (ade-brain `.ade/context/chat.md`, "Who may act
  unasked"): that line ends `, locked to you` or `, not locked`, and a line `mode: <auto|manual|acceptEdits|plan>
  (<why>)` names the mode a start would use: `(HUB_CHAT_MODE)` when hub.conf sets it, `(not locked: ...)` for manual
  by default, and it ends `; the running session is in <mode>: ...` when the running session started in another
  mode. `ade` never reads the channel's `access.json` itself. The telegram line is read whole and exactly: the
  lock is the line `telegram: policy allowlist, groups: 0, locked to you`, nothing more on it (a trailing space, a
  leftover escape sequence, other words or another group count is not a lock). Only a hub whose status has no
  `mode:` line at all (an older one) is read as before: the line `telegram: policy allowlist, groups: 0` is the
  lock, and no mode is shown. When the lines do not say locked and the mode line does not say manual for that
  reason, the `telegram:` line reads `on (lock unclear: ade chat status)`. `ade` cannot tell a paired owner from a pending pairing
  code in that line; the hub's test settles it.
- What `ade` runs: `bin/keys set telegram` (the token on stdin, the hub's own prompt and "stored" line not shown),
  bun's own install after a yes when bun is missing there all the same ("bun" below), `claude plugin install
  telegram@claude-plugins-official --scope user`, `bin/chat stop` (the test is refused while the session runs),
  `bin/chat test telegram`, `hub.conf` `HUB_CHAT=telegram`, `bin/schedule install`, then `bin/chat status` for up to
  `ADE_TG_WAIT` seconds (default 30). What only a person does, shown one at a time and checked with `bin/chat status`:
  `bin/chat start` in a second terminal window (the hub starts a first, unpaired session only at a terminal), and
  `/telegram:access pair <code>` and `/telegram:access policy allowlist` inside that Claude Code session.
- Tools: required `git python3 tmux gh gitleaks` (gitleaks: Homebrew `gitleaks`, apt `gitleaks` on Ubuntu 24.04). A
  failed install is said in one line from the installer's message (`install_why`): Homebrew's outdated Command Line
  Tools, a tap that is not trusted; `ade` never runs `brew trust`, a system upgrade or an installer from the network.
- install.sh (A22), piped: before any download it needs curl or wget (wget when there is no curl) and python3; a missing
  one is named in one line and, on apt at a terminal after a yes, installed with `[sudo] apt-get update && [sudo]
  apt-get install -y <them>`; otherwise nothing is installed. The guide asks for git's `user.name` and `user.email`
  before the hub step when git has neither in its config nor in both `GIT_AUTHOR_*` and `GIT_COMMITTER_*`, and sets
  them with `git config --global`.

## Writes into a checkout (0.2.1)
- Every file `ade` writes inside a project or hub folder (`.ade/connections.json`, `.ade/method-version`, the files
  `ade init` copies, the project's and the hub's `.claude/settings.json`, `hub.conf`) goes through `ade_write` in
  `ADE_PY_WRITE` (run by `write_py`): a `mkstemp` temp file in the same folder, fsync, `os.replace`; a target that is
  not a regular file, or a folder on the way (`.ade`, `.claude`, and for `ade init` every folder of the path) that is
  a link, is refused with one line and exit 1. Writers that read first hold `ade_hold`: `flock` on the folder itself
  (no lock file is left in the project) until they exit. `hub.conf` is checked without its folder, the hub root,
  which may be a link the owner made.
- Fetches of the pinned repositories run with `GIT_TERMINAL_PROMPT=0` and `-c credential.helper=`.

## bun (a required tool, installed without Homebrew)
- `ade` pins one bun version (`BUN_VERSION` in `ade`, the only place) and installs it itself, after a yes at a
  terminal, in the guide's tools step, `ade setup --tools`, `install.sh` and, when it is missing there all the same,
  the Telegram step. Never `brew install bun`, never apt, never a script piped to a shell.
- What it fetches, over https only (redirects too): `https://github.com/oven-sh/bun/releases/download/bun-v<version>/`
  `<asset>.zip` and `SHASUMS256.txt` from the same release. Assets: `bun-darwin-aarch64` (also an Intel shell under
  Rosetta), `bun-darwin-x64`, `bun-linux-x64`, `bun-linux-aarch64`; another OS or CPU is a failure, not a guess.
- The zip's sha256 must be the one `SHASUMS256.txt` names for it (a 64-hex line for exactly that file name); then the
  one member `<asset>/bun` is unpacked (python3 `zipfile`, no `unzip` needed), must print the pinned version for
  `--version`, and is renamed into `~/.bun/bin/bun` (0755). Anything short of that installs nothing.
- Found: a `bun` on PATH (Homebrew's or any other) or an executable `~/.bun/bin/bun` counts as installed and is left
  alone. `ade` prepends `~/.bun/bin` to its own PATH (so to every hub command it runs; the hub's `bin/chat` looks
  with `command -v bun`) when no bun is on PATH and `~/.bun/bin/bun` is there.
- The person's shell start file: after an install, when `~/.bun/bin` is not on PATH, one line
  `export PATH="$HOME/.bun/bin:$PATH"   # added by ade: bun` is appended to `~/.zshrc` (zsh), `~/.bashrc` (bash) or
  `~/.profile` (any other `$SHELL`), said first; never when that file already names `.bun/bin` or `BUN_INSTALL`.

## `ade web` (A19)
- **From the hub (read only):** `bin/sessions` with no argument (its nine columns `NAME FOLDER PID PARENT STARTED
  ROLE STATUS LAST ENGINE`, one row per line, split on blanks; a row that is not nine fields is left out);
  `<hub>/journal/<UTC date>.md`; `<hub>/<folder>/STATE.md` for a row's FOLDER when it is `projects/<name>` or
  `ops/<name>`; `<state>/logs/chat.log`; `<state>/events.jsonl` (fields `time from to kind text`, `.ade/context/events.md`
  in the hub). `<state>` is `${AGENT_STATE:-~/.agent-hub/<HUB_NAME>}`. Nothing else is opened and no other command runs.
- **Redaction:** `ade` carries a copy of the hub's `bin/agent.py` `ESCAPES` and `HIDE` (what `bin/lib.sh redact` and
  `bin/chat logs` apply) and runs it first, then its own additions. **Needed from the hub:** a change to those two
  must reach `ade`'s copy (`web_py`). `ade` cuts a line to 4096 characters before the rule runs: its
  `[A-Za-z0-9]{16,}\.[A-Za-z0-9_-]{8,}` is quadratic on one long run (250,000 characters: over a minute), and
  `bin/chat logs` and `redact` run it on the whole text.
- **HTTP (GET only, else 405):** `/?k=<token>` or `/` with the cookie: the page; `/api/agents`; `/api/log?agent=<name
  from the list>`; `/api/journal`; `/api/chat`. JSON, every string hidden. 403 without the cookie `ade_web_<port>` or
  with a Host header other than the served address; 404 for anything else.
- **`~/.config/ade/web`** (0600): line 1 the server's pid, line 2 the address with its token; there only while a
  server runs. `ade web --print-link` prints line 2 and exits 0, else prints nothing and exits 1: what the hub's
  Telegram `/status` may call. One `ade web` per user at a time.
- **Environment:** `ADE_WEB_PORT` (the default port, 8765). Tests only: `ADE_WEB_TEST_TAILNET_LOOPBACK=1` (a loopback
  address may stand in for the Tailscale one).
- **Tailscale (`--tailnet`):** `tailscale status --json` (`BackendState` must be `Running`; `Self.DNSName`) and
  `tailscale ip -4` (one address in 100.64.0.0/10). Only asked, never installed, started or signed in.

## `ade project` and the hub (A21)
- **`bin/new projects/<name>`** makes the folder (`ade` never reimplements it; run from the hub root with `HUB` set,
  no input). Names: `[a-z0-9][a-z0-9-]{0,63}`. A folder that exists is never passed to it.
- **`ACCESS.md` Code row** (`| Repo | Checkout | Default branch | Who merges | CI |`): `ade` adds one row at the end of
  the table under `## Code` (a file with no such table gets one at its end), in the form the hub's `repos_of` reads: a
  table row whose 2nd cell starts with `/` or `~`. Repo: the remote in https form, no credentials, no `.git`, or
  `(no remote)`. Checkout: `~/...` under the home folder, else absolute. Who merges: `(owner)`. CI: `GitHub Actions
  (<workflow files>)`, `GitLab CI`, `CircleCI`, joined by `; `, or `none found`. No cell holds a `|` or a control
  character; the row is read back before the project counts as added.
- **Remote:** the whole userinfo (everything up to the last `@`), any query and any fragment are dropped, the scheme
  is read in any case; a remote that still looks like it holds one is written as `(remote hidden: it held a
  credential)` and never printed. A URL is cloned without them too (ssh keeps its user name only).
- **`hub.conf` `HUB_BRAIN_PATHS`** (space-separated, read by `bin/brain`): `ade project add` appends each added repo's
  `README.md` and `docs` (as `~/...` when under the home folder), once each, then runs `bin/brain index`. A path with a
  space or a character outside `A-Za-z0-9._/~-` is not added (one line says so). A hub without `bin/brain` is skipped.
- **`bin/sessions`**: `ade project list` reads its FOLDER (2nd) and STATUS (7th) columns.
- **`bin/work projects/<name>`**: the start offer runs `ade work projects/<name>` for each added project.
- **Environment:** `ADE_CODE_DIR` (where a URL is cloned; default `~/Project` when it is there, else `~/code`; never
  the hub or a folder in it).

## `ade shot` (A20)
- **Evidence:** `<project>/.ade/evidence/<UTC date>/<HHMMSS>-<name>.png` and `.txt` (the git top level of the working
  folder, else the hub); folders 0700, files 0600, `.ade/evidence/.gitignore` holds `*`. Sidecar lines: `what:`,
  `when:`, `command:`, `address:` or `agent:`, notes, `size:`, `redaction:`.
- **Chromium:** Playwright's, as the hub's `browser_chromium` finds it (`PLAYWRIGHT_BROWSERS_PATH`, else
  `~/.cache/ms-playwright`; ade also looks in `~/Library/Caches/ms-playwright` and `/opt/ms-playwright`).
- **`--tg`:** `bin/chat status` must print `telegram: policy allowlist, groups: 0, locked to you`; then
  `bin/chat send <png>` with the caption (one line, at most 200 characters) on stdin. Exit 0 sent, 2 refused, else not
  sent; a hub whose `bin/chat` answers `usage:` has no `send` yet.
- **`ade shot screen` from an agent session** (any of `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_SESSION_ID`,
  `CLAUDE_PID`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_EXECPATH`): needs `--yes-screen` and a `permissions.ask` rule
  matching the command line (`ade shot screen --yes-screen ...`) in the project's `.claude/settings.json` or
  `settings.local.json` (`CLAUDE_PROJECT_DIR`, else the git or hub root) or the user's settings; refused when any of
  those, or the managed settings, set `bypassPermissions` or cannot be read. The hub ships `Bash(*ade shot screen*)`.
- **Tabs:** `ade shot agent <name>` reads `tmux -L ade list-windows` of the hub's session and matches the tab's name
  (`<folder>:<agent>`), its folder, the folder's last part or the agent's name.
