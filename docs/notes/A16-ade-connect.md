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

## Fix round (review of PR #42)
- `.ade/connectors.json` is written through the shared `ade_write` (0.2.1, PR #44): a `mkstemp` temp file, fsync,
  rename, under the folder's lock; `connect_record` checks that a planted temp link is never written through and that
  the record is replaced by a rename (its inode changes).
- "Terminal only" stops accidents; an agent running as you can get round it. The ten session variables and the
  `[ -t 0 ]` half of `tty_ready` are both tested (a pseudo-terminal with stdin piped is refused).
- The validator follows ade-skills' checker (`plugins/guard/scripts/check-recipe.sh` on K5-recipes, 608cebf): the
  same rules in the same order, mostly the same messages. Deliberately stricter: every string is printable ASCII
  (the checker's test holds shipped recipes to that); `sign_in.plugin` must equal the service for every kind (the
  checker: for `claude-ai` only); the guard's hook files must be regular files, not links. Following the contract's
  per-recipe wording where the checker refuses the whole folder: a file that is not `<service>.json` or a broken
  recipe is refused alone; only the "Across files" rules refuse the folder.
- The manifest download is capped (`--max-filesize 65536`, checked again after); redirects are limited to https.
- gh 2.88.0 on this Mac (help text only): `gh auth status` has `-a, --active` and `-h, --hostname`; `gh auth login`
  has `-h, --hostname`. `--active` came with multi-account gh; on an older gh that rejects it ("unknown flag:
  --active"), ade asks `gh auth status --hostname github.com` alone. Ubuntu 24.04's apt gh (2.45) has `--active`.
- A `gh` or `claude` inside the project is refused with exit 2 and that one reason (`connect`, `disconnect`; `status` says missing);
  `tests/run.sh`'s guard compares names, modes, sizes and times only (`suite_guard` in `tests/test_ade.sh`).
