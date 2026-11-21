# A11 design note: ade update without stopping anything

- ade itself: `main/VERSION` names the release; a newer one is downloaded next to the installed file
  (`.ade-update.XXXXXX`), stamped like `install.sh`, run once (`bash <new> version` must print `ade <version>`), then
  `mv -f` over the installed file. bash reads a script while it runs it, so the running file is never written: a
  running ade keeps the old inode. A checkout (no stamped version) is never replaced. Offline: nothing changes.
- `ade dash` compares the installed file's stamped version with its own after each frame and re-execs once it
  differs (the temp folder is removed first; exec skips the exit trap).
- The hub: refused (exit 1, unchanged) with local changes (`git status --porcelain`) or when the upstream is not a
  fast-forward; else `git merge --ff-only`, then `bin/method sync`.
- Plugins: `claude plugin update` for each `*@ade-skills` key in Claude Code's `installed_plugins.json`. Claude Code:
  `claude update` through A4's runner (timeout, never blocking), the 24-hour stamp reset.
- `ade ui`: the config is written again and loaded with `tmux source-file` on ade's server; never detached.
- Restart-needed parts: a running orchestrator whose chat code changed restarts only when `bin/sessions` shows `main`
  idle; a busy one is recorded in `~/.config/ade/restart-pending` and retried on the next `ade update`. No signal is
  ever sent by ade update itself.
- One `bin/notify all` line names what changed and "applies on your next prompt" (plus `/reload-plugins`).
- Left for A12: the daily check (stamp, auto-update policy) and the sha256 check against the release manifest.

## Fix round (2026-11-22, after the adversarial review)
- The download goes to a private temp folder (`mk_tmp`); `ade_check` checks it there with mode 600: `#!/bin/bash`,
  `bash -n`, the last line `# ade: end of file (ade update checks this line; keep it last)` (a cut-short download has
  no such line), and `bash <file> version`. Only then `ade_put` makes two temp files beside the installed one (mode
  644 for the kept copy, 755 for the new one, made just before the renames): the installed file becomes `.ade.prev`,
  the new one is renamed over the installed path. A version stamp alone is easy to fake; A12 adds the sha256 from the
  release manifest.
- Every temp path is tracked; `upd_traps` removes them on EXIT, INT (exit 130) and TERM (exit 143), and clears the
  traps when the step ends.
- `ade update --rollback`: `.ade.prev` (shebang, `bash -n` and its own `ade version`; older files have no marker) back
  into place; the current one is kept as `.ade.prev`, so a second rollback returns.
- The hub: `git status --porcelain --untracked-files=no`, so an untracked journal file never blocks;
  `git merge --ff-only` refuses an untracked file the pull would overwrite, and the hub stays unchanged.
