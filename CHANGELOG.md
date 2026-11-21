# Changelog

## Unreleased
- `ade claude [<folder>] [-- args]` (A4): Claude Code at the hub root with the hub's `HUB_ROOT_MODEL` and Remote
  Control named after the hub, the `ade@ade-skills` plugin enabled in the hub's settings; `--dangerously-skip-permissions`
  is refused.
- `ade hub new <name> [--private|--public] [--dir] [--no-github]`, `ade hub list|use`, and `ade` alone saying what
  to do next (A3); `install.sh` piped from curl installs the release tag main's `VERSION` names.
- `ade orchestrator new|start|stop|list|logs|remove` (A2): named orchestrators, one per hub, in
  `~/.config/ade/orchestrators` (0600); the hub's `bin/chat` does the work (`.ade/context/hub-interface.md`).

## 0.1.0
- `ade`: hub commands (work, status, dispatch, notify, chat, method, keys, models, roles, doctor, sync, context,
  agent-run) run the hub's own `bin/` scripts; the hub is found by `$ADE_HUB`, walking up, or `~/.config/ade/hub`.
- `ade init`, `ade agent list|add`, `ade skills add`: project setup from ade-method and ade-agent-registry at pinned tags.
- `ade open` (inside the ADE app), `ade version`, `ade help`; `install.sh`; tests in `tests/` (`bash tests/run.sh`).
