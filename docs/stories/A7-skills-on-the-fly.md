# A7: skills on the fly

Status: Ready for development (2026-11-21). Risk: medium. Depends on A1. Owner's intent (2026-11-21): "skills can be
onboarded on the fly through the CLI."

## Goal
Add, enable, disable and list skills and plugins without editing files or restarting by hand:
```
ade skills list                       BMAD skills (on / name-only / off) and ade-skills plugins (installed or not)
ade skills add <plugin>               install an ade-skills plugin into the project (A1), then reload
ade skills enable <bmad-skill>        flip an on-demand BMAD skill to on in .claude/settings.json skillOverrides
ade skills disable <bmad-skill>       back to name-only (never deletes the skill)
ade skills search <word>              search ade-skills plugin names and descriptions
```
After a change it tells running sessions: the change applies on the next prompt where Claude Code reloads settings, or
after `/reload-plugins` for plugins; `ade` sends that hint through `ade notify` (C6) to the sessions of that folder.

## Acceptance criteria (`tests/test_skills.sh`, fake claude, fixture settings)
| AC | Criterion |
|---|---|
| 1 | `list` shows each BMAD skill's state from skillOverrides (absent = on) and each plugin's installed state |
| 2 | `enable`/`disable` change only that skill's skillOverrides entry, keep every other key, and are idempotent |
| 3 | A skill in ade-method's never list cannot be enabled (exit 2 naming the reason) |
| 4 | `add` installs and then notifies that folder's running sessions with the reload hint |
| 5 | `search` matches names and descriptions from the marketplace file |
| 6 | Unknown skill or plugin names exit 2 with the closest names |
