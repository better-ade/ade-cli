# A3: `ade hub new`, a one-line install, and a first run that says what to do

Status: Ready for development (2026-11-21). Risk: medium (creates a GitHub repo for the user). Depends on A1.
Verification command: `bash tests/run.sh`.

## Goal
A new user goes from nothing to a working hub with two commands, and `ade` alone always says what to do next.

```
curl -fsSL https://raw.githubusercontent.com/better-ade/ade-cli/main/install.sh | bash
ade hub new acme-sre [--private|--public] [--dir ~/hubs] [--no-github]
```

- `install.sh` (run via curl) downloads the tagged release named in the repo's `VERSION` (not main), installs `ade` to
  `~/.local/bin`, and says how to add it to PATH when it is missing. Re-running upgrades in place.
- `ade hub new <name>`:
  - with GitHub (default): `gh repo create <name> --template better-ade/ade-brain --private --clone` into `--dir`
    (default `~/hubs`); `--public` only when asked;
  - `--no-github`: clones the template locally instead and leaves the remote unset;
  - then runs the hub's `bin/init --persona P --client C --owner O --name <name>`: `bin/init` is not interactive, so
    `ade hub new` takes `--persona`, `--client` and `--owner` and asks for any that are missing itself (listing
    `bin/init --list`); then it saves the hub as the default in `~/.config/ade/hub`.
- `ade` with no arguments: no hub → "no hub yet: run `ade hub new <name>`"; a hub → its name, `ade status`, and the
  three most useful next commands.
- `ade hub list` / `ade hub use <path>`: the hubs `ade` knows and switching the default.

## Acceptance criteria (`tests/test_hub.sh`; fake `gh`, `git` fixtures, fake `bin/init`; no network)
| AC | Criterion |
|---|---|
| 1 | `hub new acme` calls `gh repo create acme --template better-ade/ade-brain --private --clone` in `~/hubs` (fake gh), runs `bin/init`, saves the path |
| 2 | `--public` passes `--public`; private is the default; `--dir` changes the parent folder |
| 3 | `--no-github` clones the template without calling `gh`, and runs `bin/init` |
| 4 | A bad name (not `[a-z0-9-]+`), an existing folder, or `gh` missing (without `--no-github`) exits 2 and creates nothing |
| 5 | `ade` with no hub prints the `ade hub new` hint and exits 0; with a hub it prints the hub name and next commands |
| 6 | `hub list` shows known hubs and marks the default; `hub use <path>` refuses a path that is not a hub |
| 7 | `install.sh` installs from a given release tag into a given prefix; re-running replaces the binary; a missing PATH entry is reported |
