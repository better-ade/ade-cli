#!/bin/bash
# story A10: .ade/connections.json and ade restore. Fakes for claude (account, plugins), the hub's secrets store
# (bin/keys), bin/agent --live-test, bin/chat, bin/schedule and bin/journal; never the network, never a real key store.
. "$(dirname "$0")/helpers.sh"

restore_fixture() {
  make_skills_repo; H="$T/hub"; make_hub "$H" hub; printf 'HUB_NAME=acme\nHUB_ROOT_MODEL=opus\n' > "$H/hub.conf"
  git init -q "$H"; mkdir -p "$H/projects/api" "$T/fakebin" "$T/keystore" "$T/LA"
  export FAKE_LOG="$T/fake.log" KEYSTORE="$T/keystore" AGENT_LAUNCHAGENTS="$T/LA" ADE_GEMINI_CLI=no-gemini-cli-here; : > "$FAKE_LOG"
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
  cat > "$T/fakebin/claude" <<'F'
#!/bin/bash
echo "claude $*" >> "$FAKE_LOG"; P="$HOME/.claude/plugins"
case "$1 ${2:-} ${3:-}" in
  "auth status "*) [ -f "$HOME/.claude.json" ] ;;
  "auth login "*) printf '{"oauthAccount": {"accountUuid": "%s", "organizationUuid": "%s", "emailAddress": "owner@example.com"}}\n' \
      "${LOGIN_USER:-u-1}" "${LOGIN_ORG:-o-1}" > "$HOME/.claude.json" ;;
  "plugin marketplace list") cat "$P/mkt" 2> /dev/null ;;
  "plugin marketplace add") mkdir -p "$P"; echo ade-skills >> "$P/mkt" ;;
  "plugin install "*) mkdir -p "$P"; python3 -c 'import json,os,sys; p=sys.argv[1]; d=json.load(open(p)) if os.path.exists(p) else {"version": 2, "plugins": {}}
d["plugins"][sys.argv[2]] = [{"scope": "project"}]; json.dump(d, open(p, "w"))' "$P/installed_plugins.json" "$3" ;;
  *) echo "session $*" ;;
esac
F
  for c in launchctl systemctl; do printf '#!/bin/bash\necho "%s $*" >> "$FAKE_LOG"\n' "$c" > "$T/fakebin/$c"; done
  chmod +x "$T/fakebin/"* "$H/bin/"*; export PATH="$T/fakebin:$PATH" ADE_HUB="$H"
}
signed_in() { printf '{"oauthAccount": {"accountUuid": "%s", "organizationUuid": "%s", "emailAddress": "owner@example.com"}}\n' "$1" "$2" > "$HOME/.claude.json"; }
fp() { printf 'ade-account-v1:%s:%s' "$2" "$1" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:16])'; }
# a record as a first machine left it: Claude account u-1/o-1, DeepSeek focus by key, Telegram, the git plugin,
# the chat and monitor services
write_record() {   # [plugin ref]
  mkdir -p "$H/.ade"; cat > "$H/.ade/connections.json" <<J
{
  "format": 1,
  "account": {"label": "work", "fingerprint": "$(fp u-1 o-1)"},
  "top": {"provider": "anthropic", "sign_in": "account", "model": "opus"},
  "focus": [{"provider": "deepseek", "sign_in": "key"}],
  "channels": [{"type": "telegram", "bot": "@acme_bot"}],
  "marketplaces": [{"name": "ade-skills", "repo": "$ADE_SKILLS_REPO"}],
  "plugins": [{"name": "git", "marketplace": "ade-skills", "ref": "${1:-v0.1.0}"}],
  "services": ["chat", "monitor"]
}
J
}
secret_free() {   # <file>: no key-shaped value, token, email or account id
  ! grep -Eq 'sk-|tok-|bot[0-9]+:|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}|"u-1"|"o-1"|accountUuid|organizationUuid' "$1" || { cat "$1"; fail "$2: a secret, email or account id in the record"; }
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
  printf 'y\ntok-secret-123456\n' | bash "$ADE" setup --telegram > "$T/out" 2>&1 || { cat "$T/out"; fail "setup --telegram"; }
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
assert any(m["name"] == "ade-skills" for m in d["marketplaces"]), d
assert d["specialists"] == ["frontend"], d
assert d["pins"]["ade-method"] == "v2.0.0" and d["pins"]["ade-agent-registry"] == "v1.1.0" and d["pins"]["ade-skills"] == "v0.1.0", d
PY
  secret_free "$R" "after setup"
  P="$T/proj"; mkdir -p "$P"; git init -q "$P"; (cd "$P" && bash "$ADE" init > /dev/null 2>&1) || fail "init in a project"
  [ -f "$P/.ade/connections.json" ] && secret_free "$P/.ade/connections.json" "project" || fail "init records the project's pins"
}

