# A21: `ade project add`, `list` and `--scan`: load existing repos into the hub

Status: Ready for development (2026-11-23). Risk: medium (it clones, and writes into the hub and the person's repos,
after asking).
Owner's intent (2026-11-23): "Ok can we load an existing project using ade command", "so if I have several projects,
how do we load with ade?", then "yes" to this design.

## Goal
A person who already has code brings it into the hub with one command: `ade project add` takes repos they have (a
path) or name (a URL), makes each one a hub project folder with the hub's own `bin/new`, and fills that folder's
`ACCESS.md` Code row from the repo so the hub's `repos_of` finds the checkout. `--scan` picks from a folder of repos;
`ade project list` shows what the hub holds. No credential is ever written; a failure for one repo never stops the
others.

## Acceptance criteria (`tests/test_project.sh`: a fixture hub with fakes of `bin/new`, `bin/brain`, `bin/sessions` and `bin/work`, a fake `gh`, a `git` whose network clone is faked; local repos made in the test)
| AC | Criterion | Test |
|---|---|---|
| 1 | `ade project add <path>` (a git work tree; its top level is used) runs the hub's `bin/new projects/<name>` and writes one Code row: the remote in https form, the checkout, the default branch (`origin/HEAD`, else the current branch), `(owner)`, and the CI it sees (`.github/workflows` names, `.gitlab-ci.yml`, `.circleci`, else `none found`). The hub's own `repos_of` reads the checkout back. Several arguments make several projects | `adds_local_repo`, `adds_two`, `repos_of_reads_row` |
| 2 | A URL (`https://`, `git@`, `ssh://`, or `owner/repo` meaning GitHub) is cloned into the code folder (`ADE_CODE_DIR`, else `~/Project` when it is there, else `~/code`, made after saying so), never into the hub; `gh repo clone` when `gh` is signed in and the host is GitHub, else `git clone` | `adds_url`, `code_folder` |
| 3 | The name is the repo's folder name in the hub's folder rules (`a-z 0-9 -`), or `--name`; a hub folder of that name, or a repo the hub already lists, is left as it is and said so | `existing_name_kept`, `name_rules` |
| 4 | A remote with `user:token@` (or a token alone) is shown and stored without it; nothing `ade` prints or writes holds it, and a URL given with one is cloned without it | `credentials_stripped`, `credential_forms` |
| 5 | `ade init` is offered once per repo (yes/no, Enter is no) and never overwrites; `--no-init` never offers; `--yes` answers yes to every offer | `init_offered_never_overwrites`, `no_init_and_yes` |
| 6 | The repo's `README.md` and `docs/` join the hub's memory (`HUB_BRAIN_PATHS` in `hub.conf`, then `bin/brain index`); a hub without `bin/brain`, an index that fails, or a path the list cannot hold is one line saying it was skipped and why | `memory_indexed` |
| 7 | A path that is not a git repo, or a clone that fails, fails that project only: the shared `failed` question at a terminal (try again, skip, stop), one line otherwise; the others are added, the summary names each, and the exit code is 1 | `non_repo_fails_alone`, `failure_asks_at_terminal` |
| 8 | After the summary (one line per project): "start focus agents on them now? [y/N]" runs `ade work projects/<name>` for each; in an agent session or without a terminal it is not asked and nothing starts | `start_refused_in_agent_session`, `start_at_terminal` |
| 9 | `ade project add --scan <folder>` lists the git repos directly under it (their top levels only), marks those already in the hub, and takes `1 3`, `1-3`, `all` or names through the guide's numbered choice; then the same steps | `scan_picks` |
| 10 | `ade project list` prints each project folder's name, checkout, branch, focus agent state (from `bin/sessions`) and its `STATE.md` "Updated" line; `ade project` alone prints the help; a hostile name or folder is refused (exit 2) and never runs | `lists_projects`, `project_help`, `test_hostile.sh` |

## Notes
- `ade` never reimplements `bin/new`; a hub without it is a failure for that project, with the line "update the hub".
- Names, paths, branch and workflow names from a repo are data: no shell evaluation, control characters and `|` never
  reach the table, and the row is read back before the project counts as added.
- The skill `ade-project` ships with the command (in the ade-skills `ade` plugin, not in this repo).
- Contract: `.ade/context/hub-interface.md`, "`ade project` and the hub (A21)".
