# A18 design note: the guided first run

- `ade setup` (no flags) is the guide: `guide` lists `GUIDE_STEPS` with `guide_state` (the state alone decides a
  step is done; nothing is recorded), then for each step not done prints `Step n of 6`, `guide_about`, runs
  `guide_run` and prints `guide_checked`. A step that cannot finish stops ade with one line naming `ade setup`.
  `ade` with no hub prints the same list and, at a terminal and outside an agent session, offers it.
- Order: claude-code, claude-sign-in, github, hub, project, telegram. The provider choices (A5's `setup_top` and
  `setup_focus`) run inside the hub step, because they write the hub. The project step runs the guided session as a
  child (it was the last `exec`), so the guide can check for a project and then offer Telegram. Optional steps are
  offered only in a run that did a required step, so a finished guide run again says "All set" and asks nothing.
  A16 adds `tools` after `hub` in `GUIDE_STEPS`, with its title, state, about and run in the four `case`s.
- One way of asking: `ask_text` (free text) and `ask_choice` (numbered choices; `ASK_INLINE` for yes/no, `ASK_MULTI`
  for the focus providers). `ask`, `yes_no`, `confirm`, `tty_ask` and `tty_confirm` are thin wrappers that set
  `ASK_TTY`, `ASK_EOF` and `ASK_EMPTY_OK` with `local`; a typed-back name (reset, restore) still treats Enter as no.
  Answers with control characters, escape sequences, a leading `-` or over 200 characters are asked again.
- GitHub: `github_ready` (the guide's step and `ade hub new`) installs `gh` through `tools_install` (A15's rules),
  explains in two lines, refuses without a terminal or in an agent session, then runs `gh auth login --hostname
  github.com --git-protocol https --web` with the terminal attached. In an ADE Computer gh's output goes through a
  small relay (stdin stays the terminal) that repeats the one-time code in block letters; `GH_BROWSER` is `xdg-open`
  after a yes with `DISPLAY` set, else `true`.
- `ade hub new` asks after the clone, so the persona list comes from the hub's own `bin/init --list`; a flag that
  is not a persona is asked again. `.git/ade-hub-new` marks a clone whose `bin/init` has not finished; running the
  same command again (or the guide's hub step) picks it up without a second `gh repo create`.
- The update banner is built to fit 80 columns and drops the release summary (Telegram keeps it).
- Fix round (review of PR #43): the display text says each term in plain words (no command, flag or key renamed);
  the second refused empty answer at a question that cannot be skipped adds one hint (`ask_empty`: Ctrl-C leaves, the
  command in `ASK_AGAIN` picks up); a guided session that exits non-zero is said in one line and the guide still ends
  at "Not finished: step 5"; plain `ade setup` refuses inside an agent session, its flags keep their own rules.
