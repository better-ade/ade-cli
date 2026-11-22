# A13: `ade key`, the local key store, through ade-secrets

Status: Ready for development (2026-11-22; rewritten). Risk: high (secrets). Depends on A1, on ade-secrets v0.3.0 and
on ade-brain H2 (the hub's `bin/secret` delegating to ade-secrets). Owner's intent (2026-11-21): a local store for
sensitive keys, and the clipboard to move a key from the store to the command that needs it. Owner, 2026-11-22:
"ok le'ts build A13, a14, a16" and "a17". Verification command: `bash tests/run.sh`.

## What changed since this story was first written
The store, the clipboard handling (concealed, cleared when unchanged) and the terminal-only rules were built in their
own repo, **ade-secrets** (released v0.3.0), so that no secret code runs inside `ade` or an agent session. This story
is now thin: `ade key` runs `ade-secrets`. Nothing here reads, holds or prints a value. The contract is ade-secrets'
`docs/contract.md`; where this story and it differ, the contract wins: stop and say so.

## Goal
```
ade key list                         names and where each is used; never a value
ade key set <name> [--clipboard]     hidden prompt, or from the clipboard (then cleared)
ade key copy <name> [--for N]        to the clipboard, cleared after N seconds if unchanged
ade key forget <name>
ade key status
```

## Acceptance criteria (`tests/test_key.sh`; a fake `ade-secrets` that records its arguments and standard input)
| AC | Criterion | Test |
|---|---|---|
| 1 | Each `ade key` command runs the matching `ade-secrets` command with the person's terminal attached; `ade` captures none of its output and passes names as data (the contract's name rule; a name starting with `-` is refused before anything runs) | `key_delegates` |
| 2 | `ade-secrets`' exit codes come through unchanged, and `ade` adds one plain line for 3 (run this in your own terminal), 4 (no clipboard here) and 5 (the store is locked) | `key_exit_codes` |
| 3 | Without a terminal, and inside an agent session, every `ade key` command is refused before `ade-secrets` is called | `key_terminal_only` |
| 4 | `ade setup` (and `ade setup --tools`) installs ade-secrets at a pinned tag (`ADE_SECRETS_REF`), after a yes, checking each installed file against that release's `release.json`; if that release does not list a file `ade` would install, nothing is installed and the story stops for a release change in ade-secrets | `key_install_pinned` |
| 5 | With ade-secrets missing, `ade key` prints one line saying how to get it and exits 2 | `key_missing_tool` |
| 6 | `ade` never sets or changes the store by itself: the first `ade key set` asks which store to use (Keychain on macOS by default; `pass` or `age` on Linux) and lets ade-secrets record it | `key_store_choice` |
| 7 | `ade setup --check` and `ade doctor` print `secrets: ade-secrets <version>, store <name>`, or say the hub still uses its built-in store or lacks the permission rules H2 ships, with what to run; never a value | `key_doctor` |
| 8 | `ade setup` and `ade restore` use `ade key set <name>` for every key they ask for when the hub delegates (H2), offering `--clipboard`; otherwise they keep today's `bin/keys set` path | `key_setup_restore` |
| 9 | The hostile-input table gains `ade key` (names with spaces, newlines, control characters, `..`, a leading `-`, 65 characters) | `key_hostile` |

## Out of scope
Any store, clipboard or encryption code in `ade`. Moving keys from the hub's old store (the person re-enters them).
