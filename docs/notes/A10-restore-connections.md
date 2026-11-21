# A10 design note: connections record and ade restore

- One embedded python3 block (`conn_py`) reads and writes `<folder>/.ade/connections.json` (atomic rename, sorted keys,
  tabs and newlines stripped from values). Writers: `ade setup` (top, focus, account, services, Telegram), `skills add`
  (marketplace, plugin, ade-skills pin), `agent add` (specialist, registry pin), `init` (method pin), `orchestrator new
  --channel` and `ade chat setup <channel>` (channel, bot name from `bin/chat info`).
- The account is a fingerprint (16 hex of a sha256 of organisation and user id) plus a label (`account-<6 hex>` by
  default; `ade restore --label`). The email and ids are never stored.
- `conn_state` gives one line per connection: ready, missing, different or unknown (channels other than Telegram, and
  Gemini account sign-in, cannot be checked here). `--check` prints them and exits 1 on a gap; it runs no live test.
- `ade restore` lists the gaps, then asks one yes per gap in record order: account (c/s), Claude sign-in, keys (hidden
  prompt through `store_key`, then `live_test`; a failed test drops the provider from `HUB_PROVIDERS_ALLOWED`),
  plugins (with their marketplace), Telegram (hidden token to `bin/keys set telegram`, then `bin/chat setup telegram
  --repair`), services (one `bin/schedule install`). Each ends ready, skipped or failed; the rest goes in "still needs
  you"; one journal line.
- The account gate runs in `work`, `dispatch`, `agent-run`, `claude` and `orchestrator start`, only when the record
  has a fingerprint. No answer (or EOF): exit 2.
- Plugin versions: Claude Code installs a marketplace's current plugin; ade checks that the recorded ref is still a
  tag of the marketplace repo and warns that it installs the latest when it is not. Pinning the plugin itself to the
  old ref is left to Claude Code.
- Left out (not in the acceptance criteria): MCP servers, the ticket store and role models in the record.

## Fix round (2026-11-22, after the adversarial review)
- `conn_py` checks the whole record on every read and before every write (`check`): `format` 1, known keys only, no
  duplicate keys, 64 KiB and 64 entries at most; names `^[a-z0-9][a-z0-9._-]{0,63}$`, refs `^v<n>.<n>.<n>$`, repos
  `https://github.com/<owner>/<repo>`, `<owner>/<repo>` or `local` (the built-in ade-skills only), a label as `--label`
  takes, a 16-hex fingerprint, `@bot` names, services chat|monitor|sync. `get` prints US (0x1f) separated fields, so an
  empty field never shifts the rest. A write that would not pass the check is refused ("not recorded"), so what ade
  writes, ade reads.
- `ade-skills` bound to anything but this machine's `ADE_SKILLS_REPO` rejects the record. Another marketplace is shown
  with its repo and needs its name typed back. `git ls-remote ... -- <url>`, `claude plugin marketplace add -- <src>`,
  `claude plugin install --scope project -- <name@marketplace>`.
- Versions: a GitHub marketplace is added as `https://github.com/<owner>/<repo>.git#<ref>` when the tag is published
  (Claude Code's git-URL ref form); a local one cannot take a ref. Either way the installed version is read back from
  `installed_plugins.json` (the entry for that folder) and anything but the recorded ref is "different".
- Project records: the hub's `projects/*` and `ops/*` folders and the git checkouts their `ACCESS.md` lists; only their
  plugins (and marketplaces) are restored, in their own folder. A bad project record fails the whole restore.
- `restore` (when there is a gap) and the gate use A9's terminal path. With no gap, `restore` asks nothing and needs no
  terminal (a default: nothing changes then).
- Smaller: `hub_claude` runs claude with `HUB_CLAUDE_CONFIG_DIR` (sign-in, status, plugins); `key_stored`,
  `drop_role` and the marketplace check compare whole names (no pattern built from a record value); error messages
  carry no record value and paths are printed without control characters.
- `pty_run` moved to `tests/helpers.sh` and types with the terminal's echo off, so a typed key never shows in a
  transcript the tests scan.
