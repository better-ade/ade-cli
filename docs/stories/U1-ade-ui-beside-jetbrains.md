# U1: `ade ui` works beside a JetBrains IDE

Status: **Approved** (owner, 2026-11-28). Risk: **medium** (an editor command run with a file path; tmux
checks; no change to sign-in, keys, sync or what a session may do). Verification: `bash tests/run.sh`.
Owner's intent (2026-11-28): "I'm also thinking if we should have this run along side jetbrains (I use jetbrains)".

## Today
- The `c` key (in `ade files`, `ade view` and the link picker) and `ADE_VIEWER=code` always run `code --goto
  path:line:col`, which is Visual Studio Code. A JetBrains user has no way to open a file in their IDE at a line.
- `ade ui` needs tmux 3.2 or newer for its popups (`display-popup`), but only checks that tmux exists. An older tmux
  fails on the first popup key.
- `ade ui`'s `prefix Left/Right` keys and `set -g mouse on` can clash with an IDE's built-in terminal, and nothing
  says how to turn them off.

## Acceptance criteria (each named by its test)
1. **editor_choice** (tests/test_files.sh): `ADE_EDITOR` picks the editor for `c`: `code` (the default, as today),
   `idea` (or any JetBrains launcher: `idea`, `pycharm`, `webstorm`, `goland`, `rider`, `clion`, `phpstorm`,
   `rubymine`, `fleet`), run as `<launcher> --line <N> --column <C> <path>`, or a command with `{path}`, `{line}` and
   `{col}` placeholders. The path is always one argument, never a shell string; a value with a `;`, `|`, `&`, `$` or
   backtick outside the placeholders is refused with one line.
2. **editor_detected** (tests/test_files.sh): with no `ADE_EDITOR`, inside a JetBrains terminal
   (`TERMINAL_EMULATOR=JetBrains-JediTerm`) `c` uses the first JetBrains launcher found on PATH, else `code`, else it
   prints the path:line. `ade setup --check` shows which editor `c` uses.
3. **tmux_version** (tests/test_ui.sh): `ade ui` with tmux older than 3.2 exits 1 before starting, naming the version
   found, the one needed and how to update it; 3.2 and newer start as today.
4. **ide_safe_keys** (tests/test_ui.sh): `ADE_UI_MOUSE=off` leaves tmux's mouse mode off, and `ADE_UI_ARROWS=off` drops
   the `prefix Left/Right` binds (`prefix 0-9` still work); both are read from `~/.config/ade/ui` too, and `ade ui`
   inside a JetBrains terminal says once how to set them.
5. **u1_docs** (tests/test_ui.sh): README ("Use it beside your IDE"), `ade help` and CHANGELOG describe `ADE_EDITOR`,
   the two switches and the tmux version.

## Out of scope
A JetBrains plugin, clickable links inside the IDE's terminal (OSC 8 stays off there), the clipboard, U2 to U4.
