# A1: `ade`, one command in any terminal

Status: Ready for development (2026-11-21). Risk: medium. Verification command: `bash tests/run.sh`.
Owner's intent (2026-11-21): "create ade-cli where it can be spawned on terminals"; `ade` absorbs the ADE app's
existing `ade open`; it is the command Telegram and a future server use. Keep it thin: the hub's `bin/` scripts stay the
single source of truth.

## Goal
A Bash 3.2 script `ade` (installed to `~/.local/bin/ade` by `install.sh`) that:
- **Hub commands:** finds the hub (`$ADE_HUB`, else walking up from the current directory to a folder with
  `bin/lib.sh` and `hub.conf`, else the path in `~/.config/ade/hub`) and runs `"$HUB/bin/<cmd>" "$@"` for: `work`,
  `status` (→ `bin/sessions`), `dispatch`, `notify`, `chat`, `method`, `keys`, `models`, `roles`, `doctor`, `sync`,
  `context`, `agent-run` (→ `bin/agent`). A command whose script the hub lacks prints "this hub has no bin/<cmd>; update
  it" and exits 2.
- **Project commands (no hub needed):**
  - `ade init` in a project: copies ade-method at its pinned tag (`rules.md` → `.ade/rules.md`, `agents/*.md` →
    `.ade/agents/`, `bmad/custom/*.toml` → `_bmad/custom/`, `templates/context/` → `.ade/context/`,
    `templates/standards.md` → `docs/standards.md`), never overwriting an existing file (it lists what it kept), and
    records the tag in `.ade/method-version`.
  - `ade agent list` / `ade agent add <name>`: from ade-agent-registry at its pinned tag, lists specialists (name and
    description) or copies `agents/<name>.md` to `.ade/agents/<name>.md`.
  - `ade skills add <plugin>`: runs `claude plugin marketplace add better-ade/ade-skills` (once) and
    `claude plugin install <plugin>@ade-skills --scope project`.
- **`ade open …`:** when `ADE_HOOK_BIN` is set (inside the ADE app), `exec "$ADE_HOOK_BIN" open "$@"`; otherwise prints
  "ade open works inside the ADE app" and exits 2.
- `ade version`, `ade help` (every command, one line each).

Pins: `ADE_METHOD_REF` default `v2.0.0`, `ADE_REGISTRY_REF` default `v1.1.0`; repos overridable by `ADE_METHOD_REPO`
and `ADE_REGISTRY_REPO` (tests point them at local fixture repos; tests never use the network).

## Acceptance criteria (`tests/test_ade.sh`, fixtures only)
| AC | Criterion | Test |
|---|---|---|
| 1 | Hub found by `$ADE_HUB`, by walking up, and by `~/.config/ade/hub`, in that order | `finds_hub` |
| 2 | `ade work x --role builder` runs the hub's `bin/work x --role builder` with arguments intact (spaces kept) | `passes_args_to_hub` |
| 3 | `ade status` runs `bin/sessions`; a missing hub script exits 2 with the update message | `status_and_missing_script` |
| 4 | No hub found: hub commands exit 2 naming the three ways to set one | `no_hub` |
| 5 | `ade init` copies the method at the pin into an empty project and records the tag | `init_copies_method` |
| 6 | `ade init` on a project with an existing `.ade/rules.md` keeps it and lists it as kept | `init_never_overwrites` |
| 7 | `ade agent list` shows registry names and descriptions; `ade agent add frontend` copies it; an unknown name exits 2 | `agent_list_and_add` |
| 8 | `ade skills add notes` calls `claude plugin` with the marketplace and the project-scope install (fake `claude`) | `skills_add_calls_claude` |
| 9 | `ade open a b` execs `$ADE_HOOK_BIN open a b`; without it exits 2 | `open_inside_ade_only` |
| 10 | `install.sh` installs `ade` into a given prefix and `ade version` prints `VERSION` | `install_and_version` |

## Out of scope
The ADE app switching its own `ade` to this one (an ade-terminal story); Windows; the server mode.
