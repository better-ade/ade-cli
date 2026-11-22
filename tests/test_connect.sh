#!/bin/bash
# story A16: ade connect. A local ade-skills tagged v0.7.0 with recipe fixtures (the contract's jira, github and gmail
# examples, and held ones), that release's release.json in a file:// folder, a fake claude and a fake gh; never the
# network, never a real account, keychain, gh or Claude Code.
. "$(dirname "$0")/helpers.sh"

JIRA='{
  "format": 1, "service": "jira", "title": "Jira", "job": "tickets", "tier": 0, "state": "ready",
  "sign_in": { "kind": "plugin", "plugin": "jira" },
  "questions": [],
  "guard": { "prefixes": ["mcp__plugin_jira_jira__"], "read": ["atlassianUserInfo", "getJiraIssue", "searchJiraIssuesUsingJql"] },
  "hosts": ["mcp.atlassian.com"],
  "pages": { "docs": "https://support.atlassian.com/atlassian-ai-gateway/docs/get-started-with-the-atlassian-remote-mcp-server/",
             "revoke": "https://id.atlassian.com/manage-profile/apps" },
  "reaches": "Every Atlassian app you can reach on the sites you allow, with your permissions; changes ask each time."
}'
GITHUB='{
  "format": 1, "service": "github", "title": "GitHub", "job": "code", "tier": 2, "state": "ready",
  "sign_in": { "kind": "cli", "cli": "gh", "plugin": "github" },
  "questions": [],
  "guard": { "prefixes": [], "read": [],
    "commands": {
      "gh": { "free": [{"words": ["pr", "view"], "flags": ["--repo=", "-R=", "--json=", "--comments"], "args": "any"},
                       {"words": ["auth", "status"], "flags": [], "args": "none"}],
              "deny": [["auth", "token"], ["auth", "status", "--show-token"], ["auth", "status", "-t"]] },
      "git": { "free": [{"words": ["status"], "flags": ["-s", "--porcelain=v2"], "args": "any"},
                        {"words": ["switch"], "flags": ["-c=", "-"], "args": "any"},
                        {"words": ["fetch"], "flags": ["--all", "--prune"], "args": "names"}],
               "deny": [["credential", "fill"]] } } },
  "hosts": ["api.githubcopilot.com"],
  "pages": {},
  "reaches": "Every repository your gh sign-in can reach; pushing, merging, releases, settings and secrets ask each time."
}'
GMAIL='{
  "format": 1, "service": "gmail", "title": "Gmail", "job": "mail", "tier": 2, "state": "ready",
  "sign_in": { "kind": "claude-ai", "connector": "Gmail" },
  "questions": [{ "id": "added", "to": "gate",
                  "ask": "Have you added the Gmail connector to your Claude account and signed in to it there?" }],
  "guard": { "prefixes": ["mcp__claude_ai_Gmail__"], "read": ["get_message", "get_thread", "search_threads"] },
  "hosts": ["gmailmcp.googleapis.com"],
  "pages": {},
  "reaches": "The mail of the Google account signed in to the connector; drafting, labels, trash and spam ask each time."
}'
SLACK='{ "format": 1, "service": "slack", "title": "Slack", "job": "chat", "tier": 1, "state": "held",
  "held": "the owner decides on Slack'"'"'s published client id first",
  "sign_in": { "kind": "plugin", "plugin": "slack" }, "reaches": "The channels you are in." }'
OUTLOOK='{ "format": 1, "service": "outlook", "title": "Outlook", "job": "mail", "tier": 4, "state": "held",
  "held": "a tenant administrator must act, and the server is legacy",
  "sign_in": { "kind": "plugin", "plugin": "outlook", "admin": "register the app in Entra ID and grant Mail.ReadWrite to the tenant" },
  "reaches": "The mailbox of your work account." }'

