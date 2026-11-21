# A5 design note: `ade setup`

Order: 1 Claude Code (installer only after a yes; "no" prints the manual command, exit 1) · 2 the hub (`ade hub new`
when there is none: asks a name and whether GitHub) · 3 the everything agent (one answer; signed in, then live-tested;
GLM and Muse only once the test passes) · 4 focus providers (several; each signed in, then live-tested; failures show
the reason) · 5 `HUB_PROVIDERS_ALLOWED` = the top provider plus the ready focus ones, so the hub's own role table
(`bin/roles`) never picks a provider that failed · 6 Telegram (asked once) · 7 the guided session: `ade claude -- <setup
prompt>`.

Secrets: read with `read -s` on a terminal (plain `read` from a pipe) into an unexported variable, written with the
`printf` builtin into the stdin of `bin/keys set <tool>`, then cleared. No argv, file, log or child environment holds
one (`key_only_on_stdin` checks every fake's argv and environment log and every file under the test folder).

Modes: `--check` reads only (5 lines); `--test [p|telegram]` re-runs live tests and writes nothing; `--top` and
`--telegram` run one step.

Open items for ade-brain (blocking for a real run, faked in tests): `bin/agent --live-test`, `bin/keys` tools
`anthropic` and `telegram`, `bin/chat setup|test telegram` (C5), Gemini through `bin/agent` (E1), and the hub reading
`HUB_ROOT_PROVIDER`. Starting a non-Anthropic everything agent from `ade claude` is not built yet.

Review round (high risk): temp folders come only from `mk_tmp` (fails closed) and are removed only by `rm_tmp` (paths
under the temp root named `ade.*`); `SECRET`, `ANSWER` and `HUB_ANSWER` are unset at start; READY must be a whole line;
the installer prompt shows the URL and curl is https-only (`ADE_TEST_ALLOW_FILE_URLS=1` lets tests use file://);
`--top` keeps the old allowed list; a failed provider is signed out of the session cache; the guided session runs
with `--permission-mode default`; only "no hub found" makes a new hub; failure reasons are redacted; the live test's
environment is scrubbed of key variables; Gemini offers its CLI's Google login (`ADE_GEMINI_CLI` names the command).
