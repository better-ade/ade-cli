# A15: files, viewer, PDF, open/reveal, and every file link viewable

Status: In review (2026-11-22). Risk: high (raised by the builder from medium: `ade setup --tools` and `install.sh` run
the package manager, with sudo on Linux, after a yes; the viewer enforces what may be opened without a question).
Depends on A6 (ade ui).
Owner's intent (2026-11-21): a directory explorer, file viewer and PDF viewer in the CLI, with open in the directory
or Finder, and every file link viewable there. Verification command: `bash tests/run.sh`.

## Goal
- **`ade files [path]`** and `ade ui` key `e`: a directory explorer over the hub and its projects with name search and
  live preview; uses `yazi` when installed, else a built-in browser (bash + python3, no extra install).
- **`ade view <path[:line]>`**: code with syntax colours (`bat`, else `less -N`) opened at the line; Markdown rendered
  (`glow`, else plain); images inline on terminals with graphics (iTerm2, kitty, WezTerm, Ghostty; via the terminal's
  protocol or `chafa`), else "image: <size> (o to open)".
- **PDF:** page images inline on graphics terminals (`pdftoppm` + the terminal protocol or `chafa`), else text
  (`pdftotext -layout`), with page next/previous, go-to page and search; over SSH always text.
- **Actions** in explorer and viewer: `o` open in the default app (`open` / `xdg-open`), `f` reveal in Finder
  (`open -R`) or the Linux file manager (`xdg-open <dir>`), `y` copy the path; over SSH, offer the path and a copy/download
  command instead.
- **Every file link viewable:** `ade ui` key `l` scans the visible pane (and its scroll-back, last 2000 lines) for file
  paths (`path`, `path:line`, `path:line:col`), Markdown links and URLs; lists them; opens the pick in `ade view` at the
  line, or URLs in the browser. Paths are resolved against the agent's working folder. `ade`'s own output wraps paths in
  terminal hyperlinks (OSC 8) where supported, pointing at `ade view`.
- **Tools installed by ade, not by hand (owner, 2026-11-21):** required tools (`git`, `python3`, `tmux`, `gh`) are
  checked by the one-line installer (A3) and `ade setup` (A5) and installed after a yes (Homebrew on macOS, apt on
  Ubuntu); the viewer extras (`yazi`, `bat`, `glow`, `poppler`, `chafa`) are one yes/no step in `ade setup`; `ade files`
  and `ade view` fall back to built-ins when an extra is missing and print a one-line hint once; `ade doctor` lists each
  tool as installed or missing; `ade setup --tools` installs what is missing; V2's `ade server install` installs the
  same set with apt.
- **Read-only and contained:** nothing edits, moves or deletes; viewing outside the hub and its project checkouts asks
  first; symlinks leaving those folders are shown, not followed, unless confirmed.

## Acceptance criteria (`tests/test_files.sh`; tmux capture via the A8 full-screen renderer; fakes for open/xdg-open/bat/glow/pdftotext/pdftoppm)
| AC | Criterion |
|---|---|
| 1 | The built-in explorer lists, searches and previews a fixture tree; `yazi` is used when present (fake) |
| 2 | `ade view file.ts:42` opens at line 42 with `bat` (fake records args) and with the `less` fallback |
| 3 | A fixture PDF shows text pages without graphics support, and page images when the terminal reports graphics |
| 4 | `o`, `f`, `y` call open / open -R (or xdg-open) / the clipboard with the right path; over SSH they offer the path instead |
| 5 | The link picker finds `src/a.ts:3`, `./docs/x.md`, `[t](docs/y.md)` and a URL in a captured pane, and opens each correctly |
| 6 | Paths outside the hub and checkouts ask first; escaping symlinks are not followed without confirmation |
| 7 | No command writes, moves or deletes anything (a test compares the fixture tree before and after) |
| 8 | The installer and `ade setup` detect missing required tools and install them after a yes (fake brew/apt record the calls); `ade setup` offers the extras as one step; `ade doctor` lists them; `--tools` installs only what is missing |