# recipe <service> <json> [file name]: one recipe in the fixture's plugins/guard/connectors
recipe() { printf '%s\n' "$2" > "$K/plugins/guard/connectors/${3:-$1.json}"; }
# release [skip]: commit, tag v0.7.0 (moved), and write its release.json naming every recipe's sha256 (but skip's)
release() {
  git -C "$K" add -A && git -C "$K" commit -qm "release ${1:-}" --allow-empty && git -C "$K" tag -f v0.7.0 > /dev/null || fail "tag"
  local d="$T/gh/better-ade/ade-skills/releases/download/v0.7.0"; mkdir -p "$d"
  python3 - "$K/plugins/guard/connectors" "$d/release.json" "${1:-}" <<'PY'
import hashlib, json, os, sys
src, out, skip = sys.argv[1:4]
files = [{"name": "connector-" + n, "url": "https://example.invalid/" + n, "sha256": hashlib.sha256(open(os.path.join(src, n), "rb").read()).hexdigest()}
         for n in sorted(os.listdir(src)) if n != skip + ".json"]
json.dump({"component": "ade-skills", "version": "0.7.0", "released": "2026-11-22", "summary": "recipes", "urgency": "normal",
           "min_supported": None, "files": files}, open(out, "w"))
PY
}
connect_fixture() {
  make_skills_repo; mkdir -p "$K/plugins/guard/connectors"
  cat > "$K/.claude-plugin/marketplace.json" <<'JSON'
{ "name": "ade-skills", "plugins": [ { "name": "guard", "description": "The guard." }, { "name": "jira", "description": "Jira." },
  { "name": "github", "description": "GitHub through gh." }, { "name": "gmail", "description": "Gmail." }, { "name": "git", "description": "Git." } ] }
JSON
  mkdir -p "$K/plugins/guard/hooks"; echo '{"hooks": {}}' > "$K/plugins/guard/hooks/hooks.json"; echo 'exit 0' > "$K/plugins/guard/hooks/guard.sh"
  recipe jira "$JIRA"; recipe github "$GITHUB"; recipe gmail "$GMAIL"; recipe slack "$SLACK"; recipe outlook "$OUTLOOK"; release
  export ADE_SKILLS_REF=v0.7.0 ADE_TEST_ALLOW_FILE_URLS=1 ADE_RELEASES_BASE="file://$T/gh"
  H="$T/hub"; make_hub "$H" hub; printf '#!/bin/bash\necho "$*" >> "$HUB/journal.log"\n' > "$H/bin/journal"; chmod +x "$H/bin/journal"; export ADE_HUB="$H"
  stub_claude   # then a richer fake in its place: installs land in Claude Code's list for the folder they run in
  cat > "$T/fakebin/claude" <<'F'
#!/bin/bash
echo "$* ANSWER=${ANSWER-unset}" >> "$CLAUDE_LOG"
P="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins"
case "$1 ${2:-} ${3:-}" in
  "plugin marketplace list") cat "$P/mkt" 2> /dev/null ;;
  "plugin marketplace add") mkdir -p "$P"; echo ade-skills >> "$P/mkt" ;;
  "plugin install "*) mkdir -p "$P"; python3 -c 'import json,os,sys; p=sys.argv[1]; d=json.load(open(p)) if os.path.exists(p) else {"version": 2, "plugins": {}}
d["plugins"].setdefault(sys.argv[2], []).append({"scope": "project", "projectPath": sys.argv[3], "version": "0.7.0"}); json.dump(d, open(p, "w"))' \
      "$P/installed_plugins.json" "$3" "$(pwd -P)" ;;
  "mcp logout "*) exit "${FAKE_LOGOUT_RC:-0}" ;;
esac
exit 0
F
  # a fake gh: signed in when $HOME/.gh-signed exists; auth status prints a token-shaped line ade must never show
  mkdir -p "$T/ghbin"; export GH_LOG="$T/gh.log"; : > "$GH_LOG"
  cat > "$T/ghbin/gh" <<'F'
#!/bin/bash
echo "gh $*" >> "$GH_LOG"
case "$*" in
  "auth status") [ -f "$HOME/.gh-signed" ] || { echo "You are not logged into any GitHub hosts." >&2; exit 1; }
    echo "github.com: Logged in to github.com account someone"; echo "  Token: gho_LEAKEDTOKEN123456"; exit 0 ;;
  "auth login") touch "$HOME/.gh-signed" ;;
  *token*) echo "gho_LEAKEDTOKEN123456" ;;
esac
exit 0
F
  chmod +x "$T/fakebin/claude" "$T/ghbin/gh"; export PATH="$T/fakebin:$T/ghbin:$PATH"
  P="$T/proj"; mkdir -p "$P"; git init -q "$P"; cd "$P" || fail "cd"
}
rec() { cat "$P/.ade/connectors.json" 2> /dev/null; }
installs() { grep -c '^plugin install' "$CLAUDE_LOG"; }
tree_sum() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done); }
conn() { pty_run "$1" bash "$ADE" connect "${@:2}" > "$T/out" 2>&1; }   # conn <typed answers> <args>: at a terminal

