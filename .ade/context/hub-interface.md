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
  focus provider whose live test passed). It reads `HUB_PROVIDERS_ALLOWED` for `ade setup --test`.

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
- `bin/chat setup telegram` (after the token is stored) and `bin/chat test telegram` (`ade setup --test telegram`).
- Claude Code: `claude auth status` (exit 0 = signed in with an account) and `claude auth login`.

## `ade ui` and `ade dash` and the hub (A6)
- tmux: ade's own server (`tmux -L ade`, `ADE_TMUX_SOCKET`), session `ade-<HUB_NAME>`, config
  `~/.config/ade/ui-<session>.tmux.conf`, theme `~/.config/ade/theme` (`bg fg accent orchestrator busy idle blocked
  unread` = `#rrggbb` or a tmux colour word; anything else falls back to the default).
- `ade work` while the session runs exports `AGENT_TERMINAL=tmux` and `ADE_UI_SESSION=<session>` (unless the caller set
  `AGENT_TERMINAL`); bin/work's tmux mode (V1) then opens a window in that session named `<folder>` or
  `<folder>:<ticket>` (`ade ui --tab-name <folder> [ticket]` prints the name).
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
- Tools: required `git python3 tmux gh`; extras `yazi bat glow poppler chafa` (bat may be `batcat`; poppler =
  `pdftotext` and `pdftoppm`). Homebrew packages: `git python tmux gh yazi bat glow poppler chafa`. apt (Ubuntu 24.04):
  `git python3 tmux gh bat poppler-utils chafa`; yazi and glow are not in apt and are not downloaded (their release
  pages are named). Installs run only after one yes at a terminal: `brew install <pkgs>`, `[sudo] apt-get install -y
  <pkgs>`; never in an agent session; never a script piped to a shell. V2's `ade server install` uses the apt list.

## Writes into a checkout (0.2.1)
- Every file `ade` writes inside a project or hub folder (`.ade/connections.json`, `.ade/method-version`, the files
  `ade init` copies, the project's and the hub's `.claude/settings.json`, `hub.conf`) goes through `ade_write` in
  `ADE_PY_WRITE` (run by `write_py`): a `mkstemp` temp file in the same folder, fsync, `os.replace`; a target that is
  not a regular file, or a folder on the way (`.ade`, `.claude`, and for `ade init` every folder of the path) that is
  a link, is refused with one line and exit 1. Writers that read first hold `ade_hold`: `flock` on the folder itself
  (no lock file is left in the project) until they exit. `hub.conf` is checked without its folder, the hub root,
  which may be a link the owner made.
- Fetches of the pinned repositories run with `GIT_TERMINAL_PROMPT=0` and `-c credential.helper=`.
