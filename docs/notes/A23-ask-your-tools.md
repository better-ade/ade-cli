# A23 design note: the guide asks which tools you use

- `tools` is step 5 of `GUIDE_STEPS`, after `hub`, before `project`. It is optional (in `GUIDE_OPTIONAL`, so it never
  holds back "All set"), and unlike `telegram` it is offered in every run once the hub is there: `ade setup` again
  shows what is connected (`done: <service> (connected)`) and noted, and offers the rest.
- State, for the list, from the hub's own records only (no fetch): `.ade/connectors.json` (A16) and `.ade/tools.json`
  (this story); done when either names something.
- The list: `connect_recipes` (the pinned tag, `release.json`, sha256, format 1: the same checks as `ade connect`) in
  a subshell. Ready recipes not connected, then held ones not noted ("coming"), then `other`; refused recipes are left
  out. Nothing is hard-coded: the services are whatever the pin carries. The recipes are read only after the terminal
  check, so a piped `ade setup` never fetches.
- A ready pick runs `connect_service` itself, in a subshell in the hub (its questions, its install, its record, its
  journal line); its exit is not the guide's: a no or a failure says `ade connect <service> (in <hub>) tries again`.
- A coming or other pick is noted by name. `other` is one line of free text through `ask_text` (answers are data):
  comma-separated names, each lower-cased with spaces as `-`, `^[a-z][a-z0-9-]{0,31}$`. Anything with `@ : / . = _`
  or a part of 24+ characters (16+ with a digit) is refused as a possible address, key or token, and never echoed.
- `connectors_py` became `names_py <record> <key>`, shared by both records; one behaviour change for connectors: a
  record that would pass 64 names is refused in one line instead of a Python traceback.
- Tests: `tests/test_guide.sh` `tools_*` (a local ade-skills fixture re-tagged `v0.7.0`, `release.json` in a
  `file://` folder, the guide's fake `claude` taking `plugin` calls as stand-ins). The guide's other tests, and
  `test_bun`, `test_telegram` and `test_ubuntu`, point `ADE_SKILLS_REPO` at a missing folder so the step never
  reaches the network; the golden first run shows it skipped.
