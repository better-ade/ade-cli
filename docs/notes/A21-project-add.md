# A21 design note: `ade project add`, `list` and `--scan`

Story: [A21](../stories/A21-project-add.md). Risk: medium. Contract: `.ade/context/hub-interface.md`, "`ade project`
and the hub (A21)".

## Shape
- `cmd_project` dispatches `add`, `list` and the help. `project_add` parses the flags (refusals are exit 2, before
  anything is touched), then calls `project_one` per argument: 0 added, 2 left as it is, 1 failed. A failure goes to
  the shared `failed` question (`FAILS` row `project`: try again, skip, stop) only when a person is at a terminal;
  otherwise it is one line on stderr. The loop always goes on, the summary names each, and the exit code is 1 when
  any failed.
- `project_one`: path or URL to a repo (`proj_clone` for a URL), the name, the two "already in the hub" checks (by
  folder name and by checkout), the hub's `bin/new` through `run_logged`, then `proj_row` (Python through `write_py`,
  so the write is atomic and never goes through a link) and a read-back with the same awk as the hub's `repos_of`.
- Memory: the hub's index is rebuilt from `HUB_BRAIN_PATHS`, so a one-off environment override would be dropped by the
  next `bin/brain index`. The repo's `README.md` and `docs` are therefore appended to `HUB_BRAIN_PATHS` in `hub.conf`
  (`conf_set`), then `bin/brain index` runs once for the whole command.
- `--scan` uses `ask_choice` with `ASK_MULTI=1` and a new `ASK_RANGE=1` (`all`, `2-4`), expanded by `ask_tokens`; the
  guide's own multi-choice question does not set it and behaves as before.

## Safety
- Credentials: `url_nocred` strips `user:token@` before a clone (so git never stores it) and `url_clean` makes the
  https form for the table; what the person typed is printed through `proj_shown`.
- Data, not code: names and paths reach git and the hub's scripts as single arguments; the table cells drop `|` and
  control characters; a checkout path that holds one is refused.
- Nothing is overwritten: an existing hub folder is never passed to `bin/new`, `ade init` keeps what is there, and a
  clone never lands on an existing folder (one with the same remote is used as it is).
- The start offer needs a terminal and is never made in an agent session; `ade work` runs as a child `ade`.
