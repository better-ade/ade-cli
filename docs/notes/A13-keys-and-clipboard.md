# A13 design note: `ade key`, through ade-secrets

- The contract is ade-secrets v0.3.0 `docs/contract.md` (v1). `ade` has no store, clipboard or encryption code: each
  `ade key` command checks its words, then runs the matching `ade-secrets` command as a child with stdin, stdout and
  stderr left as they are (the person's terminal); nothing is captured or piped. The exit code is returned unchanged;
  for 3, 4 and 5 `ade` adds one plain line on stderr after it.
- Names: the contract's rule `[A-Za-z0-9][A-Za-z0-9._-]{0,63}`, checked with `LC_ALL=C` before anything runs (exit 2;
  the refused text is never repeated, it may be a key typed in the wrong place). `--for` takes 1 to 4 digits;
  ade-secrets checks the range.
- Order of checks: usage and name (exit 2), ade-secrets on `PATH` (exit 2, one line: `ade setup --tools`), any of the
  contract's ten session variables (exit 3), stdin a terminal and `/dev/tty` openable (exit 3). Only then is
  ade-secrets called. Like ade-secrets' own check, this stops accidents; it is not a wall. An agent running as you can
  get round it (unset the variables, or start a terminal without them) and reach `ade key`; a key it copies to the
  clipboard can then be read by other means. What holds is the macOS dialog on every read of an entry not marked for
  the key helper, and reading every dialog before you allow it (ade-secrets' `docs/contract.md`, "Residual risk").
- The store (AC6): before a `set`, with no `ADE_SECRETS_STORE` in the environment, `ade-secrets store` is run with its
  output discarded; exit 2 means none is recorded, and the person picks one at `/dev/tty` (macOS: Keychain, default,
  pass or age; Linux: pass, default, or age). That set runs with `ADE_SECRETS_STORE=<pick>` for that one command, and
  ade-secrets records it. `ade` never runs `ade-secrets store <name>`.
- Delegating hubs (AC8, ade-brain H2): a hub delegates when its `bin/secret` has a line starting
  `# >>> ade-secrets delegation`, ade-secrets is on `PATH` and `HUB_SECRETS` is not `builtin` (the block's own
  condition). Then `ade setup` and `ade restore`, for Claude Code's own keys (see the fix round), offer a
  hidden prompt, the clipboard, or skip, and run `ade-secrets set <name> [--clipboard] --helper --kind api-key
  --used-by hub` (the flags the contract's `bin/secret --set` uses, so the hub's key helper can read the entry). The
  name is the third column of the tool's row in the hub's `bin/keys` (for example `deepseek-api-key`), else the tool
  name. Other hubs keep the `bin/keys set <tool>` path, the value on its stdin.
- Install (AC4): `ade setup` and `ade setup --tools` offer ade-secrets at `ADE_SECRETS_REF` (default `v0.3.0`, a
  `vX.Y.Z` tag only) after a yes at a terminal (never in an agent session), read that tag's `release.json` and check
  it with A12's `manifest_py` (component `ade-secrets`, that version, a sha256 per file). **The v0.3.0 release lists
  no files (`"files": []`)**, so nothing is installed and the criterion stops there, as the story says. What
  ade-secrets needs to publish: a release whose `release.yml` passes `assets: bin/ade-secrets lib/vault.sh`, so its
  `release.json` names `ade-secrets` and `vault.sh` with their sha256. Then a follow-up moves `ADE_SECRETS_REF` and
  builds the download, compare and install step; until then even a release that lists both files is not installed
  ("this ade does not install them yet").
- Doctor (AC7): `ade doctor` and `ade setup --check` print `secrets: ade-secrets <version>, store <name>` from
  `ade-secrets version` and `ade-secrets store` (a store name only); without a terminal or in a session the store is
  "unknown here". Then, for the hub: built-in store (no block, or `HUB_SECRETS=builtin`), and any of the rules of
  ade-secrets' `docs/claude-settings.json` missing from the hub's `.claude/settings.json`, each with what to run.
- Tests: `tests/test_key.sh`, a fake ade-secrets that records its arguments, whether stdin and stdout are a terminal,
  and anything piped to it; terminals through `pty_run`. Never the real tool, Keychain or a clipboard tool.

## Fix round (2026-11-22, after the adversarial review)
- One list of Claude Code's session markers, `AGENT_SESSION_VARS` (one line in `ade`): `agent_context` (reset,
  uninstall, restore, the file viewer, installs) and the key checks both use it; `tests/helpers.sh` reads the same line
  and `fresh()` unsets all ten.
- ade-secrets is found once per run (`secrets_find`) as an absolute path and every call uses that path. A copy whose
  folder (or, for a link, its target's folder) lies under the current folder, the hub, or any git work tree is refused
  with one line naming the file and why. The current folder does not count when it is the home folder or above it
  (a person's terminal usually starts there). A clone of ade-secrets used in place is therefore refused; an install
  outside any work tree is needed.
- Hub keys: `HUB_KEY_USERS` in `ade` says who uses each key ade setup asks for. Only Claude Code's own keys
  (anthropic, deepseek, glm, muse) are stored as helper entries, after one sentence saying Claude Code and anything it
  runs can read them without a dialog. The Telegram token (bin/chat) and the Gemini API key (the Gemini CLI) are not
  stored in ade-secrets on a delegating hub: one line says the hub's built-in store handles them, until the contract
  gives other consumers their own mark. The checks run before the hub's `bin/keys` is asked for the key's name, and
  that name is used only when its row has exactly three words and the third follows the name rule.
- `ade doctor` and `ade setup --check` do not call `ade-secrets store` when `${ADE_SECRETS_HOME:-~/.ade-secrets}` does
  not exist (that command creates it): they say "none chosen yet".
- `--for` is checked as 1 to 3600 before the tool runs.
- **Requirement on the install follow-up:** when the download and install step is built, it must ignore
  `ADE_RELEASES_BASE` outside tests (or show the host in the yes/no question), so an environment variable cannot point
  the install at another server.
