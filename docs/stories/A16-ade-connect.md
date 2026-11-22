# A16: `ade connect`, predefined connectors with per-user sign-in

Status: Ready for development (2026-11-22). Risk: high (sign-in and access to the owner's accounts).
Owner's intent (2026-11-22): "we'll need to pull these and ask the users via ade cli too that uses claude code" and
"so the skills are predefined but authentication is per user". Depends on ade-skills K5 (recipes); builds against the
contract with fixtures until K5 is released.

The contract is in ade-skills: `.ade/context/connectors.md` (sections 1, 2, 3 and 6), with the decision record
`.ade/context/decisions/0001-connect-and-guard.md`. Where this story and the contract differ, the contract wins: stop
and say so. Record what ade-cli establishes in this repo's `.ade/context/`.

## Goal
`ade connect` lists the connectors ADE knows (ClickUp, Jira, Linear, GitHub, Gmail, Slack, Discord, Outlook, Teams),
says how hard each is to set up, and walks one person at one terminal through signing in to one of them. The project
commits connector names only, in `.ade/connectors.json`. No secret passes through `ade`.

## Acceptance criteria (`tests/test_connect.sh`, with a fake `claude`, a fake `gh` and local recipe fixtures; no network)
| AC | Criterion | Test |
|---|---|---|
| 1 | `ade connect` prints one row per recipe (`service job tier state here`) and the tier key, from recipes read at the ade-skills tag `ade` pins | `connect_lists` |
| 2 | A recipe is used only when its sha256 matches the pinned release's `release.json`; a missing manifest, a mismatch, an unknown field, kind or format refuses that recipe with one line and exit 2; nothing in a recipe is ever run | `connect_pins_and_refuses` |
| 3 | `ade connect <service>` for a ready `plugin` connector: installs the plugin and the `guard` plugin in project scope, adds the name to `.ade/connectors.json`, and prints the one step the person does themselves (`/mcp`, sign in); rerunning changes nothing | `connect_plugin` |
| 4 | For a `cli` connector (`gh`): checks the existing sign-in with a read-only command, never starts or changes it, never reads or prints a token, and says what to run when it is missing | `connect_cli` |
| 5 | For a `claude-ai` connector: installs the skill and the guard, records the name, and says where the person turns the connector on; it claims nothing about a sign-in it cannot see | `connect_claude_ai` |
| 6 | A held service exits 3 with its one-line reason; a tier 4 service also prints what an administrator must do, and sends nothing | `connect_held` |
| 7 | Anything that signs in, signs out or installs runs only for a person at a terminal: refused without a terminal and inside an agent session, with exit 2; a recipe's question is a yes or no asked at the terminal and stored nowhere | `connect_terminal_only` |
| 8 | `.ade/connectors.json` is exactly the contract's shape (names only, sorted, unique); anything else in it rejects the whole file; `ade connect` writes nothing else into the folder and nothing per user anywhere in it | `connect_record` |
| 9 | `ade connect status [<service>]` prints one line per recorded connector with `ready`, `missing`, `unknown` or `outside`, and exits 1 on a gap; `ade connect disconnect <service>` signs out where ade can, prints the vendor's revoke page, and leaves the record alone | `connect_status_disconnect` |
| 10 | Hostile names and values (a service name with `-`, `/`, spaces, newlines or control characters; a recipe title with escape sequences) are refused or printed safely; added to the hostile-input table | `connect_hostile` |

## Out of scope
`ade connect test`, `--check`, the doctor check, `ade restore` and `ade setup` wiring (A17). The guard itself
(ade-skills K6). Any service that needs the user's own app or a local proxy.
