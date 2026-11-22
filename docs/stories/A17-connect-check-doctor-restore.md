# A17: connectors in `test`, `--check`, `ade doctor`, `ade restore` and `ade setup`

Status: Ready for development (2026-11-22). Risk: high. Depends on A16 and ade-skills K6 (the guard).
Contract: ade-skills `.ade/context/connectors.md` (sections 3, 5 and 6). The contract wins over this story.

## Goal
A new teammate runs `ade restore` and is walked through each sign-in the project expects. Anyone can ask whether a
connector works and whether anything sits outside the guard. This is the owner's sentence made concrete: the skills
are predefined, the sign-in is per user.

## Acceptance criteria (`tests/test_connect.sh`, extended; fakes only, no network)
| AC | Criterion | Test |
|---|---|---|
| 1 | `ade connect test <service>` does one harmless read (`gh auth status` for `gh`; one tool from the recipe's read list through a non-interactive Claude Code run otherwise) and prints only `<service>: test passed` or `test failed (<reason>)`, never content; terminal only | `connect_test` |
| 2 | `ade connect --check` prints what the folder expects, then the status lines and the doctor lines; exit 0 with no gap, 1 with a gap, 2 when the record is invalid; it reads only | `connect_check` |
| 3 | The doctor check reads files only and reports a known vendor's server that sits outside the guard (project, user or local scope), with the exact fix; a server name is printed with control characters removed | `connect_doctor_outside` |
| 4 | `ade doctor` runs those lines for every folder with a record, and says so in one line when Claude Code is older than the version the guard needs to fail closed | `doctor_connectors` |
| 5 | `ade restore` treats a `missing` connector as a gap and, after a yes at the terminal, walks the same steps as `ade connect <service>`; `--check` prints one line per connector and changes nothing | `restore_connectors` |
| 6 | `ade setup --check` prints `connectors: <n> expected, <m> ready`; the guided session is told which `ade connect <service>` the person should run at their own terminal and never runs it | `setup_connectors` |
| 7 | If Claude Code keeps a plugin server's sign-in per config folder and not per project (to be confirmed first), a second customer folder under the same config folder is refused with the contract's message; if it is per project, this criterion is recorded as not needed, with the evidence | `connect_per_folder` |
| 8 | README, the help text and CHANGELOG describe `ade connect` and the tiers in plain words | `connect_docs` |
