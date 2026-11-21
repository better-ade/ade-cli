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
