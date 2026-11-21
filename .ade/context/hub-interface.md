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
