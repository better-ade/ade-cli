# A14: `ade vault`: a local password manager in the terminal

Status: Ready for development (2026-11-21). Risk: high (secrets). Depends on A13 (ade key, clipboard), A10 (connections
record). Owner's intent (2026-11-21): "an interface on the terminal to put a key in", "like a local 1Password".
Verification command: `bash tests/run.sh`.

## Goal
`ade vault` opens a full-screen terminal interface over the hub's key store (Keychain on macOS; on Linux the file
store, now encrypted):
- **List and search** keys: name, kind (API key, bot token, password, OAuth sign-in), used by (from
  `.ade/connections.json`), last rotated; values are never shown in the list.
- **Add:** paste from the clipboard (then cleared), a hidden prompt, or generate a strong random secret (length and
  alphabet chosen per kind).
- **Copy** (↵): to the clipboard, concealed, cleared after 20 s (A13).
- **Rotate:** store the new value, run that provider's live test (A5), keep the old value only until the new one
  passes, then drop it; journal "rotated <name>" (never the value).
- **Reveal:** off by default (`HUB_VAULT_REVEAL=1` enables); asks to confirm, shows the value for 10 s, then clears the
  screen region.
- **Edit notes**, **delete** (typing the name), and **reminders** for keys older than the rotation age
  (`HUB_VAULT_ROTATE_DAYS`, default 90; `ade` mentions due keys once a week).
- **Lock:** macOS relies on the Keychain (login unlock); on Linux values are encrypted with `age` and a passphrase,
  unlocked per session through a short-lived agent and auto-locked after 5 idle minutes; `ade vault lock` locks now.
- **Owner only:** needs a TTY; the hub's permission rules ask before any vault command run by an agent.
- Metadata (kind, notes, rotated dates) lives in the hub's state folder, never in the repo; names stay in
  `.ade/connections.json` (A10).

## Acceptance criteria (`tests/test_vault.sh`, driven through tmux send-keys and capture-pane; fake stores)
| AC | Criterion |
|---|---|
| 1 | The list shows names, kinds, used-by and age, and no fixture value appears anywhere on screen (capture scan) |
| 2 | Add by clipboard, hidden prompt and generate each store the value through stdin only; generate meets the length and alphabet rules |
| 3 | Copy puts the value on the clipboard (A13 path) and nothing else; reveal is impossible unless enabled, and then times out |
| 4 | Rotate keeps the old value when the live test fails, drops it when it passes, and journals without the value |
| 5 | Delete requires typing the name |
| 6 | On Linux the file store is age-encrypted; a locked vault refuses copy and reveal until unlocked; it auto-locks after the idle time |
| 7 | Due-rotation reminders appear in the list and once a week in `ade` |
| 8 | Without a TTY the vault refuses; the settings template asks before vault commands from agents |
