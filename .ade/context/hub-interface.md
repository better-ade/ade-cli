# What `ade` expects from a hub (contract)

`ade` stays thin: the hub's `bin/` scripts do the work; `ade` finds the hub, exports `HUB` to it and returns the
script's exit code unchanged. A hub is a folder with `bin/lib.sh` and `hub.conf`.

## `~/.config/ade/` (folder 0700, files 0600, names and paths only, never secrets)
- `hub`: the default hub's path (A1).
- `orchestrators`: one `name<TAB>hub` line per orchestrator (A2). Names `[a-z0-9-]+`, unique; one per hub.

## `hub.conf` keys `ade` reads
- `HUB_CHANNELS` (space-separated channel types, ADR 0006): shown by `ade orchestrator list`.

## `bin/chat` (ade-brain C5) as `ade orchestrator` calls it
- `bin/chat setup <channel>`: interactive; exit 2 for an unknown channel (`ade` shows the hub's message and exit). Called
  with `ADE_ORCHESTRATOR=<name>` in the environment.
- `bin/chat start` / `bin/chat stop`.
- `bin/chat status`: first line starts `running` or `stopped`; a running one carries `since <time>` (one word).
  Anything else shows as `unknown`.
- `bin/chat logs -n <N>`: the last N lines of the hub's chat log, printed as is (`ade` adds nothing).
