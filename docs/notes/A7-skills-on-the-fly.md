# A7 design note: skills on the fly

- One embedded python3 block reads and writes `.claude/settings.json` (atomic rename; other keys kept; invalid JSON
  refused). `enable` = remove the override (absent is on), `disable` = `"name-only"`, both idempotent; a skill is
  known when it is in `.claude/skills/<name>/SKILL.md` or already in `skillOverrides`.
- `enable` fetches ade-method's `ade.json` at the pin and refuses its `bmad.never` names (exit 2, reason named).
- `list`, `search` and `add` read ade-skills' marketplace file at `ADE_SKILLS_REF` (default `main`); `add` checks the
  name there before calling `claude plugin install` (A1's behaviour otherwise unchanged).
- After `add`, `enable` or `disable` the hint is printed and, when the project belongs to a hub folder, sent with the
  hub's `bin/notify <folder>` (C6, faked in tests). A project in no folder notifies nobody.
- Unknown names: exit 2 with up to three closest names (difflib).
