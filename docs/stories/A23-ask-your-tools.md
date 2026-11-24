# A23: the guide asks which tools you use

Status: Draft (2026-11-24). Risk: high (sign-in steps for outside services; nothing secret may pass through ade).
Owner's intent (2026-11-24): "let's also ask the developer what tools they use". Step 2 of the site's story: your
context, tools and access.
Verification command: `bash tests/run.sh`.

## Today and the gap
`ade connect <service>` exists (A16) for the services with a ready recipe at the pinned ade-skills tag (ClickUp, Jira,
Linear today). The guide (`ade setup`) never asks about tools; `GUIDE_STEPS` already notes "A16 adds its tools step
after hub", never built. A person has to know `ade connect` exists.

## Goal
A `tools` step in the guide, after `hub`: "Which tools do you use for this work?" A pick-any list (`ask_choice`, the
guide's own) of the services ade has a ready recipe for, then those labelled "coming" (GitHub, Gmail, Slack, ...), and
"other" (free text, one line). For each picked ready service it runs the `ade connect <service>` flow (the person signs
in at their own terminal, as A16). A coming or other pick is recorded by name in the hub (`.ade/tools.json`, names only)
and the guide says "not connected yet; noted". Enter skips. `ade setup` again shows what is connected and offers the rest.

## Acceptance criteria (tests/test_guide.sh unless named)
| AC | Criterion | Test |
|---|---|---|
| 1 | The step comes after `hub` and before `project` in `GUIDE_STEPS` and the guide's list | `tools_step_in_order` |
| 2 | The list is built from the pinned recipes: ready ones first, then coming ones labelled, then other | `tools_list_from_recipes` |
| 3 | A picked ready service runs the same code as `ade connect <service>` (stand-in plugin install recorded) | `tools_connect_picked` |
| 4 | A coming or other pick goes to `.ade/tools.json` by name only (format checked, at most 64, no URL or token shape) | `tools_noted_names_only` |
| 5 | Enter skips with nothing written; with no terminal the step is skipped and says `ade setup` later | `tools_skip` |
| 6 | A second run shows connected ones as done and offers only the rest | `tools_second_run` |
| 7 | No token, key or URL with credentials is read, stored or printed (planted fake values never appear) | `tools_nothing_secret` |