connect_lists() {   # AC1
  fresh; connect_fixture
  echo '{"format": 1, "service": "later", "title": "Later", "job": "chat", "tier": 0, "state": "held", "held": "x", "sign_in": {"kind": "cli", "cli": "gh"}, "reaches": "x"}' \
    > "$K/plugins/guard/connectors/later.json"; commit_tag "$K" "after the tag"   # on the branch, not at the pinned tag
  bash "$ADE" connect < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "list exit"; }
  for l in "jira +tickets +0 +ready +-" "github +code +2 +ready +-" "gmail +mail +2 +ready +-" "slack +chat +1 +held +-" "outlook +mail +4 +held +-"; do
    grep -Eq "^$l\$" "$T/out" || { cat "$T/out"; fail "row: $l"; }; done
  assert_eq "$(grep -Ec '^(jira|github|gmail|slack|outlook) ' "$T/out")" 5 "one row per recipe"
  assert_not_contains "$T/out" "later" "read at the pinned tag only"
  assert_contains "$T/out" "0  nothing to set up" "the tier key"; assert_contains "$T/out" "4  an administrator must act first" "every tier"
  mkdir -p "$P/.ade"; echo '{"format": 1, "connectors": ["jira"]}' > "$P/.ade/connectors.json"
  bash "$ADE" connect > "$T/out" 2>&1 || fail "list with a record"; grep -Eq '^jira +tickets +0 +ready +connected$' "$T/out" || { cat "$T/out"; fail "here"; }
  unset ADE_SKILLS_REF; bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "the default pin has no recipes yet"
  assert_eq "$(wc -l < "$T/out" | tr -d ' ')" 1 "says so in one line"; assert_contains "$T/out" "has no connectors yet" "the reason"
  ADE_SKILLS_REF=main bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "a branch is refused"; assert_contains "$T/out" "vX.Y.Z tag" "why"
}

