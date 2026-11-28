# U6: read the PRD, architecture and stories as they are written, in the terminal or the browser

Status: **Approved** (owner, 2026-11-28). Risk: **high** (the browser page serves the hub's files over
`ade web`, which can be reached from the tailnet; that is access to data). Verification: `bash tests/run.sh`.
Owner's intent (2026-11-28): "when we write PRD or any docs we need a viewer from the CLI", "or a weburl viewer". The
owner chose "Both": a list in the terminal, and the same doc in `ade web`.

## Today
- `ade view <file.md>` shows one Markdown file, through glow when it is installed.
- Nothing lists the hub's planning docs, and nothing follows a doc while an agent writes it.
- `ade web` (A19) is read-only and shows agents, logs, journal and chat, but no docs.

## What a "doc" is
A `.md` file under `_bmad-output/` or `docs/`, in:
- the hub root;
- each folder;
- each project `ade project` knows.

Each folder's `PLAN.md` and `STATE.md` count too. The rules:
- a symlink, or anything outside these roots, is never a doc;
- every file found is held to the same `inside()` check `ade files` uses.

## Acceptance criteria (each named by its test)
1. **docs_list** (tests/test_docs.sh):
   - `ade docs [<folder>]` lists the docs, newest first, with their title (the first `#` line), folder, kind and age. Kind is one of prd, architecture, ux, story, spec, plan or doc, taken from the path or the name.
   - Typing filters the list, using fzf when installed, else ade's numbered picker. Enter opens the doc in `ade view`.
   - In `ade ui`, `prefix v` opens the same list in a popup. Tmux's own `prefix d` stays detach. The keys popup lists `v`, and with U5 the action is in its menu table too.
2. **docs_follow** (tests/test_docs.sh):
   - `ade docs --follow <doc>`, or `F` in the list, shows the doc again whenever it is saved, keeping the place in it. It checks the file's mtime at most once a second.
   - `q` stops it. While it is open, nothing in the doc is run or edited.
3. **docs_web_page** (tests/test_web.sh):
   - `ade web` gains a Docs page: the same list, and a doc rendered as HTML by a small built-in renderer. It needs no new dependency and loads nothing from the network.
   - The renderer handles headings, lists, tables, code blocks, quotes, emphasis and links.
   - Every character of the file is escaped. Raw HTML in the Markdown shows as text, never as markup.
   - The page keeps today's CSP, which allows no inline script without the nonce.
4. **docs_web_links** (tests/test_web.sh):
   - A link to another doc opens it in the viewer, and a heading gets an anchor.
   - An external link opens in a new tab with `rel="noopener noreferrer"`.
   - A `javascript:`, `data:` or `file:` link is shown as text.
5. **docs_web_live** (tests/test_web.sh): an open doc reloads within 3 seconds of being saved, keeping the scroll position. The page shows "updated hh:mm:ss".
6. **docs_web_access** (tests/test_web.sh):
   - Docs are served only behind today's gate: the token, the one-time code, the session cookie, `X-Ade-Key`, the Origin and Sec-Fetch checks.
   - A doc is asked for by its id from the list, never by a path. An id not in the current list gets 404.
   - Traversal (`..`), a symlink, a file swapped for a symlink after listing, a file over 2 MB, and a path outside the roots are each refused.
   - Every doc goes through ade web's redactor (A19) before it is sent, so a key shape or a connection-string password never reaches the browser.
7. **docs_web_link** (tests/test_docs.sh):
   - `w` in the list, or `ade docs --web <doc>`, opens that doc in the browser.
   - If ade web is not running, it starts it (127.0.0.1 only; never `--tailnet` on its own) and prints the code as today.
   - The link carries the token and the doc's id only.
8. **docs_diagrams** (tests/test_web.sh, tests/test_setup.sh):
   - A ```` ```mermaid ```` block is drawn as a diagram on the Docs page, and redrawn when the doc reloads.
   - Mermaid is an optional extra, like glow. `ade setup` fetches one pinned `mermaid.min.js` and keeps it only when its sha256 matches the one written in `ade`. It is stored under `~/.local/share/ade/` and `ade doctor` lists it.
   - The page loads it from ade web itself, behind the same gate, with the page's nonce. Nothing is fetched from a CDN at view time.
   - It runs with `securityLevel: "strict"`, so a diagram's labels can carry no HTML, script or link. A diagram that fails to parse shows its source and the parse error.
   - Without the extra, the block shows as code with one line: "diagram: `ade setup` adds the diagram drawer".
   - In the terminal, `ade view` and `--follow` show the block as code, with one line: "diagram: w draws it in the browser".
9. **u6_docs** (tests/test_docs.sh): README ("Read the plan as it is written"), `ade help`, the keys popup and CHANGELOG describe `ade docs`, `prefix v`, `--follow`, `--web`, the Docs page and diagrams.

## Out of scope
- Images, which show as their alt text; a later story can add them.
- Drawing diagrams in the terminal itself.
- Diagram kinds other than Mermaid (PlantUML, Graphviz).
- Editing, comments, search inside docs, PDF export, and docs from a hub you are not in.
