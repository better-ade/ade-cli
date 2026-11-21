# A13: `ade key`: the local key store, with the clipboard as the only way in and out

Status: Ready for development (2026-11-21). Risk: high (secrets). Depends on A1; the hub's bin/keys and bin/secret
(Keychain on macOS; pass or the 0600 file store on Linux, V1). Owner's intent (2026-11-21): a local store for sensitive
keys, and the clipboard to move a key from the store to the command that needs it.
Verification command: `bash tests/run.sh`.

## Goal
```
ade key list                         names, where each is used, stored or missing; never a value
ade key set <name> --clipboard       read the value from the clipboard into the store, then clear the clipboard
ade key copy <name> [--for N]        put the value on the clipboard, cleared after N seconds (default 20)
ade key forget <name>
```
- Values never appear on screen, in argv, in the environment, in a log, or in shell history. They move store →
  clipboard (pbcopy / `wl-copy` / `xclip`) by stdin, and clipboard → store (pbpaste / `wl-paste` / `xclip -o`) by stdin
  into `bin/keys set` / `bin/secret --set`.
- **Auto-clear:** a detached timer clears the clipboard after N seconds only if it still holds that value (compared by
  hash, never stored).
- **Concealed on macOS:** the value is written with the `org.nspasteboard.ConcealedType` marker (through a tiny
  python3/osascript helper), so clipboard managers skip it and Universal Clipboard does not sync it.
- **Owner only:** `copy` refuses without a TTY; the hub's permission rules gain `ask` for `Bash(*ade key copy*)` and
  `Bash(*bin/secret --get*)`-style reads, so an agent's attempt needs the owner's yes. Agents never read the clipboard
  for a key.
- **Remote:** over SSH without a local clipboard, `copy` refuses and explains (no OSC 52, no printing).
- `ade setup` (A5) and `ade restore` (A10) offer `--clipboard` as the alternative to the hidden prompt.

## Acceptance criteria (`tests/test_key.sh`; fake clipboard tools that record stdin and argv; fake bin/keys)
| AC | Criterion |
|---|---|
| 1 | `list` shows names and states only; a test scans its output for the fixture values |
| 2 | `set --clipboard` passes the value to `bin/keys set` on stdin only, then clears the clipboard |
| 3 | `copy` writes the value to the clipboard on stdin only; it is in no argv, env, log or file (fakes record all) |
| 4 | The clear runs after N seconds and leaves the clipboard alone when it changed in the meantime |
| 5 | On macOS the concealed marker is set (the helper is called with it) |
| 6 | `copy` refuses without a TTY and over SSH without a local clipboard, never printing the value |
| 7 | The hub settings template asks before `ade key copy` and secret reads (permission rules present) |
| 8 | `setup` and `restore` accept `--clipboard` for every key they ask for |
