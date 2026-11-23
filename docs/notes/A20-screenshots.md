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
  characters that draw nothing (soft hyphen, grapheme joiner, zero-width and other default-ignorable ones)
  are removed, then the hub's rule (`bin/agent.py`: bot tokens, `<id>.<secret>` keys, `sk-` keys, runs of 32 or more) and the
  additions of A19 and `Cookie:` / `Set-Cookie:` values run on each line; styles are carried across the replacements. `tmux capture-pane -J` joins lines
  tmux wrapped, so a key tmux wrapped is one line again. A key the program itself printed on two lines can be missed;
  the help says so.
- **The screen gate.** A person at a terminal answers a question (`tty_confirm`, A9); `--yes-screen` answers nothing
  there. An agent cannot answer for the person, so from an agent session (any of six variables Claude Code sets, so
  removing the usual three and making a pseudo-terminal changes nothing) the approval is the session's own permission
  prompt for this command. ade cannot see that prompt; `shot_py asks` checks what makes it appear:
  - the session's project is `CLAUDE_PROJECT_DIR` when the session sets it, else the git or hub root ade saves into;
    never the shell's current folder, a folder below it or one above (an agent can make a folder with its own
    settings and enter it);
  - no settings file may let the session skip permissions: the project's `.claude/settings.json` and
    `settings.local.json`, the user's `settings.json` (`CLAUDE_CONFIG_DIR`, else `~/.claude`) and the managed settings
    of this system; a `defaultMode` of `bypassPermissions` in any, or one that cannot be read, refuses;
  - one `permissions.ask` rule of the project's or the user's must match the command line as ade got it
    (`ade shot screen --yes-screen ...`): a wildcard rule, a `:*` prefix rule, or an exact rule for exactly that command.
  The hub's root and focus folder settings carry `Bash(*ade shot screen*)` (ade-brain, `.ade/context/chat.md`).
  Known limits: a session started with a command-line flag that skips permissions shows no prompt and ade cannot tell
  (the hub never starts one); without `CLAUDE_PROJECT_DIR` (Claude Code sets it for hooks, not for the Bash tool
  today) an agent that makes a new git repository with its own ask rule and enters it passes ade's check, and only
  the session's real rule, which matches the text of that command too, prompts.
- **What a page may load.** Besides files outside the project, a page never gets a `.env`, a key (`*.pem`, `*.key`,
  `id_*`) or anything under `.git/` of the project (the files the hub's `bin/chat send` never sends), nor a
  link-local or metadata address (169.254.0.0/16, `fe80::/10`, `fd00:ec2::254`, `metadata.google.internal`, also
  IPv4-mapped); such an address or file as the page itself is refused before a browser starts. Chromium reports
  each request with its canonical address, so `http://2852039166/` is seen as 169.254.169.254. A name that resolves
  to such an address is not caught. The sidecar counts what was stopped, by kind.
- **Saving.** Each level (`.ade`, `evidence`, the day) is made and then opened from its parent's descriptor with
  `O_NOFOLLOW`; the PNG, the sidecar and the `.gitignore` are created through those descriptors with `O_EXCL`. No
  level can be swapped for a link between a check and a write.
- **Evidence is private by default.** `.ade/evidence/` is 0700 and gets a `.gitignore` holding `*`: a picture of a
  screen is not committed by an `add -A`. To commit a shot as the record of a story, `git add -f` it.
- **`--tg`** never talks to Telegram: it runs the hub's `bin/chat send <file>` with the caption on stdin, after
  `bin/chat status` says `locked to you`. The hub re-checks the lock and owns the token.
- **Checked against a real browser once, by hand** (the builder's machine, Playwright's Chromium, a local file page
  and a fake tmux; never the network or a real screen): the pipe, the full-page clip, the request check (an `<img>`
  and an `<iframe>` of files outside the project were stopped) and the terminal page all worked. The suite uses a
  stand-in Chromium only. Not run for real: `screencapture`, `import`, `xwd`, Telegram.
- **Left out:** Wayland, one window or a region, installing Chromium, blurring a picture, a retry of a failed send.
