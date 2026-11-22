# A18b design note: when a guide step fails

- Found by the owner on the released guide (0.2.2): a Claude account at its weekly limit failed the live test, the
  guide printed the hub's raw line cut at 200 characters and showed the list again. Asked: say it plainly and offer
  to sign in; then, the same for every place the guide can fail.
- One function (`failed`) and one table (`FAILS`) in `ade`; every failure point calls it and acts on `CHOICE` in a
  loop of its own. The contract is in `.ade/context/hub-interface.md`, "When a guide step fails".
- The live test: `live_test` keeps the engine's last line (`LIVE_RAW`); `live_explain` turns it into the line
  (limit and reset time, sign-in, or the reason) and the details; `live_failed` asks and acts. The default is the
  sign-in (or the key) for a limit or sign-in problem, else try again. The sign-in is `claude auth login` on the
  person's terminal, as step 2 runs it; ade reads no token and refuses it in an agent session.
- Go on without the test: only the everything agent, and not GLM or Muse. Recorded as chosen (`HUB_ROOT_PROVIDER`,
  the connections record) and as not tested (`HUB_PROVIDERS_UNTESTED`), and left out of `HUB_PROVIDERS_ALLOWED`: the
  hub has one list and no notion of "tested", so staying out of the list is what keeps focus agents off it (A5).
  `ade setup --test` now writes when, and only when, that provider passes (it was read-only before).
- `gh repo create` and `bin/init` ask nothing, so their output is captured (`run_logged`): shown when they work, kept
  in `~/.config/ade/last-failure` when they fail. A folder a failed `gh repo create` left behind is removed (it was
  not there before the try); a failed `bin/init` keeps the clone and its `.git/ade-hub-new` mark, as before.
- The hub's first version (owner, the same evening: the hub's repository still showed the template's README):
  `hub_first_save` runs the hub's own `bin/sync --yes` after `bin/init`. `bin/sync --yes` only warns when gitleaks
  is missing, so `ade` checks for gitleaks and the hooks path itself and does not commit without them. Two things
  belong to ade-brain and are not changed here: `bin/sync` does not list `hub.conf`, so it stays untracked; and a hub
  made by `bin/init` without `ade` is still left uncommitted (the first save would sit better at the end of
  `bin/init`). gitleaks is not among the tools `ade setup --tools` installs, so on a new machine the first save is
  skipped with its line until gitleaks is there.
- Ctrl-C at the question: an INT trap for the length of the question prints the line and exits 130 (checked on bash
  3.2 and 5). Elsewhere Ctrl-C is as before.
- Left out, on purpose: refusals that are not failures (an agent session, no terminal, a non-https installer, a
  declined install); `mkdir`, `hub.conf` and `~/.config/ade` write errors and a template without `bin/init` (nothing
  the person can retry from a menu); the optional tools step (`setup_tools_steps`), which already goes on;
  `--no-github` (tests and scripts); `ade restore`'s own live test line.
