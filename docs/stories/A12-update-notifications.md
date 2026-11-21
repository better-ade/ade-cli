# A12: release manifests and update notifications

Status: Ready for development (2026-11-21). Risk: medium. Depends on A11. Owner's intent (2026-11-21): notify users when
there is a new version, through a JSON file that `ade` checks.

## Goal
1. **better-ade/.github `release.yml`** (shared CD) attaches `release.json` to every release: `component`, `version`,
   `released`, `notes_url`, `summary` (first line of the CHANGELOG section), `urgency` (`normal` unless the section has
   a `Security:` line → `security`), `min_supported` (from an optional `MIN_SUPPORTED` file), and `files` with the URL
   and `sha256` of each release asset. Every better-ade repo gets it with no change of its own.
2. **`ade`** checks `https://github.com/better-ade/<repo>/releases/latest/download/release.json` once a day per
   component in use (ade-cli, ade-brain, ade-method, ade-skills, ade-agent-registry), with a stamp file and an ETag
   cache; offline means try tomorrow. It notifies **once per new version**: a banner on the next `ade` command, a badge
   in `ade ui`'s tab bar, and one Telegram line through the orchestrator when a channel is set up. `security` urgency
   repeats on every command until updated. `ADE_NO_UPDATE_CHECK=1` turns it off.
3. **`ade update`** (A11) installs a file only when its sha256 matches the manifest; a mismatch refuses and says so.
   The one-line installer (A3) checks the same sha256.

## Acceptance criteria (fake release server folder, no network)
| AC | Criterion |
|---|---|
| 1 | The release workflow produces a valid `release.json` with the fields above and correct sha256 values (a workflow test job, plus a local script test) |
| 2 | `ade` checks at most once a day per component and notifies once per new version (banner), never for the installed or an older version |
| 3 | `security` urgency shows the banner on every command until updated |
| 4 | `ade ui` shows the badge; the orchestrator gets one Telegram line per new version when a channel exists |
| 5 | A sha256 mismatch makes `ade update` and the installer refuse and keep the old version |
| 6 | Offline, a 404 or a malformed manifest never blocks or slows a command by more than 2 s, and is retried tomorrow |
| 7 | `ADE_NO_UPDATE_CHECK=1` makes no request |
