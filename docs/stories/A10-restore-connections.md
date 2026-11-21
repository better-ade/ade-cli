# A10: remember connections, restore them anywhere

Status: In review (2026-11-21). Risk: high (credentials, accounts). Depends on A5 (setup), A7 (skills).
Owner's intent (2026-11-21): if the user switches Claude account, `ade` asks for new connections before proceeding; the
project's state is saved so that on a new device, after checking out the code, `ade` does its best to reinstate every
connection. Verification command: `bash tests/run.sh`.

## Goal
- **A connections record, committed, with no secrets:** `.ade/connections.json` in the hub (and in each project `ade
  init` touched) lists what this work depends on, by name only:
  - the everything agent's provider and model; each focus provider (with its sign-in kind: account or key);
  - channels (Telegram: bot username, never the token; the paired account's id is not stored either);
  - plugins and marketplaces (ade-skills plugins with versions); MCP servers and their sign-in kind (OAuth or key name);
  - ticket store (e.g. ClickUp: workspace and list names); specialists; ade-method and registry pins; role models;
  - the Claude account it was set up with, as a label the user chose plus a one-way fingerprint (a hash of the
    account's organisation id and user id), never the email or a token.
  `ade setup`, `ade skills add`, `ade agent add` and `bin/chat setup` update it; it is plain JSON, reviewed in PRs.
- **`ade restore`** (and automatically, as a check, before any `ade` command that needs a connection) compares the
  record with this machine and walks each gap, asking before each step:
  - **different Claude account** (fingerprint differs) or not signed in: stops and asks "this project was set up with
    `<label>`; continue with the current account and reconnect everything, or sign in to the recorded one?";
  - keys missing from this machine's secrets store: hidden prompt per key, then a live test;
  - plugins and marketplaces missing: reinstall at the recorded versions;
  - MCP servers needing OAuth: runs their sign-in; key-based ones: hidden prompt;
  - Telegram: the bot token (hidden prompt) and re-pairing, since pairing is per device and per account;
  - services (chat, monitor, sync): reinstalled for this platform (launchd or systemd).
  Each step ends ready, skipped (the user said no) or failed (with the reason); the summary lists what still needs
  the user. Nothing secret is ever written to the record, a log or the repo.

## Acceptance criteria (`tests/test_restore.sh`; fakes for claude, the secrets store, plugin install, launchctl/systemctl)
| AC | Criterion |
|---|---|
| 1 | `ade setup`, `skills add`, `agent add` and `chat setup` keep `.ade/connections.json` current; it never contains a key, token, email or Telegram account id (a test scans it for secret patterns and emails) |
| 2 | On a fresh machine (empty secrets store, no plugins, no services) `ade restore` lists every gap from the record and fixes each with the user's yes |
| 3 | A different Claude account (fingerprint mismatch) stops every connection-needing command with the question above until answered; the answer is remembered per machine |
| 4 | Keys are read with a hidden prompt, stored only through `bin/keys`, then live-tested; a failed test leaves the provider out of roles with the reason |
| 5 | Plugins return at the recorded versions; a version no longer published falls back to the latest with a warning |
| 6 | Telegram restore asks for the token and re-pairs; it never reuses another account's pairing |
| 7 | `ade restore --check` changes nothing and prints one line per connection: ready, missing or different |
| 8 | A second `ade restore` after a full restore finds nothing to do |
