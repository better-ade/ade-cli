# A26: `ade keys` sets the missing keys for you

Status: **Approved** (owner, 2026-11-26: "make it easy for devs", option "one `ade keys` command"). Risk: **high**
(it is on the keys path; the rules make anything touching secrets high, whatever its size).
Verification: `bash tests/run.sh`.

## Today and the gap
`ade keys [args]` already runs the default hub's `bin/keys` from any folder (`run_hub`), so `ade keys set glm`,
`ade keys share`, `ade keys receive` work anywhere. But a developer still has to read the list, work out what is
missing and type one `set` per tool. `ade setup` asks for keys only during setup.

## Goal
- `ade keys` at a terminal: the hub's list as today, then, when any AI tool key is missing, one question
  "Set the missing keys now? (y/N)". On yes, each missing tool in turn with ade's hidden prompt (`store_key`: empty
  skips), then the list again. On no, or not a terminal (stdin or stdout not a TTY), the list alone, exactly as today.
- `ade keys --missing` asks for the missing ones without the question (still a terminal only; otherwise exit 2 with a
  one-line reason).
- Every other `ade keys <args>` is passed through unchanged.
- `ade help` and the README name `ade keys` as the one place for keys: list, set the missing ones, share, receive.

## Acceptance criteria (tests in `tests/` with a fake hub whose bin/keys logs its arguments and stdin length only)
1. **keys_guided_yes**: at a (fake) terminal with two tools missing, yes then two values: each is stored through the
   hub's `bin/keys set <tool>` on stdin, and the list is shown again.
2. **keys_guided_no_or_pipe**: answering no, or running with stdin or stdout not a terminal, prints the list only and
   asks nothing (byte-identical to the hub's output).
3. **keys_missing_flag**: `--missing` asks for each missing tool without the question; not at a terminal: exit 2.
4. **keys_skip_and_fail**: an empty answer skips that tool; a failed store says so (no value in the message) and moves on.
5. **keys_passthrough**: `ade keys set glm`, `share …`, `receive …` reach the hub's bin/keys with the same arguments.
6. **keys_no_value**: a value never appears in output, process arguments, the environment of anything ade starts, or
   files outside the fake store (the existing no-leak style in tests/test_hostile.sh or the keys tests).

## Out of scope
App secrets (.env replacement), changes to the hub's bin/keys, onboarding inside `ade hub import`.
