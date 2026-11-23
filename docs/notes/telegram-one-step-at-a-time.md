# Design note: the guide's Telegram step, one step at a time

- Found by the owner on the released guide: the step asked for the token twice ("Bot token (hidden):", then the
  hub's "value for telegram-bot-token:"), printed the hub's seven manual steps (two already done) and ended as if
  Telegram were set up. Nothing ran, so the bot never answered. Asked: no loops, nothing twice, and an honest ending.
- Two prompts: the hub's `bin/secret --set` writes its prompt and "stored" line to stderr even when the value comes
  on stdin, and `ade` only hid stdout. `key_put` captures both; on a failure the hub's last line is shown with the
  value itself and key-shaped text hidden. `store_key` (the provider keys) uses it too.
- The wall: `bin/chat setup telegram` only prints. `ade setup` no longer calls it; it calls the hub's single
  commands and reads `bin/chat status`. `tg_left` names the first thing not done from the state alone, so a second
  run resumes there and prints nothing for what is done; nothing is recorded but `HUB_CHAT=telegram`, written when
  the hub's test passed (the hub needs it for `bin/schedule install` anyway).
- What a program can do, and what it cannot (checked in `claude plugin install --help` of Claude Code 2.1.330 and
  https://code.claude.com/docs/en/channels.md and discover-plugins.md): `claude plugin install <plugin> --scope user`
  exists ("install a plugin without starting a Claude Code session, for example from a setup script"), so `ade` runs
  it. Pairing and the allowlist are documented only as `/telegram:access pair <code>` and `/telegram:access policy
  allowlist` typed in the running session; no command-line form is documented, so those stay with the person. The
  hub starts a first session only at a terminal (without one it refuses an unpaired channel), and that session
  owns its terminal, so the person opens it in a second window and the guide stays in the first.
- The test: `bin/chat test` is refused while the session runs, so `ade` stops the session (`bin/chat stop`), runs
  the test (the bot writes to the owner, the owner replies), writes `HUB_CHAT=telegram`, runs `bin/schedule install`
  and waits for `bin/chat status` to say running. "Telegram is working" is printed only after all of that.
- bun: installed as the other tools are (`tools_install`, one yes at a terminal; Homebrew's own `bun` formula, so
  no third-party tap is needed). apt has no bun and ade pipes no installer from the network, so on Linux its page is
  named and the step waits. A failed install is said in one line from the installer's message, for every tool.
  (Since `docs/notes/install-bun.md`: bun is a required tool, installed from its own release, never by Homebrew.)
- Left for the hub (not changed here): see the pull request.

## Later change (2026-11-23): lock, then auto mode
- Owner's words: "i think if telegram is on, auto mode should be on?", then yes to: auto only once the bot is locked
  to an allowlist. Risk: high (who can act through the owner's agent without a question). The hub's `bin/chat` now
  picks `auto` only when the channel's `access.json` reads an allowlist with the owner's account and no groups.
- The rule lives in the hub alone. `ade` reads `bin/chat status` (`locked to you` / `not locked`, and the `mode:`
  line) and never the file. The guide's `allowlist` step was already before the test; it is now checked against the
  hub's lock, not the policy's name, so an allowlist with groups or with nobody in it is not "locked".
- No restart is needed on the usual path: `ade` stops the person's session for the test and `bin/schedule install`
  starts a new one, which starts in the new mode. Only a session that started before the lock needs one; `ade`
  restarts it when `bin/sessions` shows the main agent idle (as `ade update` does), and otherwise says what to type.
- The mode is explained only when the run did something, so `ade setup --telegram` on a finished hub stays one line.
- Tests: `tg_lock_then_auto` in `tests/test_telegram.sh`. The golden guide transcript answers no to Telegram, so it
  is unchanged.
