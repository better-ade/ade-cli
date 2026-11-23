# A20: `ade shot`, screenshots as proof

Status: In review (2026-11-23; one fix round after the adversarial review). Risk: high (a capture of a screen or a page can hold private data, and `--tg` sends an
image to Telegram). Depends on A1 (the hub is found as for every command), A6 (`ade ui`, whose tabs `agent` reads) and
ade-brain's `bin/chat send` (for `--tg`). Owner's intent (2026-11-23): "Ade should have a screenshot tool as well for
proofs", then "Can be attached to tg as well". Proof is the ADE method's evidence for Done (`.ade/rules.md`,
Definition of Done: for work with no code, "the evidence is recorded instead").
Verification command: `bash tests/run.sh`. Design note: `docs/notes/A20-screenshots.md`.

## Goal
- **`ade shot url <address> [--name N] [--full-page] [--width W]`**: a PNG of a page through the headless Chromium the
  hub already uses (Playwright's, found where the hub finds it; ade downloads none). When it is missing: one plain
  line on how to get it. Only `http`, `https` and `file` addresses; a `file` address only for a regular file inside
  the project; nothing the page asks for may be a file outside it.
- **`ade shot screen [--name N]`**: the whole desktop. macOS: `screencapture -x` (no sound). Linux and the ADE
  Computer: the X display (`import -window root`, else `xwd -root`, which the image has, converted to a PNG). At a
  terminal it asks first ("this captures everything on your screen, including other apps"), with or without
  `--yes-screen`. From an agent session it refuses unless `--yes-screen` is given, the session's settings put a
  permission prompt before this command line, and no settings file lets the session skip permissions: the person's
  Allow at that prompt is the approval (the hub's settings ask for every `ade shot screen`). Without a
  terminal and outside an agent session there is nobody to ask: refused. A Mac that does not let the terminal record
  the screen: one plain line on where to grant it; ade never changes a system setting.
- **`ade shot agent <name>`**: the focus agent's tab in ade's tmux server (`tmux capture-pane -p -e`), its text
  redacted, then rendered to a PNG by the same headless Chromium. Colour sequences become colours; every other escape
  sequence and control character is dropped, never executed.
- **Where shots go:** `<project>/.ade/evidence/<YYYY-MM-DD>/<HHMMSS>-<name>.png` (UTC) and a sidecar `.txt` (what,
  when, the command, the address or agent, the size, what was or could not be redacted). Folders 0700, files 0600;
  names are sanitised; a shot never replaces another. Inside the hub (no project): the hub's own `.ade/evidence/`.
  The path is printed.
- **Redaction:** a terminal shot hides keys and tokens in the captured text before rendering: the hub's `bin/chat
  logs` rule, then the additions of `ade web` (A19). A page or screen shot cannot be redacted; the sidecar and the
  help say so.
- **`--tg [caption]`**: after saving, the image goes to the hub's paired, locked owner through the hub's
  `bin/chat send`; refused when the hub's `bin/chat status` does not say the bot is locked. The caption is cleaned
  and cut.

## Acceptance criteria (`tests/test_shot.sh`; fakes for Chromium, `screencapture`, `import`, `xwd`, `tmux` and the hub's `bin/chat`)
| AC | Criterion | Test |
|---|---|---|
| 1 | `ade shot url <address>` saves a PNG of the page through Playwright's Chromium, headless, with a throwaway profile; `--width` (320 to 3840) and `--full-page` change what is captured; a page that does not load, or a browser that answers nothing or nonsense, saves nothing and leaves no browser running; with no Chromium, one line on how to get it, and `ade doctor` names it | `url_shot` |
| 2 | Only `http`, `https` and `file` addresses, with no user or password, no control character and no option-like text; a `file` address only for a regular file inside the project (not a link, not a `.env`, a key or a `.git` file); every request the page makes is checked: a file outside the project, a `.env`, key or `.git` file of the project, and a link-local or metadata address (169.254.0.0/16, `fd00:ec2::254`, `metadata.google.internal`) are stopped, from any page, and the sidecar says what was stopped | `url_addresses` |
| 3 | `ade shot screen` at a terminal says what it captures and asks; only a yes typed there captures (macOS: `screencapture -x`); `--yes-screen` answers nothing at a terminal; without a terminal, with or without the flag, nothing is captured | `screen_asks` |
| 4 | From an agent session (any of `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_PID`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_EXECPATH`, a pseudo-terminal or not) it refuses without `--yes-screen`. With it, it refuses unless an ask rule of the session's project (`CLAUDE_PROJECT_DIR`, else the git or hub root; never the shell's folder, one below or one above) or of the user's settings matches the command line as it is, and refuses when the project's `settings.json` or `settings.local.json`, the user's settings (`CLAUDE_CONFIG_DIR` or `~/.claude`) or the managed settings set `bypassPermissions` or cannot be read. The sidecar says how it was approved | `screen_agent_session` |
| 5 | A Mac that refuses the capture: one line on where to grant Screen Recording, nothing saved, no setting changed. Linux: `import -window root`, else `xwd -root` converted pixel for pixel, else one line on what to install; no display, one line | `screen_capture_tools` |
| 6 | `ade shot agent <name>` captures the one tab the name means (the tab's name, its folder, the folder's last part or the agent's name) with `tmux capture-pane -p -e` and saves it as a PNG; a name of two tabs, of none, or a hostile one captures nothing | `agent_shot` |
| 7 | A terminal shot's text has keys and tokens hidden before it is rendered (bot tokens, `sk-` keys, long runs, a key split by a colour sequence or by a character that draws nothing, a password, an Authorization header, `Cookie:` and `Set-Cookie:` values, a URL's password, a private key block); markup in the pane is shown as text; no escape sequence or control character reaches the page | `agent_redacted` |
| 8 | Shots land in `<project>/.ade/evidence/<date>/<time>-<name>.png` with the sidecar, folders 0700 and files 0600, never over another shot, ignored by git; each folder level is opened from its parent without following a link, so a linked `.ade`, evidence or day folder, or a link planted under the shot's name, is never written through; names are sanitised and a hostile one is refused before anything is captured; inside the hub, the hub's own folder; nowhere to save, nothing captured | `evidence_layout` |
| 9 | `--tg [caption]` runs the hub's `bin/chat send <file>` with the cleaned caption on stdin, after saving; a bot that is not locked, a hub that refuses, a failed send and a hub without `send` each say so, with the shot still saved | `tg_sends` |
| 10 | `ade help`, `ade shot help`, the README and the changelog name the three modes, where shots go, `--tg`, and that a page or screen shot cannot be redacted | `help_and_docs` |

## Out of scope
- Installing Chromium (`ade setup --tools` does not; the hub's `bin/server install` does on a server).
- Wayland, a single window or a region of the screen, video.
- Redacting pictures (blurring a page or a screen).
- Retrying a failed Telegram send (the hub keeps no file).
