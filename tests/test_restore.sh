#!/bin/bash
# story A10: .ade/connections.json and ade restore. Fakes for claude (account, plugins), the hub's secrets store
# (bin/keys), bin/agent --live-test, bin/chat, bin/schedule and bin/journal; never the network, never a real key store.
. "$(dirname "$0")/helpers.sh"

restore_fixture() {
  make_skills_repo; H="$T/hub"; make_hub "$H" hub; printf 'HUB_NAME=acme\nHUB_ROOT_MODEL=opus\n' > "$H/hub.conf"
  git init -q "$H"; mkdir -p "$H/projects/api" "$T/fakebin" "$T/keystore" "$T/LA"
  export FAKE_LOG="$T/fake.log" KEYSTORE="$T/keystore" AGENT_LAUNCHAGENTS="$T/LA" ADE_GEMINI_CLI=no-gemini-cli-here; : > "$FAKE_LOG"
  unset FAKE_PLUGIN_VERSION FAKE_MKT_NAME LOGIN_USER LOGIN_ORG
  cat > "$H/bin/keys" <<'F'
#!/bin/bash
echo "keys $*" >> "$FAKE_LOG"
case "${1:-}" in set) IFS= read -r v; printf '%s' "$v" > "$KEYSTORE/$2" ;; forget) rm -f "$KEYSTORE/$2" ;;
  "") for f in "$KEYSTORE"/*; do [ -f "$f" ] && echo "$(basename "$f") stored"; done ;; esac; exit 0
F
  cat > "$H/bin/agent" <<'F'
#!/bin/bash
echo "agent $*" >> "$FAKE_LOG"; IFS= read -r task
case "$2" in anthropic) [ -f "$HOME/.claude.json" ] || { echo "not signed in"; exit 1; } ;;
  *) [ -f "$KEYSTORE/$2" ] && ! grep -q bad "$KEYSTORE/$2" || { echo "agent: the key was rejected (401)"; exit 1; } ;; esac
echo READY
F
  cat > "$H/bin/chat" <<'F'
#!/bin/bash
echo "chat $*" >> "$FAKE_LOG"
case "$1 ${2:-}" in "info telegram") echo "bot @acme_bot" ;; "setup telegram") touch "$HUB/.paired" ;; esac; exit 0
F
  cat > "$H/bin/schedule" <<'F'
#!/bin/bash
echo "schedule $*" >> "$FAKE_LOG"; for j in chat monitor sync; do : > "$AGENT_LAUNCHAGENTS/ai.agent-hub.acme.$j.plist"; done
F
  printf '#!/bin/bash\necho "$*" >> "$HUB/journal.log"\n' > "$H/bin/journal"
  # a fake claude: the account in ${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json; plugins installed at $FAKE_PLUGIN_VERSION
  # (default 0.1.0) for the folder it runs in; a marketplace added is listed as $FAKE_MKT_NAME (default ade-skills)
  cat > "$T/fakebin/claude" <<'F'
#!/bin/bash
echo "claude $*" >> "$FAKE_LOG"; [ -z "${CLAUDE_CONFIG_DIR:-}" ] || echo "claude-config $CLAUDE_CONFIG_DIR $1 ${2:-}" >> "$FAKE_LOG"
P="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins"; J="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
case "$1 ${2:-} ${3:-}" in
  "auth status "*) [ -f "$J" ] ;;
  "auth login "*) mkdir -p "$(dirname "$J")"; printf '{"oauthAccount": {"accountUuid": "%s", "organizationUuid": "%s", "emailAddress": "owner@example.com"}}\n' \
      "${LOGIN_USER:-u-1}" "${LOGIN_ORG:-o-1}" > "$J" ;;
  "plugin marketplace list") cat "$P/mkt" 2> /dev/null ;;
  "plugin marketplace add") mkdir -p "$P"; echo "${FAKE_MKT_NAME:-ade-skills}" >> "$P/mkt" ;;
  "plugin install "*) n=""; for a in "$@"; do case "$a" in *@*) n="$a" ;; esac; done; echo "claude-cwd $(pwd -P) $n" >> "$FAKE_LOG"
    mkdir -p "$P"; python3 -c 'import json,os,sys; p=sys.argv[1]; d=json.load(open(p)) if os.path.exists(p) else {"version": 2, "plugins": {}}
d["plugins"].setdefault(sys.argv[2], []).append({"scope": "project", "projectPath": sys.argv[3], "version": sys.argv[4]}); json.dump(d, open(p, "w"))' \
      "$P/installed_plugins.json" "$n" "$(pwd -P)" "${FAKE_PLUGIN_VERSION:-0.1.0}" ;;
  *) echo "session $*" ;;
esac
F
  for c in launchctl systemctl; do printf '#!/bin/bash\necho "%s $*" >> "$FAKE_LOG"\n' "$c" > "$T/fakebin/$c"; done
  chmod +x "$T/fakebin/"* "$H/bin/"*; export PATH="$T/fakebin:$PATH" ADE_HUB="$H"
}
signed_in() { printf '{"oauthAccount": {"accountUuid": "%s", "organizationUuid": "%s", "emailAddress": "owner@example.com"}}\n' "$1" "$2" > "$HOME/.claude.json"; }
fp() { printf 'ade-account-v1:%s:%s' "$2" "$1" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:16])'; }
# a record as a first machine left it: Claude account u-1/o-1, DeepSeek focus by key, Telegram, the git plugin,
# the chat and monitor services; the built-in ade-skills from a local fixture is recorded as "local"
write_record() {   # [plugin ref]
  mkdir -p "$H/.ade"; cat > "$H/.ade/connections.json" <<J
{
  "format": 1,
  "account": {"label": "work", "fingerprint": "$(fp u-1 o-1)"},
  "top": {"provider": "anthropic", "sign_in": "account", "model": "opus"},
  "focus": [{"provider": "deepseek", "sign_in": "key"}],
  "channels": [{"type": "telegram", "bot": "@acme_bot"}],
  "marketplaces": [{"name": "ade-skills", "repo": "local"}],
  "plugins": [{"name": "git", "marketplace": "ade-skills", "ref": "${1:-v0.1.0}"}],
  "services": ["chat", "monitor"]
}
J
}
# record_with <python statements on d>: the hub's record from write_record, changed (T is the test folder)
record_with() {
  write_record; python3 - "$H/.ade/connections.json" "$1" "$T" <<'PY'
import json, sys
p, code, T = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p)); exec(code); json.dump(d, open(p, "w"))
PY
}
# github_as <dir>: https://github.com/ (also with a user in it) is a local folder for git, in this test's HOME only
github_as() { mkdir -p "$1"; git config --global url."$1/".insteadOf https://github.com/; git config --global --add url."$1/".insteadOf https://tok@github.com/; }
secret_free() {   # <file>: no key-shaped value, token, email, account id, machine path or URL with a user
  ! grep -Eq 'sk-|tok-|bot[0-9]+:|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}|"u-1"|"o-1"|accountUuid|organizationUuid|/Users/|/home/|/private/|://[^/]*@' "$1" ||
    { cat "$1"; fail "$2: a secret, email, account id or machine path in the record"; }
}
installed_version() {   # <name@marketplace> <folder>: the versions Claude Code installed for that folder
  python3 -c 'import json,os,sys; d=json.load(open(sys.argv[1])); print(" ".join(e.get("version","?") for e in d["plugins"].get(sys.argv[2],[]) if os.path.realpath(e.get("projectPath","")) == sys.argv[3]))' \
    "$HOME/.claude/plugins/installed_plugins.json" "$1" "$(cd "$2" && pwd -P)"
}

record_kept_current() {   # AC1: setup, skills add, agent add, init and chat setup keep the record current
  fresh; restore_fixture; make_method_repo; make_registry_repo; signed_in u-1 o-1
  printf '1\n' | bash "$ADE" setup --top > "$T/out" 2>&1 || { cat "$T/out"; fail "setup --top"; }
  R="$H/.ade/connections.json"; [ -f "$R" ] || fail "setup writes the record"
  python3 - "$R" "$(fp u-1 o-1)" <<'PY' || fail "top provider and account recorded"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["top"] == {"provider": "anthropic", "sign_in": "account", "model": "opus"}, d
assert d["account"]["fingerprint"] == sys.argv[2] and d["account"]["label"], d
PY
  bash "$ADE" chat setup telegram > "$T/out" 2>&1 || { cat "$T/out"; fail "chat setup telegram"; }   # (ade setup --telegram records it too, once it is working: test_telegram.sh)
  (cd "$H" && bash "$ADE" skills add git > "$T/out" 2>&1) || { cat "$T/out"; fail "skills add"; }
  (cd "$H" && bash "$ADE" agent add frontend > "$T/out" 2>&1) || { cat "$T/out"; fail "agent add"; }
  (cd "$H" && bash "$ADE" init > "$T/out" 2>&1) || { cat "$T/out"; fail "init"; }
  bash "$ADE" chat setup slack > "$T/out" 2>&1 || { cat "$T/out"; fail "chat setup"; }
  python3 - "$R" <<'PY' || fail "every kind recorded"
import json, sys
d = json.load(open(sys.argv[1]))
assert {"type": "telegram", "bot": "@acme_bot"} in d["channels"], d
assert {"type": "slack", "bot": ""} in d["channels"] or any(c["type"] == "slack" for c in d["channels"]), d
assert any(p["name"] == "git" and p["ref"] == "v0.1.0" for p in d["plugins"]), d
assert {"name": "ade-skills", "repo": "local"} in d["marketplaces"], d   # a machine path is never recorded
assert d["specialists"] == ["frontend"], d
assert d["pins"]["ade-method"] == "v2.2.0" and d["pins"]["ade-agent-registry"] == "v1.1.0" and d["pins"]["ade-skills"] == "v0.1.0", d
PY
  secret_free "$R" "after setup"
  bash "$ADE" restore --check < /dev/null > "$T/out" 2>&1; assert_not_contains "$T/out" "not a valid connections record" "what ade writes, ade reads"
  P="$T/proj"; mkdir -p "$P"; git init -q "$P"; (cd "$P" && bash "$ADE" init > /dev/null 2>&1) || fail "init in a project"
  [ -f "$P/.ade/connections.json" ] && secret_free "$P/.ade/connections.json" "project" || fail "init records the project's pins"
}

record_repo_public_only() {   # item 6: only a public GitHub URL is recorded; a path or a URL with a user is "local"
  fresh; restore_fixture; signed_in u-1 o-1; github_as "$T/gh"; mkdir -p "$T/gh/better-ade"; git clone -q --bare "$K" "$T/gh/better-ade/ade-skills"
  R="$H/.ade/connections.json"
  ADE_SKILLS_REPO="https://tok@github.com/better-ade/ade-skills" bash -c 'cd "$1" && bash "$2" skills add git' _ "$H" "$ADE" > "$T/out" 2>&1 || { cat "$T/out"; fail "skills add (a URL with a user)"; }
  assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["marketplaces"][0]["repo"])' "$R")" local "a URL with a user is not recorded"
  secret_free "$R" "a URL with a user"
  ADE_SKILLS_REPO="https://github.com/better-ade/ade-skills" bash -c 'cd "$1" && bash "$2" skills add git' _ "$H" "$ADE" > "$T/out" 2>&1 || { cat "$T/out"; fail "skills add (public)"; }
  assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["marketplaces"][0]["repo"])' "$R")" https://github.com/better-ade/ade-skills "a public URL is"
}

fresh_machine() {   # AC2 + AC6: every gap listed, then fixed with a yes each (typed at a terminal); Telegram re-pairs
  fresh; restore_fixture; write_record; signed_in u-1 o-1
  pty_run 'y\nsk-deep-good-1234567890\ny\ny\ntok-new-123456\ny\n' bash "$ADE" restore > "$T/out" 2>&1 || { cat "$T/out"; fail "restore exit"; }
  for g in "key deepseek: missing" "plugin git@ade-skills: missing" "channel telegram: missing" "service chat: missing" "service monitor: missing"; do
    assert_contains "$T/out" "$g" "listed: $g"; done
  assert_eq "$(cat "$KEYSTORE/deepseek")" "sk-deep-good-1234567890" "the key went to bin/keys"
  assert_contains "$FAKE_LOG" "agent --live-test deepseek" "then live-tested"
  assert_contains "$FAKE_LOG" "claude plugin marketplace add -- $K" "marketplace back (a record value after --)"
  assert_contains "$FAKE_LOG" "claude plugin install --scope project -- git@ade-skills" "plugin back"
  assert_eq "$(installed_version git@ade-skills "$H")" 0.1.0 "installed at the recorded version"
  assert_contains "$T/out" "plugin git@ade-skills: ready" "and verified"
  assert_eq "$(cat "$KEYSTORE/telegram")" "tok-new-123456" "the bot token went to bin/keys"
  assert_contains "$FAKE_LOG" "chat setup telegram --repair" "Telegram re-pairs"
  ! grep -q "chat setup telegram$" "$FAKE_LOG" || fail "never the old pairing"
  assert_contains "$FAKE_LOG" "schedule install" "services reinstalled"; [ -f "$T/LA/ai.agent-hub.acme.chat.plist" ] || fail "service back"
  assert_contains "$T/out" "deepseek: ready" "a step ends ready"
  for f in "$T/out" "$FAKE_LOG" "$H/.ade/connections.json"; do assert_not_contains "$f" "sk-deep-good" "no key in $f"; assert_not_contains "$f" "tok-new" "no token in $f"; done
  assert_contains "$H/journal.log" "ade restore" "journaled"
}

terminal_only() {   # item 3: restore and the account question take answers from a person at a terminal only
  fresh; restore_fixture; write_record; signed_in u-1 o-1
  printf 'y\nsk-deep-good-1234567890\ny\ny\ntok-new-123456\ny\n' | bash "$ADE" restore > "$T/out" 2>&1; assert_eq "$?" 2 "piped answers are refused"
  assert_contains "$T/out" "refuses piped or missing answers" "says so"
  export CLAUDECODE=1; pty_run 'n\ny\nn\nn\n' bash "$ADE" restore > "$T/out" 2>&1; assert_eq "$?" 2 "an agent session is refused"; unset CLAUDECODE
  ! grep -Eq "plugin install|marketplace add|keys set" "$FAKE_LOG" || fail "nothing installed or stored without a person"
  signed_in u-2 o-2
  export CLAUDECODE=1; pty_run 'c\n' bash "$ADE" work api > "$T/out" 2>&1; assert_eq "$?" 2 "the account question is refused in an agent session"; unset CLAUDECODE
  assert_contains "$T/out" "an agent cannot" "says why"; assert_not_contains "$T/out" "hub work" "bin/work not run"
  [ ! -f "$HOME/.config/ade/accounts" ] || fail "no answer remembered"
}

account_skipped_stops() {   # item 3: a skipped account step stops restore (exit 2) before anything else
  fresh; restore_fixture; write_record; signed_in u-2 o-2
  pty_run '\ny\nsk-deep-good-1234567890\ny\ny\ntok-new-123456\ny\n' bash "$ADE" restore > "$T/out" 2>&1; assert_eq "$?" 2 "stopped"
  assert_contains "$T/out" "account step was skipped" "says so"
  ! grep -Eq "keys set|plugin install|marketplace add|repair|schedule" "$FAKE_LOG" || { cat "$FAKE_LOG"; fail "nothing after a skipped account step"; }
}

account_gate() {   # AC3: another Claude account stops connection-needing commands until answered; remembered
  fresh; restore_fixture; write_record; signed_in u-2 o-2
  bash "$ADE" work api < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "stopped without a terminal"
  assert_contains "$T/out" "set up with work" "the refusal names the label"; assert_not_contains "$T/out" "hub work" "bin/work not run"
  bash "$ADE" claude < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "ade claude stopped too"
  pty_run '\n' bash "$ADE" work api > "$T/out" 2>&1; assert_eq "$?" 2 "no answer at the terminal"
  pty_run 'c\n' bash "$ADE" work api > "$T/out" 2>&1 || { cat "$T/out"; fail "continue"; }; assert_contains "$T/out" "hub work" "continued"
  bash "$ADE" work api < /dev/null > "$T/out" 2>&1 || fail "the answer is remembered"; assert_contains "$T/out" "hub work" "no question again"
  bash "$ADE" restore --check < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "account work: different (continuing with this account)" "check says so"
  fresh; restore_fixture; write_record; signed_in u-2 o-2; export LOGIN_USER=u-1 LOGIN_ORG=o-1
  pty_run 's\n' bash "$ADE" work api > "$T/out" 2>&1 || { cat "$T/out"; fail "sign in"; }
  assert_contains "$FAKE_LOG" "claude auth login" "signed in to the recorded account"; assert_contains "$T/out" "hub work" "then runs"
  fresh; restore_fixture; signed_in u-2 o-2; bash "$ADE" work api < /dev/null > "$T/out" 2>&1 || fail "no record, no gate"
}

account_config_dir() {   # the sign-in uses the hub's Claude Code folder (HUB_CLAUDE_CONFIG_DIR), where the fingerprint is read
  fresh; restore_fixture; write_record; signed_in u-1 o-1; echo "HUB_CLAUDE_CONFIG_DIR='$T/cfg'" >> "$H/hub.conf"; mkdir -p "$T/cfg"
  export LOGIN_USER=u-1 LOGIN_ORG=o-1
  pty_run 's\n' bash "$ADE" work api > "$T/out" 2>&1 || { cat "$T/out"; fail "sign in with the hub's config folder"; }
  assert_contains "$FAKE_LOG" "claude-config $T/cfg auth login" "claude ran with CLAUDE_CONFIG_DIR"; assert_contains "$T/out" "hub work" "then runs"
}

keys_live_tested() {   # AC4: hidden prompt, bin/keys only, live test; a failed one leaves the roles with the reason
  fresh; restore_fixture; write_record; signed_in u-1 o-1; echo "HUB_PROVIDERS_ALLOWED='anthropic deepseek'" >> "$H/hub.conf"
  pty_run 'y\nsk-bad-key-1234567890\nn\nn\nn\n' bash "$ADE" restore > "$T/out" 2>&1
  assert_contains "$T/out" "deepseek: failed (agent: the key was rejected (401))" "the reason"
  assert_contains "$T/out" "left out of the roles" "says so"
  assert_eq "$(. "$H/hub.conf"; echo "$HUB_PROVIDERS_ALLOWED")" anthropic "out of the roles"
  assert_not_contains "$T/out" "sk-bad-key" "never echoed"; assert_contains "$T/out" "still needs you" "the summary lists it"
}

plugin_versions() {   # AC5: the recorded version, verified; one no longer published falls back to the latest, never "ready"
  fresh; restore_fixture; write_record v0.0.9; signed_in u-1 o-1
  pty_run 'n\ny\nn\nn\n' bash "$ADE" restore > "$T/out" 2>&1; assert_eq "$?" 1 "not every connection is ready"
  assert_contains "$T/out" "v0.0.9 is no longer published" "warns"; assert_contains "$FAKE_LOG" "claude plugin install --scope project -- git@ade-skills" "installs the latest"
  assert_contains "$T/out" "plugin git@ade-skills: different (recorded v0.0.9, installed v0.1.0)" "says what it got"
  assert_eq "$(installed_version git@ade-skills "$H")" 0.1.0 "the installed version"
  fresh; restore_fixture; write_record; signed_in u-1 o-1; export FAKE_PLUGIN_VERSION=0.2.0
  pty_run 'n\ny\nn\nn\n' bash "$ADE" restore > "$T/out" 2>&1; assert_eq "$?" 1 "a different version is a gap"
  assert_contains "$T/out" "plugin git@ade-skills: different (recorded v0.1.0, installed v0.2.0)" "verified afterwards"
  assert_not_contains "$T/out" "plugin git@ade-skills: ready" "never ready"
  bash "$ADE" restore --check < /dev/null > "$T/out" 2>&1; assert_eq "$?" 1 "check: a gap"
  assert_contains "$T/out" "plugin git@ade-skills: different (recorded v0.1.0, installed v0.2.0)" "check says so"
  # a GitHub marketplace is added at the recorded tag
  fresh; restore_fixture; github_as "$T/gh"; mkdir -p "$T/gh/better-ade"; git clone -q --bare "$K" "$T/gh/better-ade/ade-skills"
  export ADE_SKILLS_REPO=https://github.com/better-ade/ade-skills; record_with 'd["marketplaces"][0]["repo"] = "https://github.com/better-ade/ade-skills"'
  signed_in u-1 o-1; pty_run 'n\ny\nn\nn\n' bash "$ADE" restore > "$T/out" 2>&1
  assert_contains "$FAKE_LOG" "claude plugin marketplace add -- https://github.com/better-ade/ade-skills.git#v0.1.0" "at the recorded tag"
  assert_contains "$T/out" "plugin git@ade-skills: ready" "verified"; assert_eq "$(installed_version git@ade-skills "$H")" 0.1.0 "the installed version"
}

project_records() {   # ade restore also reads the records of the hub's projects and installs their plugins there
  fresh; restore_fixture; write_record; signed_in u-1 o-1
  mkdir -p "$H/projects/api/.ade"; echo '{"format": 1, "plugins": [{"name": "notes", "marketplace": "ade-skills", "ref": "v0.1.0"}], "pins": {"ade-skills": "v0.1.0"}}' > "$H/projects/api/.ade/connections.json"
  bash "$ADE" restore --check < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "plugin notes@ade-skills in projects/api: missing" "listed"
  pty_run 'n\ny\nn\ny\nn\n' bash "$ADE" restore > "$T/out" 2>&1
  assert_contains "$FAKE_LOG" "claude-cwd $H/projects/api notes@ade-skills" "installed in the project's folder"
  assert_eq "$(installed_version notes@ade-skills "$H/projects/api")" 0.1.0 "at the recorded version"
  bash "$ADE" restore --check < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "plugin notes@ade-skills in projects/api: ready" "then ready"
  echo '{"format": 1, "plugins": [{"name": "notes", "marketplace": "ade-skills", "ref": "main"}]}' > "$H/projects/api/.ade/connections.json"
  bash "$ADE" restore --check < /dev/null > "$T/out" 2>&1; assert_eq "$?" 1 "a bad project record fails the check"
  assert_contains "$T/out" "projects/api/.ade/connections.json is not a valid connections record" "names it"
}

other_marketplace() {   # item 2: the question shows the repo; a marketplace other than ade-skills needs its name typed back
  fresh; restore_fixture; signed_in u-1 o-1; github_as "$T/gh"; mkdir -p "$T/gh/acme" "$T/team"; git init -q "$T/team"; echo t > "$T/team/README"; commit_tag "$T/team" t v1.0.0
  git clone -q --bare "$T/team" "$T/gh/acme/team-skills"; export FAKE_MKT_NAME=team FAKE_PLUGIN_VERSION=1.0.0
  record_with 'd = {"format": 1, "marketplaces": [{"name": "team", "repo": "https://github.com/acme/team-skills"}], "plugins": [{"name": "lint", "marketplace": "team", "ref": "v1.0.0"}]}'
  pty_run 'y\nteem\n' bash "$ADE" restore > "$T/out" 2>&1; assert_eq "$?" 1 "not typed back: not ready"
  assert_contains "$T/out" "from the marketplace team (https://github.com/acme/team-skills)" "the question shows the repo"
  assert_contains "$T/out" "skipped (the name was not typed back)" "skipped"; assert_not_contains "$FAKE_LOG" "marketplace add" "nothing added"
  assert_not_contains "$FAKE_LOG" "plugin install" "nothing installed"
  pty_run 'y\nteam\n' bash "$ADE" restore > "$T/out" 2>&1 || { cat "$T/out"; fail "typed back"; }
  assert_contains "$FAKE_LOG" "claude plugin marketplace add -- https://github.com/acme/team-skills.git#v1.0.0" "added at its tag"
  assert_contains "$FAKE_LOG" "plugin install --scope project -- lint@team" "installed"
}

# hostile records (item 1, 4): each is rejected whole; check, restore and the gate exit 1 with the reason; nothing runs
hostile_records() {
  local i=0 code rc
  while IFS= read -r code; do
    [ -n "$code" ] || continue; i=$((i + 1))
    fresh; restore_fixture; signed_in u-1 o-1; record_with "$code"
    bash "$ADE" restore --check < /dev/null > "$T/o1" 2>&1; rc=$?
    [ "$rc" = 1 ] && grep -q "is not a valid connections record" "$T/o1" || { cat "$T/o1"; fail "record $i ($code): --check exit $rc"; }
    pty_run 'y\ny\ny\ny\ny\ny\n' bash "$ADE" restore > "$T/o2" 2>&1; rc=$?
    [ "$rc" = 1 ] && grep -q "is not a valid connections record" "$T/o2" || { cat "$T/o2"; fail "record $i ($code): restore exit $rc"; }
    bash "$ADE" work api < /dev/null > "$T/o3" 2>&1; rc=$?
    [ "$rc" = 1 ] && ! grep -q "hub work" "$T/o3" || { cat "$T/o3"; fail "record $i ($code): the gate let work run (exit $rc)"; }
    ! grep -Eq "plugin install|marketplace add|keys set|auth login|repair|schedule" "$FAKE_LOG" || { cat "$FAKE_LOG"; fail "record $i: something ran"; }
    [ ! -e "$T/PWNED" ] || fail "record $i ($code): a command from the record ran"
    ! grep -q "$(printf '\033')" "$T/o1" "$T/o2" "$T/o3" || fail "record $i: an escape sequence reached the terminal"
  done <<'EOF'
d["marketplaces"] = [{"name": "m", "repo": "--upload-pack=touch %s/PWNED;:" % T}]; d["plugins"] = [{"name": "git", "marketplace": "m", "ref": "x"}]
d["marketplaces"] = [{"name": "m", "repo": "--upload-pack=touch %s/PWNED;:" % T}]; d["plugins"] = [{"name": "git", "marketplace": "m", "ref": "v0.1.0"}]
d["marketplaces"] = [{"name": "ade-skills", "repo": "https://evil.example/attacker/skills"}]
d["marketplaces"] = [{"name": "ade-skills", "repo": "https://github.com/attacker/skills"}]
d["marketplaces"] = [{"name": "ade-skills", "repo": "attacker/skills"}]
d["marketplaces"] = [{"name": "m", "repo": "https://user:tok@github.com/a/b"}]
d["marketplaces"] = [{"name": "m", "repo": "https://github.com/../b"}]
d["marketplaces"] = [{"name": "m", "repo": "local"}]
d["marketplaces"] = [{"name": "m", "repo": ["https://github.com/a/b"]}]
d["plugins"][0]["ref"] = "x"
d["plugins"][0]["ref"] = "v0.1.0; touch %s/PWNED" % T
d["plugins"][0]["name"] = "git$(touch %s/PWNED)" % T
d["plugins"][0]["name"] = "--help"
d["plugins"][0]["marketplace"] = "nowhere"
d["plugins"] = [1]
d["plugins"] = [{"name": "p%d" % n, "marketplace": "ade-skills", "ref": "v0.1.0"} for n in range(100)]
d["account"] = "x"
d["account"]["label"] = "work\x1b]0;pwned\x07"
d["account"]["fingerprint"] = "not-a-fingerprint"
d["focus"] = "deepseek"
d["focus"] = [{"provider": "deepseek", "sign_in": "key"}, {"provider": "deepseek", "sign_in": "key"}]
d["focus"][0]["provider"] = "Deep Seek"
d["top"]["sign_in"] = "token"
d["channels"][0]["bot"] = "@acme_bot\n"
d["services"] = ["chat; rm -rf ~"]
d["evil"] = 1
d["format"] = 2
d["format"] = True
d["pins"] = {"ade-method": "main"}
EOF
  fresh; restore_fixture; signed_in u-1 o-1; mkdir -p "$H/.ade"
  for raw in '{"format": 1, "format": 1}' 'not json' '[1, 2]' "{\"format\": 1, \"specialists\": [\"$(printf 'a%.0s' $(seq 1 70000))\"]}"; do
    printf '%s\n' "$raw" > "$H/.ade/connections.json"
    bash "$ADE" restore --check < /dev/null > "$T/o1" 2>&1; assert_eq "$?" 1 "raw record ${raw:0:30}: rejected"
    assert_contains "$T/o1" "is not a valid connections record" "raw record ${raw:0:30}: says so"
    bash "$ADE" work api < /dev/null > "$T/o3" 2>&1; assert_eq "$?" 1 "raw record ${raw:0:30}: the gate fails closed"
  done
}

no_regex_from_record() {   # a name is compared whole, never used as a pattern
  fresh; restore_fixture; signed_in u-1 o-1; : > "$KEYSTORE/deepXseek"; mkdir -p "$HOME/.claude/plugins"; echo ade-skills > "$HOME/.claude/plugins/mkt"
  record_with 'd["focus"] = [{"provider": "deep.seek", "sign_in": "key"}]; d["marketplaces"] = [{"name": "skills", "repo": "acme/skills"}]; d["plugins"] = []'
  bash "$ADE" restore --check < /dev/null > "$T/out" 2>&1
  assert_contains "$T/out" "key deep.seek: missing" "deep.seek is not deepXseek"
  assert_contains "$T/out" "marketplace skills: missing" "skills is not ade-skills"
}

check_changes_nothing() {   # AC7: one line per connection, nothing changed
  fresh; restore_fixture; write_record; signed_in u-1 o-1
  : > "$T/out"; before="$(cd "$T" && find . -path ./fake.log -prune -o -print | sort)"
  bash "$ADE" restore --check < /dev/null > "$T/out" 2>&1; assert_eq "$?" 1 "gaps: exit 1"
  for l in "account work: ready" "provider anthropic: ready" "key deepseek: missing" "marketplace ade-skills: missing" "plugin git@ade-skills: missing" \
    "channel telegram: missing" "service chat: missing" "service monitor: missing"; do assert_contains "$T/out" "$l" "line: $l"; done
  assert_eq "$(cd "$T" && find . -path ./fake.log -prune -o -print | sort)" "$before" "nothing changed"
  ! grep -Eq "keys set|plugin install|marketplace add|schedule|chat setup|live-test" "$FAKE_LOG" || fail "no change and no live test"
}

twice_nothing() {   # AC8
  fresh; restore_fixture; write_record; signed_in u-1 o-1
  pty_run 'y\nsk-deep-good-1234567890\ny\ny\ntok-new-123456\ny\n' bash "$ADE" restore > /dev/null 2>&1
  bash "$ADE" restore < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "second restore"; }
  assert_contains "$T/out" "nothing to restore" "nothing to do (and nothing to ask, so no terminal needed)"
  bash "$ADE" restore --check < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "check after restore"; }
  assert_not_contains "$T/out" "missing" "all ready"
}

refusals() {   # no record, a bad label, unknown flags
  fresh; restore_fixture; bash "$ADE" restore < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "no record"
  assert_contains "$T/out" "no .ade/connections.json" "says so"
  write_record; bash "$ADE" restore --label $'a\nb' > /dev/null 2>&1; assert_eq "$?" 2 "a label with a newline"
  bash "$ADE" restore --label home > /dev/null 2>&1 || fail "label set"
  assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["account"]["label"])' "$H/.ade/connections.json")" home "label"
  bash "$ADE" restore --nope > /dev/null 2>&1; assert_eq "$?" 2 "unknown flag"
}

restore_other_steps() {   # the other steps: account continued, Claude sign-in, a marketplace alone, failures reported
  fresh; restore_fixture; rm -f "$HOME/.claude.json"   # not signed in at all
  record_with 'd["focus"] = [{"provider": "gemini", "sign_in": "account"}]; d["plugins"] = []; d["services"] = ["chat"]'
  printf '#!/bin/bash\necho "chat $*" >> "$FAKE_LOG"\n[ "$1 $2" = "info telegram" ] && echo "bot @acme_bot"\n[ "$1" = setup ] && exit 1\nexit 0\n' > "$H/bin/chat"
  printf '#!/bin/bash\necho "schedule $*" >> "$FAKE_LOG"; exit 1\n' > "$H/bin/schedule"
  bash "$ADE" restore --check < /dev/null > "$T/out" 2>&1
  assert_contains "$T/out" "provider anthropic: missing (not signed in)" "not signed in"
  assert_contains "$T/out" "provider gemini: unknown (signed in through its own CLI)" "a CLI's own sign-in cannot be checked"
  pty_run 'c\ny\ny\ny\ntok-x-123456\ny\n' bash "$ADE" restore > "$T/out" 2>&1; assert_eq "$?" 1 "failures: exit 1"
  assert_contains "$T/out" "account work: ready" "continued with this account"
  assert_contains "$FAKE_LOG" "claude auth login" "signed in"; assert_contains "$T/out" "provider anthropic: ready" "then ready"
  assert_contains "$FAKE_LOG" "claude plugin marketplace add -- $K" "a marketplace with no missing plugin, alone"
  assert_contains "$T/out" "marketplace ade-skills: ready" "ready"
  assert_contains "$T/out" "channel telegram: failed (bin/chat setup telegram --repair)" "a failed re-pair"
  assert_contains "$T/out" "services chat: failed (bin/schedule install)" "a failed install"
  # sign in to the recorded account, but Claude Code ends on yet another one
  fresh; restore_fixture; write_record; signed_in u-2 o-2; export LOGIN_USER=u-3 LOGIN_ORG=o-3
  pty_run 's\n' bash "$ADE" work api > "$T/out" 2>&1; assert_eq "$?" 1 "still another account"
  assert_contains "$T/out" "still signed in to another account than work" "says so"; assert_not_contains "$T/out" "hub work" "bin/work not run"
  # the marketplace is already here: a recorded ref no longer published still warns
  fresh; restore_fixture; write_record v0.0.9; signed_in u-1 o-1; mkdir -p "$HOME/.claude/plugins"; echo ade-skills > "$HOME/.claude/plugins/mkt"
  pty_run 'n\ny\nn\nn\n' bash "$ADE" restore > "$T/out" 2>&1; assert_contains "$T/out" "v0.0.9 is no longer published; installing the latest" "warns"
  # a checkout the hub's ACCESS.md lists, with its own record
  fresh; restore_fixture; write_record; signed_in u-1 o-1; W="$T/webrepo"; git init -q "$W"; mkdir -p "$W/.ade" "$H/projects/web"
  echo '{"format": 1, "plugins": [{"name": "notes", "marketplace": "ade-skills", "ref": "v0.1.0"}]}' > "$W/.ade/connections.json"
  printf '| Repo | Checkout | Branch |\n|---|---|---|\n| o/web | %s | main |\n' "$W" > "$H/projects/web/ACCESS.md"
  bash "$ADE" restore --check < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "plugin notes@ade-skills in $W: missing" "the checkout's record is read"
}

ALL="record_kept_current record_repo_public_only fresh_machine terminal_only account_skipped_stops account_gate account_config_dir
  keys_live_tested plugin_versions project_records other_marketplace hostile_records no_regex_from_record check_changes_nothing
  twice_nothing refusals restore_other_steps"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
