# Changelog

## Unreleased
- `ade init` installs ade-method's `install_templates` (`.github/pull_request_template.md`, `.ade/commit-template.txt`,
  never overwriting) and sets `git config commit.template .ade/commit-template.txt` in that repo unless one is set;
  the default `ADE_METHOD_REF` is now `v2.1.0`; the temp checkout is removed again (the exit trap no longer fails).

## 0.1.0
- `ade`: hub commands (work, status, dispatch, notify, chat, method, keys, models, roles, doctor, sync, context,
  agent-run) run the hub's own `bin/` scripts; the hub is found by `$ADE_HUB`, walking up, or `~/.config/ade/hub`.
- `ade init`, `ade agent list|add`, `ade skills add`: project setup from ade-method and ade-agent-registry at pinned tags.
- `ade open` (inside the ADE app), `ade version`, `ade help`; `install.sh`; tests in `tests/` (`bash tests/run.sh`).
