# A15 design note: files, viewer, PDF, open/reveal, file links, tools

Risk raised from medium to **high** by the builder: `ade setup --tools` and `install.sh` run the system package manager
(`sudo apt-get install`, `brew install`) after a yes, and the viewer enforces an access boundary (what may be opened
without a question). Nothing else changes risk: the commands only read.

- **One bash surface, one Python helper.** `cmd_files`, `cmd_view`, `files_act` and the tool functions are bash (the
  tty questions, the tools they call); `files_py` (run with `python3 -I -c`, so a `json.py` in the folder being
  browsed is never imported, and stdin stays the terminal) does `where`, `kind`, the built-in explorer, the PDF and
  image viewer and the link picker. The explorer and viewer call back into `ade view` and `ade files --act`, so every
  check and every tool call has one place.
- **Roots** (`files_roots`): the hub (physical path), each checkout its `projects/*/ACCESS.md` and `ops/*/ACCESS.md`
  list (A9's `access_rows`), and the git top level of the working folder (`--cwd` for the link picker: the agent's
  pane folder). `where`: `in` when the real path is under a root; `link-out` when the name is under a root but is a
  link whose target is not; `out` otherwise. `out` and `link-out` ask `files_confirm` (A9's `tty_confirm`; refused in
  an agent session or without a terminal, exit 2) before the file is even classified. The explorer lists an escaping
  link as `name (outside: not followed) -> target` and never previews it; entering one asks.
- **No control character drawn**: names and previews go through `shown()` (C0, DEL and C1 replaced); a text file with
  control characters is viewed from a private copy made by `no_ctl` (a message says so); pane captures are cleaned
  before matching.
- **No option injection**: every path is absolute and passed after `--` (bat, less, glow, yazi, pdftotext, pdftoppm,
  chafa, `open`); `xdg-open` has no `--`, so it only ever gets an absolute path or an `http(s)://` URL.
- **`o` opens documents only** (fix round): an allow list of extensions (pdf, images, text and Markdown, office,
  audio, video), case-insensitive, on `os.path.realpath`; refused: an executable, a folder, and anything with a bundle
  or link-file extension in any component of the real path (`X.app/...`, `.prefPane`, `.webloc`, `.dmg`, `.zip`, ...).
  `report.pdf -> Evil.app` and `safe.pdf -> f.webloc` are refused. `f` reveals anything.
- **Viewer choice**: code `bat --style=numbers [--highlight-line N --pager "less -RF +Ng"]` (Ubuntu's `batcat`), else
  `less -N +Ng`; Markdown without a line `glow -p`, else `less`; PDF text from `pdftotext -layout` (pages split on form
  feeds), page images from `pdftoppm -f N -l N -png -r 110` on a graphics terminal; images by `chafa` when installed,
  else the terminal's protocol (iTerm2/WezTerm `OSC 1337`, kitty/Ghostty `APC G`), in tmux `chafa --format symbols`,
  else `image: WxH, size (o to open)`. Over SSH always text. A missing extra prints one hint, once
  (`~/.config/ade/hints`); a missing `pdftotext` is said every time (nothing else can show the PDF).
- **Link picker**: `prefix l` runs `ade ui --menu links #{pane_id}`: `capture-pane -p -J -S -2000` and the pane's
  folder go to an `mk_tmp` folder, then a popup runs `ade ui --links <folder>` (only an `$TMP_ROOT/ade.*` folder),
  which lists existing files (`path`, `path:line`, `path:line:col`, `./path`, Markdown link targets) and `http(s)`
  URLs in order, opens a file with `ade view --cwd <pane folder>` and a URL with `ade files --act url`, and removes
  the folder.
- **OSC 8**: the explorer's and viewer's titles are `file://` hyperlinks on terminals that draw them (not in tmux). A
  terminal opens such a link with its default app; it cannot run `ade view`, so the picker is the way into the viewer.
- **Visual Studio Code** (follow-up, owner 2026-11-22): `c`, `ade view --code` and `ADE_VIEWER=code` go through
  `view_code` after `files_target` (so the outside question and the unreadable check are the same as for `o`); the
  allow list of `o` does not apply, any regular file or folder may be opened in an editor. `code_bin` takes
  `command -v code` only when it is absolute and outside the roots. A code file in `ade view` is shown by `less`,
  which owns the keys (and runs in secure mode, so no key can be added to it): `c` is on ade's own screens, and
  `--code` or `ADE_VIEWER=code` cover the pager case. `ADE_VIEWER=code` applies only at a terminal, so a script that
  prints a file never opens a window.
- **Tools**: required `git python3 tmux gh`, extras `yazi bat glow poppler chafa`. `ade setup --tools [required|extras]`
  asks once and runs `brew install <pkgs>` or `[sudo] apt-get install -y <pkgs>` (`python` for python3 on brew,
  `poppler-utils` on apt); yazi and glow are not in Ubuntu 24.04's apt, so on apt they are named with their release
  page and not downloaded (no pinned sha256 to check them against). `ade setup` runs the required step, then the
  extras as one yes/no, before Claude Code; `install.sh` runs `ade setup --tools required` on `/dev/tty` when its
  output is a terminal, else only names what is missing. `ade doctor` prints the tool table, then runs the hub's
  `bin/doctor` as before.
- **yazi** (fix round, coordinator's default): only with `ADE_FILES=yazi`. yazi is neither read-only nor held to the hub and its projects: it
  deletes, renames, moves, runs shell commands, uses its own opener and walks to `$HOME` and `/` without asking. The
  help, README, contract, story and `ade setup`'s extras step say so; the built-in browser is the default.
- **Fix round hardening**: `/`, `$HOME` and its parents are never roots; a folder allowed by a yes is listed, never
  previewed, and a yes to a wide one allows nothing under it. Pagers run with `LESSSECURE=1`, `LESSOPEN=` (bat's
  pager is `less -RF`, glow's `PAGER=less -r`). Names in messages come from Python's `shown()` (C1, bidi, zero-width
  and non-UTF-8 bytes as `?`; bash's `no_ctl` cannot tell a stray C1 byte from UTF-8 cheaply, so the messages use the
  Python path); `--act url` takes printable ASCII only. `y` copies a shell-quoted path when it must; the SSH line is
  `scp -s '<host>:<real path>' .`. bash makes the cleaned copy and the PDF page folder and removes them from a HUP/TERM/INT
  trap when the window is closed; Python's SIGHUP/SIGTERM handlers stop the running tool and remove the page folder
  first (on Linux a hung-up Python can die before its `finally`, so the bash trap is the guarantee). No `file://` title link for a binary file or anything inside a bundle.
- **Not built here**: V2's `ade server install` (another repo); it should use the package lists in the contract.