# clickup <json object>: the jira recipe as clickup, with these fields put in, then released
clickup() {
  JIRA="$JIRA" python3 - "$1" "$K/plugins/guard/connectors/clickup.json" <<'PY2'
import json, os, sys
d = json.loads(os.environ["JIRA"].replace("jira", "clickup")); d.update(json.loads(sys.argv[1])); json.dump(d, open(sys.argv[2], "w"))
PY2
  release "$1"
}
connect_pins_and_refuses() {   # AC2
  fresh; connect_fixture; local m="$T/gh/better-ade/ade-skills/releases/download/v0.7.0/release.json" bad
  mv "$m" "$m.off"; bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "no manifest"; assert_contains "$T/out" "no release.json for ade-skills v0.7.0" "why"
  assert_eq "$(wc -l < "$T/out" | tr -d ' ')" 1 "in one line"
  sed 's/"ade-skills"/"ade-cli"/' "$m.off" > "$m"; bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "another component"
  sed 's/"0.7.0"/"0.7.1"/' "$m.off" > "$m"; bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "another version"
  assert_not_contains "$T/out" "jira" "nothing listed from an unverified pin"
  mv "$m.off" "$m"
  # a recipe changed after its sha256 was published: that one is refused, in one line; the rest are used
  recipe jira "$(printf '%s' "$JIRA" | sed 's/"title": "Jira"/"title": "Jira Cloud"/')"; git -C "$K" commit -qam tampered && git -C "$K" tag -f v0.7.0 > /dev/null
  bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "a mismatch exits 2"
  assert_eq "$(grep -c jira "$T/out")" 1 "one line for that recipe"; assert_contains "$T/out" "the recipe of jira is refused: its sha256 does not match" "why"
  grep -Eq '^github +code' "$T/out" || fail "the verified recipes are still listed"
  conn 'y\n' jira; assert_eq "$?" 2 "connect to a refused recipe"; assert_contains "$T/out" "the recipe of jira is refused" "says so"; assert_eq "$(installs)" 0 "nothing installed"
  release again; recipe linear '{"format": 1}'; release linear   # a recipe the manifest does not name
  bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "unnamed"; assert_contains "$T/out" "linear is refused: release.json names no sha256" "why"
  rm "$K/plugins/guard/connectors/linear.json"
  for bad in "{\"run\": \"touch $T/pwned\"}" '{"sign_in": {"kind": "proxy", "plugin": "clickup"}}' '{"format": 2}' '{"format": true}' \
    '{"questions": [{"id": "key", "ask": "Your key?", "to": "keychain"}]}' "{\"sign_in\": {\"kind\": \"plugin\", \"plugin\": \"clickup; touch $T/pwned\"}}" \
    '{"tier": 5}' '{"tier": "0"}' '{"job": "money"}' '{"guard": {"prefixes": [], "read": []}}' '{"state": "held"}' '{"tier": 4}' \
    '{"sign_in": {"kind": "plugin", "plugin": "clickup", "cli": "gh"}}' '{"pages": {"docs": "http://example.com"}}' '{"service": "jira"}' \
    '{"questions": [{"id": "a", "ask": "A?", "to": "gate"}, {"id": "b", "ask": "B?", "to": "gate"}, {"id": "c", "ask": "C?", "to": "gate"}]}' \
    '{"sign_in": {"kind": "plugin", "plugin": "git"}, "guard": {"prefixes": ["mcp__plugin_git_git__"], "read": []}}' \
    '{"sign_in": {"kind": "claude-ai", "connector": "ClickUp"}, "guard": {"prefixes": ["mcp__claude_ai_Other__"], "read": []}}' \
    '{"sign_in": {"kind": "cli", "cli": "gh"}, "guard": {"prefixes": ["mcp__plugin_clickup_clickup__"], "read": []}}' \
    '{"sign_in": {"kind": "cli", "cli": "gh"}, "guard": {"prefixes": [], "read": ["getIssue"]}}' \
    '{"guard": {"prefixes": ["mcp__plugin_clickup_clickup__"], "read": [], "commands": {"gh": {"free": [], "deny": []}}}}' \
    '{"guard": {"prefixes": ["mcp__plugin_clickup_clickup__", "mcp__claude_ai_ClickUp__"], "read": []}}' \
    '{"sign_in": {"kind": "claude-ai", "connector": "ClickUp"}, "guard": {"prefixes": ["mcp__claude_ai_ClickUp__", "mcp__claude_ai_Other__"], "read": []}}' \
    '{"sign_in": {"kind": "cli", "cli": "gh"}, "guard": {"prefixes": [], "read": []}}' \
    '{"sign_in": {"kind": "cli", "cli": "gh"}, "guard": {"prefixes": [], "read": [], "commands": {"gh": {"free": [["pr", "view"]], "deny": []}}}}' \
    '{"sign_in": {"kind": "cli", "cli": "gh"}, "guard": {"prefixes": [], "read": [], "commands": {"gh": {"free": [{"words": ["pr"], "flags": ["--x"], "args": "all"}], "deny": []}}}}' \
    '{"sign_in": {"kind": "cli", "cli": "gh"}, "guard": {"prefixes": [], "read": [], "commands": {"gh": {"free": [{"words": ["pr"], "flags": ["-x;y"], "args": "any"}], "deny": []}}}}' \
    '{"sign_in": {"kind": "cli", "cli": "gh"}, "guard": {"prefixes": [], "read": [], "commands": {"gh": {"free": [{"words": ["pr"], "flags": [], "args": "any", "run": "x"}], "deny": []}}}}' \
    '{"sign_in": {"kind": "cli", "cli": "gh"}, "guard": {"prefixes": [], "read": [], "commands": {"gh": {"free": [{"words": ["pr"], "flags": [], "args": "any"}, {"words": ["pr"], "flags": [], "args": "none"}], "deny": []}}}}' \
    '{"sign_in": {"kind": "cli", "cli": "gh"}, "guard": {"prefixes": [], "read": [], "commands": {"gh": {"free": [], "deny": [["a", "b", "c", "d", "e"]]}}}}' \
    '{"sign_in": {"kind": "cli", "cli": "gh"}, "guard": {"prefixes": [], "read": [], "commands": {"sh": {"free": [], "deny": []}}}}' \
    '{"hosts": ["mcp.example.com\u200b"]}' \
    '{"reaches": "one\u2028two"}' '{"title": "Click\ue000Up"}' '{"held": "x", "state": "held", "sign_in": {"kind": "plugin", "plugin": "clickup", "admin": "a\u200bb"}}'; do
    clickup "$bad"; bash "$ADE" connect > "$T/out" 2>&1
    assert_eq "$?" 2 "[$bad] refused"; assert_eq "$(grep -c 'clickup is refused' "$T/out")" 1 "[$bad] in one line"
    grep -Eq '^jira +tickets' "$T/out" || { cat "$T/out"; fail "[$bad] others still listed"; }
  done
  printf '%s' "$JIRA" | sed 's/"jira"/"clickup"/g; s/"format": 1,/"format": 1, "format": 1,/' > "$K/plugins/guard/connectors/clickup.json"; release twice
  bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "a key twice"; assert_contains "$T/out" "clickup is refused: a key appears twice" "why"
  clickup "{\"reaches\": \"\$(touch $T/pwned) \`touch $T/pwned\`\"}"   # valid text: shown as it is, never run
  bash "$ADE" connect > "$T/out" 2>&1 || { cat "$T/out"; fail "a recipe with shell text is data"; }
  conn 'n\n' clickup; assert_contains "$T/out" "reaches: \$(touch $T/pwned)" "printed as text"
  [ ! -e "$T/pwned" ] || fail "nothing in a recipe is run"
  rm "$K/plugins/guard/connectors/clickup.json"; ln -s jira.json "$K/plugins/guard/connectors/clickup.json"; release link
  bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "a link"; assert_contains "$T/out" "clickup is refused: it is not a plain file" "only regular files"
  rm "$K/plugins/guard/connectors/clickup.json"
  # across files: one failure refuses the whole folder (exit 2, nothing listed)
  for bad in '{"guard": {"prefixes": ["mcp__plugin_clickup_clickup__", "mcp__plugin_jira_jira__x__"], "read": []}}' \
    '{"sign_in": {"kind": "claude-ai", "connector": "Gmail"}, "guard": {"prefixes": ["mcp__claude_ai_Gmail__"], "read": []}}' \
    "{\"sign_in\": {\"kind\": \"cli\", \"cli\": \"gh\"}, \"guard\": $(printf '%s' "$GITHUB" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["guard"]))')}"; do
    clickup "$bad"; bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "[$bad] refuses the folder"
    assert_contains "$T/out" "the recipes of ade-skills v0.7.0 are refused together" "[$bad] why"; assert_not_contains "$T/out" "tickets" "[$bad] nothing listed"
  done
  rm "$K/plugins/guard/connectors/clickup.json"; rm "$K/plugins/guard/hooks/guard.sh"; release nohook
  bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "no guard hook, a ready recipe"; assert_contains "$T/out" "has no guard hook" "why"
}

