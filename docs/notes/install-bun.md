# Install bun as part of set-up, without Homebrew

risk: medium (no risk was given). Builder's flag for the reviewer: ade downloads a program, runs it once (`--version`)
and writes one line into the person's shell start file.

## Why
`bin/chat start` failed with "bun not found" after set-up. bun was installed only at the Telegram step, with
`brew install bun`, which failed on the owner's Mac twice over: outdated Command Line Tools, and a tap that is not
trusted. The owner: "it should be part of the installation".

## Decisions
- bun joins `REQUIRED_TOOLS`, so the guide's tools step, `ade setup --tools`, `install.sh` and `ade doctor` have it
  with no new step. `tools_install` splits its list: the packages go to Homebrew or apt as before (`pkgs_install`,
  one question), bun goes to `bun_install` (its own question, saying what a yes does). Two questions when both are
  missing: each shows exactly what it runs, and bun still installs when Homebrew is missing or fails.
- The pin: `BUN_VERSION` in `ade`, one place. bun 1.4.4 (released 2026-10-22), the newest release at least two weeks
  old on 2026-11-23 (1.4.5 was four days old). A bump is a change of that one line.
- Download: `curl --proto =https --proto-redir =https --tlsv1.2` of `<asset>.zip` and `SHASUMS256.txt` from
  `github.com/oven-sh/bun/releases/download/bun-v<version>/`. The checksum list comes from the same release as the
  zip, as asked: it guards against a damaged or swapped download, not against a release that was itself replaced
  (no hash is pinned in `ade`; that would need four hashes changed at every bump).
- Unpacking: python3's `zipfile` reads the one member `<asset>/bun` into ade's temp folder. Not `unzip`: a fresh
  Ubuntu (the ADE Computer) has none, python3 is already required, and one named member cannot write outside the
  folder. The unpacked program must print the pinned version for `--version` before it is renamed into
  `~/.bun/bin/bun` (0755); a bun that cannot run on this CPU is said, not installed.
- Rosetta: an Intel shell on Apple silicon gets the Apple silicon build, as bun's own installer does.
- Found: `bun_path`, at the start of every `ade`, prepends `~/.bun/bin` to PATH when no bun is on PATH and
  `~/.bun/bin/bun` is there, so the hub's `bin/chat` (`command -v bun`) finds it under `ade chat start`. A bun on
  PATH wins and is never replaced.
- The shell start file: one marked line, only after an install by ade, only when `~/.bun/bin` is not on PATH, never
  when the file already names `.bun/bin` or `BUN_INSTALL` (bun's own installer's lines). This is what makes
  `bin/chat start` work in the second terminal window the Telegram step asks for.
- Failures go through `failed` with a new row `bun` (try again, the manual steps, stop); the Telegram step keeps its
  row `tg-bun`, which adds "skip Telegram for now". The manual steps are the same download, check and move by hand.

## Not done here
- Linux x64 CPUs without AVX2 (bun's `-baseline` builds) and musl systems: the four named assets only; the
  `--version` check turns a bun that cannot run into a plain failure.
- `ade reset` and `ade uninstall` do not remove `~/.bun` or the start-file line.
- The hub's `bin/chat` still names https://bun.sh in its own "bun not found" line; the hub is another repository.
