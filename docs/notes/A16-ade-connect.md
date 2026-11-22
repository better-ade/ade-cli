# A16 design note: `ade connect`

- One section in `ade` (after `ade restore`): `connectors_py` (the record), `recipes_py` (format 1, whole),
  `connect_recipes` (pin, fetch, `release.json`, sha256 per recipe), then `connect_list`, `connect_service`,
  `connect_status`, `connect_disconnect`. `plugin_add` is `ade skills add`'s install and record step, shared.
- Trust order: the name is checked before anything else; then `tty_ready` (for connect and disconnect); then the record;
  then the pin. A recipe's bytes are hashed before Python opens it; recipes are parsed with duplicate keys refused and
  printed only as checked one-line text, again through `no_ctl`.
- Rerun: an installed plugin (Claude Code's list for this folder) is not installed or recorded again, and the record
  and journal change only for a new name, so a second `ade connect <service>` changes nothing.
- `gh` presence is checked before anything is installed, so `gh` missing changes nothing (the contract checks it at
  step 8, after the install).
- The card says `next: ade connect status <service>`: `ade connect test` is A17.
- Tests: `tests/test_connect.sh` with a local ade-skills fixture re-tagged `v0.7.0` and its `release.json` in a
  `file://` folder; a fake `claude` that records installs in `installed_plugins.json`, a fake `gh`. `tests/run.sh`
  fails when the real `~/.config/ade` changes during a run.
- Amendment 1 of the contract (2026-11-22) folded in: the checks above, the card's fixed sentences per kind, and
  `status` saying `missing (held: <held>)` for a recorded held service. Fixtures keep a `ready` `cli` (github) and a
  `ready` `claude-ai` (gmail) recipe, as K7 will make them, so those code paths are tested; a test also uses them as
  the first release ships them (held).
