# `ade docs` and ade web's Docs page (story U6, contract)

## What a doc is
- A `.md` file, a regular file of 2 MB or less with one link (`st_nlink == 1`: a hard link is never a doc), reached
  without a symlink, under one of the doc roots:
  `_bmad-output/` and `docs/` of the hub, of each `projects/<folder>` and `ops/<folder>`, and of each checkout their
  `ACCESS.md` names; plus `projects/<folder>/PLAN.md`, `STATE.md` (and the same under `ops/`). At most 8 folder levels,
  2000 docs (the walk stops there); dot folders and `node_modules` are skipped.
- The title: the first `# ` line in the doc's first 64 KiB, each raw line cut to 1024 characters before any pattern
  meets it, the closing `#`s dropped (`doc_atx`); else the file name. Titles are cached by (device, inode, mtime_ns,
  size), so a relist reads only the docs that changed.
- The roots reach python as `ADE_DOC_ROOTS`: one `label<TAB>physical path` line each, the hub first (label `hub`),
  then each checkout labelled with its folder; a label is shown without its control characters. A root that is `/`, the
  home folder or a system folder, or is not its own real path, is dropped.

## The id
- `sha256("ade-doc-v1:" + <the doc's real path>)`, first 16 hex characters. Stable while the file stays where it is.
- A doc is served only by an id in the current list (rebuilt at most every 2 s); a path is never taken from a request.
- At read time the file is opened with `O_NOFOLLOW`, `fstat`ed (regular, 2 MB at most, one link), its real path must still be
  itself and inside the roots, and the path must still name the same device and inode. Anything else is a 404.

## ade web routes (behind the same gate as `/api/agents`: Host, Origin, `X-Ade-Key`, Sec-Fetch-Site, the session)
- `GET /api/docs`: `{"docs": [{id, title, folder, kind, rel, mtime}]}`, newest first, through `send_json` (scrubbed).
- `GET /api/doc?id=<16 hex>[&since=<ver>]`: `{id, title, folder, kind, mtime, ver, mermaid, html}`; `ver` is
  `<mtime_ns>-<size>-<inode>`; with `since` equal to the current `ver`, `{"same": true, "ver": ...}`. The text is
  redacted (the A19 rule) before it is rendered; `html` is the renderer's own escaped markup, rebuilt again in the page
  from an allow-list of tags and attributes. 404 for anything refused.
- `GET /api/mermaid`: the diagram drawer as `application/javascript`, only when the file's sha256 is the pinned one;
  404 otherwise. The page runs it as a script element carrying the page's nonce; the CSP is unchanged.
- The page link: `http://127.0.0.1:<port>/?k=<token>&doc=<id>`. The page opens that doc after the code.

## The diagram drawer
- `MERMAID_VERSION`, `MERMAID_URL`, `MERMAID_SHA256` in `ade` (mermaid 11.17.2, `dist/mermaid.min.js` from jsDelivr).
- `ade setup --diagrams` fetches it with curl (https only) and keeps it only on a sha256 match, as
  `~/.local/share/ade/mermaid-<version>.min.js`. `ade web` gets the path and sha as `ADE_MERMAID_FILE` and
  `ADE_MERMAID_SHA`, and checks the sha again before serving it. `ade doctor` lists it as the extra `mermaid`.
- Initialised with `startOnLoad: false`, `securityLevel: "strict"`.
- A drawing (`drawSvg`) is read as HTML in an inert document (mermaid gives HTML-serialised SVG: `<br>`, `&nbsp;`); its
  one element must be an `<svg>`. Kept: only the elements of an allow-list (`SVG_OK`: the SVG and HTML elements
  flowchart and sequence drawings use); no `on*` or `src*` (`src`, `srcdoc`, `srcset`), `action`, `formaction`, `target`, `data`, `form`,
  `ping`, `background` or `poster` attribute; an `href` (in any namespace) only to `#...`; no value with `url(` to
  anything but `#...`. A `<style>` is kept (with the page nonce) only when every rule is scoped to `#<render id>` or is
  one of mermaid's own `@keyframes` (`dash`, `edge-animation-frame`), with no comment, backslash, `<`, `@import` or
  `url(`; otherwise it is dropped.

## Keys
- `ade ui`: `prefix v` is `ade docs` in a popup (a row of `ui_actions`; no bar button). `prefix d` stays detach.
- `ade web`: `d` opens the Docs page; there `q`, Esc or `d` closes it.
- `ade docs` with fzf: Enter views, ctrl-f follows, ctrl-o opens the browser. `--follow`: `q` stops, `w` opens it in
  the browser (exit 10 from the pager, internal).