connect_plugin() {   # AC3
  fresh; connect_fixture; mkdir -p "$P/sub"; cd "$P/sub" || fail "cd"
  conn 'y\n' jira || { cat "$T/out"; fail "connect jira"; }
  assert_contains "$CLAUDE_LOG" "plugin install guard@ade-skills --scope project" "the guard, project scope"
  assert_contains "$CLAUDE_LOG" "plugin install jira@ade-skills --scope project" "the plugin, project scope"
  assert_eq "$(rec)" '{"format": 1, "connectors": ["jira"]}' "the name, at the git top level"
  for s in "Connect jira in $P?" "reaches: Every Atlassian app" "Reading needs no question; every change asks." \
    "If you also add Jira as a connector to your Claude account, the guard does not cover that connector's tools: Claude Code's own permission settings decide for them, in every folder." "docs: https://support.atlassian.com/" \
    "run /mcp, pick plugin:jira:jira, choose Authenticate, and sign in in the browser"; do assert_contains "$T/out" "$s" "prints: $s"; done
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); n=sorted(p["name"] for p in d["plugins"]); assert n == ["guard", "jira"], n' "$P/.ade/connections.json" || fail "recorded as ade skills add does"
  assert_eq "$(grep -c 'ade connect: jira connected in proj' "$H/journal.log")" 1 "one journal line"
  local before n; before="$(tree_sum "$P")"; n="$(installs)"
  conn 'y\n' jira || { cat "$T/out"; fail "again"; }
  assert_eq "$(tree_sum "$P")" "$before" "rerunning changes nothing in the folder"; assert_eq "$(installs)" "$n" "nor installs again"
  assert_eq "$(grep -c 'ade connect: jira' "$H/journal.log")" 1 "nor journals again"
}

connect_cli() {   # AC4
  fresh; connect_fixture
  conn 'y\nn\n' github; assert_eq "$?" 1 "not signed in and no: exit 1"; assert_contains "$T/out" "run gh auth login yourself" "what to run"
  assert_eq "$(rec)" "" "not recorded"; assert_contains "$GH_LOG" "gh auth status" "the read-only check"
  assert_not_contains "$GH_LOG" "auth login" "never started without a yes"
  touch "$HOME/.gh-signed"; : > "$GH_LOG"
  conn 'y\n' github || { cat "$T/out"; fail "signed in"; }
  assert_eq "$(rec)" '{"format": 1, "connectors": ["github"]}' "recorded"; assert_contains "$T/out" "gh is signed in" "says so"
  assert_contains "$T/out" "Reading, fetching and ordinary local git work need no question; pushing and every other change on GitHub asks in this folder." "the cli card"
  assert_contains "$CLAUDE_LOG" "plugin install github@ade-skills" "its skill"
  assert_eq "$(sort -u "$GH_LOG")" "gh auth status" "only the read-only check: no login, logout or token"
  rm "$HOME/.gh-signed"; Q="$T/other"; mkdir -p "$Q"; git init -q "$Q"; cd "$Q" || fail "cd"; : > "$GH_LOG"
  conn 'y\ny\n' github || { cat "$T/out"; fail "sign in now"; }
  assert_eq "$(grep -c 'gh auth login' "$GH_LOG")" 1 "gh auth login runs on the terminal after a yes (the contract, section 2 step 8)"
  for f in "$T/out" "$Q/.ade/connectors.json" "$Q/.ade/connections.json" "$CLAUDE_LOG"; do assert_not_contains "$f" "gho_" "no token in $f"; done
  assert_not_contains "$GH_LOG" "token" "never gh auth token"
  cd "$P" || fail "cd"; : > "$CLAUDE_LOG"; PATH="$T/fakebin:$(no_gh_path)" pty_run 'y\ny\n' "$BASH" "$ADE" connect github > "$T/out" 2>&1
  assert_eq "$?" 1 "gh missing"; assert_contains "$T/out" "ade setup --tools" "what to run"; assert_eq "$(installs)" 0 "nothing installed"
}

