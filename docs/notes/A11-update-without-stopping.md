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
