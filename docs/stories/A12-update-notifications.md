# A12: release manifests and update notifications

Status: In review (2026-11-22; fix round after the adversarial review); part 1 is better-ade/.github#3. Risk: high (raised
in the review round: it installs code on the user's machine without a prompt). Depends on A11. Owner's intent (2026-11-21): notify users when
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
3. **Auto-update (owner, 2026-11-21: "if there's a new version, push new"):** on the daily check, patch and minor
   versions are installed automatically through `ade update` (A11: atomic, sha256-verified, no session stopped), then
   one line says what was updated; `security` urgency installs at once; a major version or a version whose
   `min_supported` is above the installed one asks first. `ADE_NO_AUTO_UPDATE=1` keeps notify-only.
4. **`ade update`** (A11) installs a file only when its sha256 matches the manifest; a mismatch refuses and says so.
   The one-line installer (A3) checks the same sha256.
5. **Fail closed (review round):** from a hard-coded `MANIFEST_SINCE` (0.2.0, the first release with a manifest) a
   missing, unreadable or invalid manifest installs nothing, in `ade update`, the auto-update and `install.sh`, and
   the reason is shown whole. The manifest must be ade-cli's and for exactly the requested version; any `url` in it is
   ignored (the file always comes from its tag); a version lower than the installed one is refused (only
   `ade update --rollback` goes back). This proves integrity, not authenticity: the hash and the file come from the
   same release pipeline (residual risk; a signature or `gh attestation verify` is a later owner decision).
6. **Never in a command's way (review round):** the day's fetch runs in a detached job with one 2-second budget for
   every component; the next command reads the cached result. The auto-install runs in a detached job too, started
   only when a person runs `ade` at a terminal (never in an agent session); `ade update --auto on|off` is a persistent
   switch in `~/.config/ade` (default on, as the owner asked); `ADE_NO_AUTO_UPDATE=1` still works.

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
| 8 | Patch/minor auto-install after the daily check (then one line); security installs at once; major or min_supported jumps ask; `ADE_NO_AUTO_UPDATE=1` and `ade update --auto off` only notify; no install without a terminal or inside an agent session |
| 9 | From `MANIFEST_SINCE` on, a missing or invalid manifest installs nothing (`ade update`, auto-update, installer) and the reason is shown (`manifest_fail_closed`, `auto_update_failure_says_why`) |
| 10 | A manifest of another version or component is refused; its `url` is ignored; a lower version is refused (`manifest_bound`) |
| 11 | ade-cli's `release.yml` passes `assets: ade` (`release_workflow_passes_assets`); the manifest script refuses an empty file list when assets were named (better-ade/.github) |
| 12 | A stalled network with every component in use never delays a command; every request ends within the 2-second budget (`never_delays_a_command`) |