connect_claude_ai() {   # AC5
  fresh; connect_fixture
  conn 'n\n' gmail; assert_eq "$?" 1 "the gate answered no"; assert_eq "$(installs)" 0 "nothing installed"; assert_eq "$(rec)" "" "nothing recorded"
  conn 'y\ny\n' gmail || { cat "$T/out"; fail "connect gmail"; }
  assert_contains "$T/out" "Have you added the Gmail connector" "the gate"
  assert_contains "$T/out" "Reading needs no question; every change asks, in folders where ade installed the guard. In other folders, Claude Code's own permission settings decide." "the claude-ai card"
  assert_contains "$CLAUDE_LOG" "plugin install guard@ade-skills --scope project" "the guard"; assert_eq "$(installs)" 1 "no skill named: the guard only"
  assert_eq "$(rec)" '{"format": 1, "connectors": ["gmail"]}' "recorded"
  assert_contains "$T/out" "the Gmail connector is on in your Claude account (claude.ai, Settings, Connectors)" "where it is turned on"
  assert_contains "$T/out" "shared by every folder of that account; ade cannot see that sign-in" "claims nothing it cannot see"
  assert_not_contains "$T/out" "signed in to Gmail" "no claim"
  recipe gmail "$(printf '%s' "$GMAIL" | sed 's/"connector": "Gmail"/"connector": "Gmail", "plugin": "gmail"/')"; release skill   # K7's skill
  conn 'y\ny\n' gmail || { cat "$T/out"; fail "with its skill"; }; assert_contains "$CLAUDE_LOG" "plugin install gmail@ade-skills --scope project" "the skill"
}

connect_held() {   # AC6
  fresh; connect_fixture
  conn 'y\n' slack; assert_eq "$?" 3 "held exits 3"; assert_contains "$T/out" "slack is not available yet: the owner decides on Slack's published client id first" "its reason"
  conn 'y\n' outlook; assert_eq "$?" 3 "tier 4 exits 3"
  assert_contains "$T/out" "Your administrator must first: register the app in Entra ID" "what the administrator must do"
  assert_contains "$T/out" "ade sends nothing; forward this yourself." "sends nothing"; assert_not_contains "$T/out" "Connect outlook" "asks nothing"
  assert_eq "$(wc -c < "$CLAUDE_LOG" | tr -d ' ')" 0 "claude never ran"; assert_eq "$(wc -c < "$GH_LOG" | tr -d ' ')" 0 "gh never ran"
  [ ! -e "$H/journal.log" ] && [ ! -e "$P/.ade" ] || fail "nothing written"
  # github and gmail as the first release ships them (contract amendment 1): held
  recipe github "$(printf '%s' "$GITHUB" | sed 's/"state": "ready",/"state": "held", "held": "Not available until the guard'"'"'s hook and the GitHub skill ship in ade-skills.",/; s/, "plugin": "github"//')"
  recipe gmail "$(printf '%s' "$GMAIL" | sed 's/"state": "ready",/"state": "held", "held": "Not available until the guard'"'"'s hook and the Gmail skill ship in ade-skills.",/')"; release shipped
  conn 'y\n' github; assert_eq "$?" 3 "github held"; assert_contains "$T/out" "github is not available yet: Not available until the guard's hook and the GitHub skill ship" "why"
  conn 'y\ny\n' gmail; assert_eq "$?" 3 "gmail held"; assert_not_contains "$T/out" "Have you added" "no question for a held service"
  assert_eq "$(wc -c < "$GH_LOG" | tr -d ' ')" 0 "gh never ran"; [ ! -e "$P/.ade" ] || fail "nothing written"
  mkdir -p "$P/.ade"; echo '{"format": 1, "connectors": ["github", "slack"]}' > "$P/.ade/connectors.json"
  bash "$ADE" connect status > "$T/out" 2>&1; assert_eq "$?" 1 "a held service is a gap"
  assert_contains "$T/out" "connector slack: missing (held: the owner decides on Slack's published client id first)" "status says held"
  assert_contains "$T/out" "connector github: missing (held: Not available until" "github too"
}

