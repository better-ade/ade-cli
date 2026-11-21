# A12 design note: release manifests and update notifications

- Part 1 is in better-ade/.github (#3): `scripts/release-manifest.sh` and `release.yml` attach `release.json`.
- `update_check` runs before every command except `version`, `help`, `update` and the `ade ui` calls tmux makes. Per
  component in use: at most one request a day (`curl --max-time 2`; any failure, a 404 or a malformed manifest only
  writes the stamp), then a banner on stderr once per new version (`security`: every command), one `bin/chat send`
  line when the hub has `HUB_CHANNELS`.
- Auto-update (ade-cli only; the others are announced): on the day's check a newer patch or minor (or `security`)
  release runs A11's `self_update` at that version and prints one line; a new major or a `min_supported` above the
  installed version asks first (the banner says `ade update`); `ADE_NO_AUTO_UPDATE=1` only notifies.
- `self_update` reads `release.json` of the target version: it downloads the `ade` file it names and refuses on a
  sha256 mismatch. Without a manifest (older releases) it says so and keeps A11's `ade version` check. `install.sh`
  does the same when it downloads.
- Tests point `ADE_RELEASES_BASE` at a `file://` folder; when `ADE_CLI_BASE` is overridden and `ADE_RELEASES_BASE` is
  not, no manifest is read (a test never reaches GitHub). `tests/helpers.sh` turns checks off for every other test.
- The ade ui badge: `⬆ N update(s)` after `[+ new]`, from the cached `.latest` files (no request while drawing).
