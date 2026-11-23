# A20 design note: `ade shot`

Risk: high (a capture can hold private data; `--tg` sends it out). One bash surface (`cmd_shot`, the screen gate, the
capture tools, tmux, the hub's `bin/chat`) and one Python helper, `shot_py`, run with `python3 -I -c` and the standard
library only.

- **Chromium is found the hub's way** (`browser_chromium` in the hub's `bin/lib.sh`): Playwright's own build under
  `PLAYWRIGHT_BROWSERS_PATH`, else `~/.cache/ms-playwright`, `~/Library/Caches/ms-playwright` (macOS) and
  `/opt/ms-playwright` (the ADE Computer), the newest revision; its headless shell counts, a system browser does not.
  ade downloads nothing: when it is missing, one line names `npx -y @playwright/mcp install-browser chromium` and the
  hub's `bin/server install`. `ade doctor` lists it; `ade setup --tools` does not install it.
- **The DevTools pipe, not `--screenshot`.** Chromium runs headless with `--remote-debugging-pipe` (JSON messages on
  fd 3 and 4): no port is opened, the address is never an argument of a process, and ade can do what the
  `--screenshot` flag cannot: capture the whole page (`Page.getLayoutMetrics`, then a clip beyond the window), read
  the document's HTTP status for the sidecar, and hold every request the page makes (`Fetch.enable`) so a page cannot
  pull a file from outside the project into the picture. A throwaway profile in ade's own temp folder; the sandbox
  stays on except where Chromium cannot make a user namespace (a container) or runs as root, as the ADE Computer's
  wrapper decides. The browser is in its own session and is killed on every path, a timeout or Ctrl-C included.
- **A terminal shot is HTML rendered by the same Chromium, not a hand-made PNG renderer.** A renderer in the standard
  library would need a bitmap font inside `ade` and would draw ASCII only; agent sessions are full of box-drawing
  characters, symbols and non-Latin text. Chromium is already the hub's browser and draws any glyph with the machine's
  fonts. The cost: an agent shot needs Chromium too. The page is made by ade: text is HTML-escaped, colours are
  `#rrggbb` values ade computes from the colour sequences (nothing from the pane is copied into a style), and a
  Content-Security-Policy of `default-src 'none'` lets it load and run nothing.
- **Redaction happens on text, before any pixel.** Escape sequences are parsed out first (so one cannot split a key),
  then the hub's rule (`bin/agent.py`: bot tokens, `<id>.<secret>` keys, `sk-` keys, runs of 32 or more) and the
  additions of A19 run on each line; styles are carried across the replacements. `tmux capture-pane -J` joins lines
  tmux wrapped, so a key tmux wrapped is one line again. A key the program itself printed on two lines can be missed;
  the help says so.
- **The screen gate.** A person at a terminal answers a question (`tty_confirm`, A9). An agent cannot answer for the
  person, so from an agent session the approval is the session's own permission prompt for this command:
  `--yes-screen` says the caller knows what it captures, and ade checks that the nearest `.claude/settings.json` (the
  working folder or above) has a `permissions.ask` rule matching `ade shot screen --yes-screen` and does not set
  `bypassPermissions`. ade cannot see the prompt itself; it checks that the rule that makes it is there. The hub's
  root and focus folder settings carry the rule (ade-brain, `.ade/context/chat.md`).
  Known limit: a session started with a command-line flag that skips permissions shows no prompt and ade cannot
  tell; the hub never starts one (`ade claude` and the hub's `bin/chat` refuse the flag).
- **Evidence is private by default.** `.ade/evidence/` is 0700 and gets a `.gitignore` holding `*`: a picture of a
  screen is not committed by an `add -A`. To commit a shot as the record of a story, `git add -f` it.
- **`--tg`** never talks to Telegram: it runs the hub's `bin/chat send <file>` with the caption on stdin, after
  `bin/chat status` says `locked to you`. The hub re-checks the lock and owns the token.
- **Checked against a real browser once, by hand** (the builder's machine, Playwright's Chromium, a local file page
  and a fake tmux; never the network or a real screen): the pipe, the full-page clip, the request check (an `<img>`
  and an `<iframe>` of files outside the project were stopped) and the terminal page all worked. The suite uses a
  stand-in Chromium only. Not run for real: `screencapture`, `import`, `xwd`, Telegram.
- **Left out:** Wayland, one window or a region, installing Chromium, blurring a picture, a retry of a failed send.
