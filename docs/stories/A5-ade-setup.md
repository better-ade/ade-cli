# A5: `ade setup`: sign in, then a guided session that sets everything up

Status: Ready for development (2026-11-21). Risk: high (credentials). Depends on A1, A3, A4.
Owner's decisions (2026-11-21): ask the user for their Claude account or key and run a session that sets up the project;
provider-agnostic in principle, but **Claude Code only to start**: providers are Claude (account or Anthropic API key),
DeepSeek, and GLM and Muse once their live check passes; Focus agents may use Gemini (E1) and GPT (E2) as well.
Verification command: `bash tests/run.sh`.

## Setup flow (owner, 2026-11-21, revised)
1. **The everything agent (top, exactly one):** the orchestrator. Choices: Claude Code with Claude (account or key),
   DeepSeek, GLM or Muse. One answer; it can be changed later with `ade setup --top`.
2. **Focus agents (multi-select):** Claude Code, Gemini (Gemini CLI, ade-brain E1), GPT (Codex CLI, ade-brain E2),
   DeepSeek, GLM, Muse. For **each** selected provider: sign in (account login where the CLI has one, else a key with a
   hidden prompt into `bin/keys`), then a **live test**: one tiny read-only task in a throwaway folder ("reply with the
   word READY"), timed, through the same path a real focus agent uses. Result per provider: ready, failed (with the
   reason), or skipped. Only ready providers can be put in a role; the role table is written from them.
3. `ade setup --test [provider]` re-runs the live tests any time.

`ade setup` takes a new user from nothing to a working hub and project:
1. **Claude Code:** installs it with the official installer when `claude` is missing (asks first).
2. **Provider and sign-in** (one question each, plain words):
   - Claude account (Pro, Max, Team, Enterprise): runs Claude Code's own login; `ade` stores nothing.
   - Anthropic API key, DeepSeek key, GLM key, Muse key: read with a hidden prompt (never argv, never echoed), stored
     with the hub's `bin/keys set <tool>` (Keychain on macOS, the V1 store on Linux), and used through Claude Code's key
     helper as ADR 0002 already does; never in the environment. GLM and Muse are shown as "needs the live check" and
     stay off until it passes.
3. **Hub:** `ade hub new` when there is none (A3).
4. **Guided session:** `ade claude` (A4) opens Claude Code at the hub with a first prompt that runs the ADE setup
   guide: asks in plain words about the user's projects and work, then proposes and, one step at a time with the
   user's yes, runs `ade init` per project, `ade agent add` for specialists, `ade skills add` for plugins, sets role
   models (`bin/models`), and offers the Telegram channel (`bin/chat setup telegram`).
- `ade setup --check` reports each step's state (installed, signed in, hub, projects, channel) and changes nothing.

## Acceptance criteria (`tests/test_setup.sh`; fakes for claude, the installer, bin/keys, gh; no network)
| AC | Criterion |
|---|---|
| 1 | With `claude` missing, setup asks before running the installer; "no" stops with the manual command |
| 2 | Account sign-in runs Claude Code's login and stores nothing; `--check` then shows "signed in (account)" |
| 3 | A key is read without echo and passed only to `bin/keys set <tool>` on stdin; it is in no argv, file, log or environment of any child (a fake child prints its env) |
| 4 | GLM and Muse are listed as "needs the live check" and cannot be made the default until then |
| 5 | No hub: runs `ade hub new`; a hub: skips it |
| 6 | The guided session starts with `ade claude` and a setup prompt that names each step and says it asks before each change |
| 7 | `--check` makes no change (all fakes record zero writes) and prints one line per step |
| 8 | The top agent is asked first and only one can be chosen; Gemini and GPT are not offered for it |
| 9 | Focus providers are multi-select; each selected one is signed in and live-tested; a failed test leaves it out of every role, with the reason shown |
| 10 | `--test` re-runs the live tests and changes nothing else; the test runs in a throwaway folder and never in a real checkout |