connect_terminal_only() {   # AC7
  fresh; connect_fixture
  bash "$ADE" connect jira < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "no terminal"; assert_contains "$T/out" "refuses piped or missing answers" "why"
  printf 'y\ny\n' | bash "$ADE" connect jira > "$T/out" 2>&1; assert_eq "$?" 2 "piped answers"
  CLAUDECODE=1 pty_run 'y\n' bash "$ADE" connect jira > "$T/out" 2>&1; assert_eq "$?" 2 "an agent session"; assert_contains "$T/out" "inside a Claude Code session" "why"
  CLAUDE_CODE_ENTRYPOINT=cli pty_run 'y\n' bash "$ADE" connect disconnect jira > "$T/out" 2>&1; assert_eq "$?" 2 "disconnect in an agent session"
  bash "$ADE" connect disconnect jira < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "disconnect without a terminal"
  assert_eq "$(wc -c < "$CLAUDE_LOG" | tr -d ' ')" 0 "nothing ran"; [ ! -e "$P/.ade" ] || fail "nothing written"
  conn 'y\ny\n' gmail || { cat "$T/out"; fail "gmail"; }
  grep -q 'ANSWER=unset' "$CLAUDE_LOG" && ! grep -q 'ANSWER=[^u]' "$CLAUDE_LOG" || fail "no answer reaches a child"
  ! grep -rqs -e "Have you added" -e '"added"' "$HOME" "$P" || fail "the question and its answer are stored nowhere"
}

connect_record() {   # AC8
  fresh; connect_fixture; touch "$HOME/.gh-signed"
  local before; before="$(cd "$P" && find . -path ./.git -prune -o -print | LC_ALL=C sort)"
  conn 'y\n' jira || fail "jira"; conn 'y\n' github || fail "github"
  assert_eq "$(rec)" '{"format": 1, "connectors": ["github", "jira"]}' "the contract's shape: names only, sorted, unique"
  assert_eq "$(cd "$P" && find . -path ./.git -prune -o -print | LC_ALL=C sort | grep -vxF -e ./.ade -e ./.ade/connectors.json -e ./.ade/connections.json)" "$before" "nothing else in the folder"
  for f in connectors.json connections.json; do assert_not_contains "$P/.ade/$f" "$T" "no path of this machine in $f"; assert_not_contains "$P/.ade/$f" "someone" "no account in $f"; done
  local bad n=0 sum
  for bad in '{"format": 1, "connectors": ["jira"], "who": "me"}' '{"format": 2, "connectors": []}' '{"format": "1", "connectors": []}' \
    '{"format": true, "connectors": []}' '{"format": 1, "connectors": ["jira", "github"]}' '{"format": 1, "connectors": ["jira", "jira"]}' \
    '{"format": 1, "connectors": ["Jira"]}' '{"format": 1, "connectors": "jira"}' '{"format": 1}' '{"format": 1, "format": 1, "connectors": []}' \
    '[1]' 'not json' "{\"format\": 1, \"connectors\": [$(seq 1 65 | sed 's/^/"a/; s/$/"/' | paste -sd, -)]}" \
    "{\"format\": 1, \"connectors\": [], \"x\": \"$(head -c 70000 /dev/zero | tr '\0' a)\"}" '{"format": 1, "connectors": ["a\u001b[2Jb"]}'; do
    n=$((n + 1)); printf '%s\n' "$bad" > "$P/.ade/connectors.json"; sum="$(cksum < "$P/.ade/connectors.json")"; : > "$CLAUDE_LOG"
    bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "record $n: list refuses"; assert_contains "$T/out" "is not a valid connectors record" "record $n: why"
    bash "$ADE" connect status > "$T/out" 2>&1; assert_eq "$?" 2 "record $n: status refuses"
    conn 'y\n' gmail; assert_eq "$?" 2 "record $n: connect refuses"; assert_eq "$(installs)" 0 "record $n: nothing installed"
    assert_eq "$(cksum < "$P/.ade/connectors.json")" "$sum" "record $n: left as it is"
    LC_ALL=C grep -q "$(printf '\033')" "$T/out" && fail "record $n: a control character printed"
  done
  rm "$P/.ade/connectors.json"; ln -s "$T/elsewhere.json" "$P/.ade/connectors.json"; echo '{"format": 1, "connectors": []}' > "$T/elsewhere.json"
  conn 'y\n' jira; assert_eq "$?" 2 "a link is refused"; assert_eq "$(cat "$T/elsewhere.json")" '{"format": 1, "connectors": []}' "and not written through"
}

