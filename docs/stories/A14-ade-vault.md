# A14: `ade vault`, the terminal vault, through ade-secrets

Status: Ready for development (2026-11-22; rewritten). Risk: high (secrets). Depends on A13. Owner's intent
(2026-11-21): "an interface on the terminal to put a key in", "like a local 1Password". Verification command:
`bash tests/run.sh`.

## What changed since this story was first written
The vault itself (list and search, add, copy, rotate behind a live test, notes, typed-name delete, reminders, lock,
an opt-in timed reveal) is built in **ade-secrets** v0.3.0 as `ade-secrets vault`. This story only opens it from
`ade`. Nothing here draws, reads or holds a value.

## Acceptance criteria (`tests/test_vault.sh`; a fake `ade-secrets`)
| AC | Criterion | Test |
|---|---|---|
| 1 | `ade vault` runs `ade-secrets vault` with the person's terminal attached; `ade vault lock` and `ade vault unlock` run the matching commands; exit codes come through | `vault_delegates` |
| 2 | Without a terminal, and inside an agent session, `ade vault` is refused before `ade-secrets` is called | `vault_terminal_only` |
| 3 | In `ade ui`, one key opens the vault in a popup that closes when the vault exits; `ade` never captures that popup's contents (no screen capture of it, nothing of it in `ade dash` or a log), and the help popup lists the key | `vault_popup` |
| 4 | `ade` alone mentions keys due for rotation at most once a week, by name only, when ade-secrets offers a names-only way to ask; if it does not, the reminder is left out and the story says what ade-secrets would need | `vault_reminder` |
| 5 | README, the help text and CHANGELOG describe `ade key` and `ade vault` in plain words, and say the Owner check in ade-secrets' contract should be done before a real key is stored | `vault_docs` |
