# A14 design note: `ade vault`, through ade-secrets

- `ade vault` runs `ade-secrets vault`; `ade vault lock` and `ade vault unlock` run `ade-secrets lock` and
  `ade-secrets unlock` (the contract's commands: the vault itself takes no arguments). They use A13's path: the same
  checks before anything runs (ade-secrets installed, exit 2; no session variable and a terminal, exit 3), then
  ade-secrets as a child with the terminal attached, nothing captured, its exit code unchanged (A13's plain line for 3,
  4 and 5). Any other word is refused (exit 2).
- `ade ui`: `prefix v` is `display-popup -E -w 90% -h 90% "<ade> vault"`, so the popup closes when the vault exits.
  The popup is not a pane: ade's one `capture-pane` is the links key's (`-t <pane id>`, checked `^%[0-9]+$`), so the
  vault's screen is never captured, never in `ade dash` and never in a log; no `pipe-pane` anywhere. The help popup
  (`prefix ?`) lists the key; its golden screens (`tests/golden/ui-120x36-help.txt`, `ui-80x24-help.txt`) were
  recaptured for that one line. No golden screen of the vault popup is taken: the test suite does not capture it either.
- Reminder (AC4): ade-secrets v0.3.0 has **no names-only way to ask which keys are due** for rotation. Its due rule
  (`ADE_SECRETS_ROTATE_DAYS`, default 90) lives only inside the full-screen vault (`lib/vault.sh`, the `rotate:` line);
  `ade-secrets list` prints a table (kind, used-by, age, helper), and `list --names` all names. Parsing `list`'s AGE
  column would copy the rule into `ade`, so the reminder is left out: `ade` alone calls nothing of ade-secrets. What
  ade-secrets would need: a command such as `ade-secrets list --due` that prints one name per line for the entries
  past `ADE_SECRETS_ROTATE_DAYS` (nothing else, exit 0, guarded like `list`), recorded in its contract. Then `ade`
  alone can mention them by name at most once a week (a stamp in `~/.config/ade/`).
- Docs: README (a section and two rows of the command reference), the help text and CHANGELOG describe `ade key` and
  `ade vault` in plain words and say the Owner check in ade-secrets' `docs/contract.md` comes before a real key.