fresh_machine() {   # AC2 + AC6: every gap listed, then fixed with a yes each; Telegram re-pairs
  fresh; restore_fixture; write_record; signed_in u-1 o-1
  printf 'y\nsk-deep-good-1234567890\ny\ny\ntok-new-123456\ny\n' | bash "$ADE" restore > "$T/out" 2>&1 || { cat "$T/out"; fail "restore exit"; }
  for g in "key deepseek: missing" "plugin git@ade-skills: missing" "channel telegram: missing" "service chat: missing" "service monitor: missing"; do
    assert_contains "$T/out" "$g" "listed: $g"; done
  assert_eq "$(cat "$KEYSTORE/deepseek")" "sk-deep-good-1234567890" "the key went to bin/keys"
  assert_contains "$FAKE_LOG" "agent --live-test deepseek" "then live-tested"
  assert_contains "$FAKE_LOG" "claude plugin marketplace add" "marketplace back"; assert_contains "$FAKE_LOG" "claude plugin install git@ade-skills" "plugin back"
  assert_eq "$(cat "$KEYSTORE/telegram")" "tok-new-123456" "the bot token went to bin/keys"
  assert_contains "$FAKE_LOG" "chat setup telegram --repair" "Telegram re-pairs"
  ! grep -q "chat setup telegram$" "$FAKE_LOG" || fail "never the old pairing"
  assert_contains "$FAKE_LOG" "schedule install" "services reinstalled"; [ -f "$T/LA/ai.agent-hub.acme.chat.plist" ] || fail "service back"
  assert_contains "$T/out" "deepseek: ready" "a step ends ready"
  for f in "$T/out" "$FAKE_LOG" "$H/.ade/connections.json"; do assert_not_contains "$f" "sk-deep-good" "no key in $f"; assert_not_contains "$f" "tok-new" "no token in $f"; done
  assert_contains "$H/journal.log" "ade restore" "journaled"
}

account_gate() {   # AC3: another Claude account stops connection-needing commands until answered; remembered
  fresh; restore_fixture; write_record; signed_in u-2 o-2
  bash "$ADE" work api < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "stopped without an answer"
  assert_contains "$T/out" "set up with work" "the question names the label"; assert_not_contains "$T/out" "hub work" "bin/work not run"
  bash "$ADE" claude < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "ade claude stopped too"
  printf 'c\n' | bash "$ADE" work api > "$T/out" 2>&1 || { cat "$T/out"; fail "continue"; }; assert_contains "$T/out" "hub work" "continued"
  bash "$ADE" work api < /dev/null > "$T/out" 2>&1 || fail "the answer is remembered"; assert_contains "$T/out" "hub work" "no question again"
  bash "$ADE" restore --check < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "account work: different (continuing with this account)" "check says so"
  fresh; restore_fixture; write_record; signed_in u-2 o-2; export LOGIN_USER=u-1 LOGIN_ORG=o-1
  printf 's\n' | bash "$ADE" work api > "$T/out" 2>&1 || { cat "$T/out"; fail "sign in"; }
  assert_contains "$FAKE_LOG" "claude auth login" "signed in to the recorded account"; assert_contains "$T/out" "hub work" "then runs"
  fresh; restore_fixture; signed_in u-2 o-2; bash "$ADE" work api < /dev/null > "$T/out" 2>&1 || fail "no record, no gate"
}

keys_live_tested() {   # AC4: hidden prompt, bin/keys only, live test; a failed one leaves the roles with the reason
  fresh; restore_fixture; write_record; signed_in u-1 o-1; echo "HUB_PROVIDERS_ALLOWED='anthropic deepseek'" >> "$H/hub.conf"
  printf 'y\nsk-bad-key-1234567890\nn\nn\nn\n' | bash "$ADE" restore > "$T/out" 2>&1
  assert_contains "$T/out" "deepseek: failed (agent: the key was rejected (401))" "the reason"
  assert_contains "$T/out" "left out of the roles" "says so"
  assert_eq "$(. "$H/hub.conf"; echo "$HUB_PROVIDERS_ALLOWED")" anthropic "out of the roles"
  assert_not_contains "$T/out" "sk-bad-key" "never echoed"; assert_contains "$T/out" "still needs you" "the summary lists it"
}

plugin_versions() {   # AC5: the recorded version; one no longer published falls back to the latest with a warning
  fresh; restore_fixture; write_record v0.0.9; signed_in u-1 o-1
  printf 'n\ny\nn\nn\n' | bash "$ADE" restore > "$T/out" 2>&1
  assert_contains "$T/out" "v0.0.9 is no longer published" "warns"; assert_contains "$FAKE_LOG" "claude plugin install git@ade-skills" "installs the latest"
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
  printf 'y\nsk-deep-good-1234567890\ny\ny\ntok-new-123456\ny\n' | bash "$ADE" restore > /dev/null 2>&1
  bash "$ADE" restore < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "second restore"; }
  assert_contains "$T/out" "nothing to restore" "nothing to do"
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

ALL="record_kept_current fresh_machine account_gate keys_live_tested plugin_versions check_changes_nothing twice_nothing refusals"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
