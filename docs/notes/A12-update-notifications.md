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

## Fix round (2026-11-22, after the adversarial review; risk raised to high)
- `MANIFEST_SINCE=0.2.0` in `ade` and `install.sh` (no override: an environment variable could turn the check off).
  `release_sha` fetches the per-version manifest; `manifest_py` checks component, version, a 64-hex sha256 for `ade`
  and ignores `url`; the reason goes into the one message, never cut by `tail -1`. `releases_on` is gone: the manifest
  is always read from `ADE_RELEASES_BASE` (default GitHub). `self_update` refuses a version lower than the installed
  one. Tests for A11 publish a manifest for their 0.9.0 release (`rel_manifest`).
- `update_check` makes no request: it prints from the cache (`update_banners`), reports a finished auto-install
  (`update_auto_report`), and once a day (`checked`, lock `fetching`) starts `update_fetch_all` detached (`trap ''
  HUP INT`, stdio closed): each component in use is fetched side by side, and one `sleep 2` watchdog sends TERM to
  every fetch still running (each kills its own curl). The banner therefore shows on the command after the fetch.
- `update_auto`: ade-cli only, a newer patch/minor (or security) release, `auto_on`, not `agent_context`, stdin and
  stderr a terminal, once per version (`ade-cli.tried`); a major or a `min_supported` jump prints how to install it by
  hand. The install itself is `self_update 0 <version>` in a detached job writing `auto.log`.
- Residual risk recorded in `.ade/context/hub-interface.md`: integrity, not authenticity (signing is a later decision).
