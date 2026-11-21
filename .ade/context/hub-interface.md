# What `ade` expects from a hub (contract)

`ade` stays thin: the hub's `bin/` scripts do the work; `ade` finds the hub, exports `HUB` to it and returns the
script's exit code unchanged. A hub is a folder with `bin/lib.sh` and `hub.conf`.

## `~/.config/ade/` (folder 0700, files 0600, names and paths only, never secrets)
- `hub`: the default hub's path (A1).
- `hubs`: every hub `ade hub new` made or `ade hub use` chose, one path per line (A3).
- `orchestrators`: one `name<TAB>hub` line per orchestrator (A2). Names `[a-z0-9-]+`, unique; one per hub.

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