connect_status_disconnect() {   # AC9
  fresh; connect_fixture; touch "$HOME/.gh-signed"
  bash "$ADE" connect status < /dev/null > "$T/out" 2>&1 || fail "no record: exit 0"; assert_contains "$T/out" "no connectors recorded" "says so"
  conn 'y\n' jira && conn 'y\n' github && conn 'y\ny\n' gmail || { cat "$T/out"; fail "connect three"; }
  bash "$ADE" connect status < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "status, no gap: exit 0"; }
  assert_contains "$T/out" "connector github: ready" "gh signed in"
  assert_contains "$T/out" "connector jira: unknown (ade cannot see this sign-in; /mcp in Claude Code shows it)" "a plugin server's sign-in"
  assert_contains "$T/out" "connector gmail: unknown (the sign-in is in your Claude account; ade cannot see it)" "a claude.ai connector"
  assert_eq "$(wc -l < "$T/out" | tr -d ' ')" 3 "one line per recorded connector"; assert_not_contains "$T/out" "gho_" "no token"
  rm "$HOME/.gh-signed"; bash "$ADE" connect status > "$T/out" 2>&1; assert_eq "$?" 1 "a gap exits 1"
  assert_contains "$T/out" "connector github: missing (gh is not signed in: gh auth login)" "missing"
  bash "$ADE" connect status jira > "$T/out" 2>&1 || fail "one service"; assert_eq "$(cat "$T/out")" "connector jira: unknown (ade cannot see this sign-in; /mcp in Claude Code shows it)" "only it"
  bash "$ADE" connect status slack > "$T/out" 2>&1; assert_eq "$?" 1 "not recorded"
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["plugins"].pop("guard@ade-skills"); json.dump(d, open(p, "w"))' "$HOME/.claude/plugins/installed_plugins.json"
  bash "$ADE" connect status jira > "$T/out" 2>&1; assert_eq "$?" 1 "guard gone"; assert_contains "$T/out" "connector jira: missing (plugin guard is not installed here)" "why"
  echo '{"format": 1, "connectors": ["github", "gmail", "jira", "linear"]}' > "$P/.ade/connectors.json"
  bash "$ADE" connect status linear > "$T/out" 2>&1; assert_eq "$?" 1 "no recipe"; assert_contains "$T/out" "connector linear: missing (no verified recipe" "why"
  local sum; sum="$(cksum < "$P/.ade/connectors.json")"; : > "$CLAUDE_LOG"; : > "$GH_LOG"
  conn 'y\n' disconnect jira || { cat "$T/out"; fail "disconnect jira"; }
  assert_contains "$CLAUDE_LOG" "mcp logout plugin:jira:jira" "signs out where ade can"; assert_contains "$T/out" "https://id.atlassian.com/manage-profile/apps" "the revoke page"
  conn '' disconnect github || fail "disconnect github"; assert_contains "$T/out" "gh auth logout" "how to sign out at the source"
  assert_eq "$(wc -c < "$GH_LOG" | tr -d ' ')" 0 "gh is not touched"
  conn '' disconnect gmail || fail "disconnect gmail"; assert_contains "$T/out" "connector settings of your Claude account" "where"
  FAKE_LOGOUT_RC=1 pty_run 'y\n' bash "$ADE" connect disconnect jira > "$T/out" 2>&1; assert_eq "$?" 1 "a failed sign-out exits 1"
  assert_eq "$(cksum < "$P/.ade/connectors.json")" "$sum" "the record is left alone"
}

connect_hostile() {   # AC10
  fresh; connect_fixture; local x esc; esc="$(printf '\033')"
  for x in "-rf" "a/b" "a b" "$(printf 'a\nb')" "$(printf 'a\033[31mb')" "../x" "Jira" "" "--help" "$(printf 'a\tb')"; do
    for c in "" status disconnect; do
      pty_run 'y\n' bash "$ADE" connect $c "$x" > "$T/out" 2>&1; assert_eq "$?" 2 "[$c $x] refused"
      LC_ALL=C grep -q "$esc" "$T/out" && fail "[$c $x] printed an escape"
    done
  done
  assert_eq "$(wc -c < "$CLAUDE_LOG" | tr -d ' ')" 0 "nothing ran"
  recipe jira "$(printf '%s' "$JIRA" | sed 's/"title": "Jira"/"title": "Ji\\u001b]0;pwned\\u0007ra"/')"
  recipe gmail "$(printf '%s' "$GMAIL" | sed 's/mail of the/mail \\u001b[2J of the/')"
  recipe github "$(printf '%s' "$GITHUB" | sed 's/"title": "GitHub"/"title": "Git\\u202eHub"/')"; recipe x '{}' "$(printf 'x\033[2J.json')"; release hostile
  bash "$ADE" connect > "$T/out" 2>&1; assert_eq "$?" 2 "hostile recipes refused"
  for x in jira gmail github; do assert_contains "$T/out" "the recipe of $x is refused" "$x refused"; done
  assert_contains "$T/out" "x??2J.json is refused: its file name" "a hostile file name, printed safely"
  LC_ALL=C grep -q "$esc" "$T/out" && fail "an escape reached the terminal"
  LC_ALL=C grep -q "$(printf '\007')" "$T/out" && fail "a bell reached the terminal"
  grep -Eq '^slack +chat' "$T/out" || fail "the others are listed"
}

ALL="connect_lists connect_pins_and_refuses connect_plugin connect_cli connect_claude_ai connect_held connect_terminal_only connect_record connect_status_disconnect connect_hostile"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
