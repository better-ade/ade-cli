#!/bin/bash
# story A7: skills on the fly. Fixture project settings, a local ade-method (never list) and ade-skills (marketplace),
# a fake claude, and a hub whose bin/notify logs; never the network.
. "$(dirname "$0")/helpers.sh"

skills_fixture() {
  P="$T/proj"; mkdir -p "$P/.claude"; git init -q "$P"
  for s in bmad-build bmad-prd bmad-ux bmad-party-mode bmod-method; do mkdir -p "$P/.claude/skills/$s"; echo "# $s" > "$P/.claude/skills/$s/SKILL.md"; done
  cat > "$P/.claude/settings.json" <<'J'
{ "model": "opus", "skillOverrides": { "bmad-prd": "name-only", "bmad-ux": "name-only", "bmad-party-mode": "off", "bmod-method": "off" },
  "enabledPlugins": { "git@ade-skills": true } }
J
  M="$T/method"; mkdir -p "$M"; git init -q "$M"
  echo '{"format": 2, "bmad": {"never": ["bmad-party-mode", "bmad-agent-pm"], "on_demand_skills": ["bmad-prd", "bmad-ux"]}}' > "$M/ade.json"
  commit_tag "$M" m v9.0.0; export ADE_METHOD_REPO="$M" ADE_METHOD_REF=v9.0.0
  make_skills_repo
  make_hub "$T/hub" hub; echo "HUB_NAME=acme" > "$T/hub/hub.conf"; mkdir -p "$T/hub/projects/api"
  printf '| Repo | Checkout | Branch |\n|---|---|---|\n| owner/api | %s | main |\n' "$P" > "$T/hub/projects/api/ACCESS.md"
  export NOTIFY_LOG="$T/notify.log"; : > "$NOTIFY_LOG"
  printf '#!/bin/bash\nfor a in "$@"; do printf "[%%s]" "$a"; done >> "$NOTIFY_LOG"; echo >> "$NOTIFY_LOG"\n' > "$T/hub/bin/notify"; chmod +x "$T/hub/bin/notify"
  export ADE_HUB="$T/hub"; stub_claude; cd "$P"
}
over() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("skillOverrides", {}).get(sys.argv[2], "(absent)"))' "$P/.claude/settings.json" "$1"; }

list_states() {   # AC1
  fresh; skills_fixture
  bash "$ADE" skills list > "$T/out" 2>&1 || { cat "$T/out"; fail "list exit"; }
  for l in "bmad-build +on" "bmad-prd +name-only" "bmad-party-mode +off" "git +installed" "browser +not installed" "notes +not installed"; do
    grep -Eq "^  $l" "$T/out" || { cat "$T/out"; fail "list: $l"; }; done
}

enable_disable() {   # AC2
  fresh; skills_fixture; before="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["skillOverrides"].pop("bmad-prd"); print(json.dumps(d, sort_keys=True))' "$P/.claude/settings.json")"
  bash "$ADE" skills enable bmad-prd > "$T/out" 2>&1 || { cat "$T/out"; fail "enable exit"; }
  assert_eq "$(over bmad-prd)" "(absent)" "on = no override"
  after="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$P/.claude/settings.json")"
  assert_eq "$after" "$before" "only that entry changed"
  bash "$ADE" skills enable bmad-prd > /dev/null 2>&1 || fail "enable again"; assert_eq "$(over bmad-prd)" "(absent)" "idempotent on"
  bash "$ADE" skills disable bmad-build > /dev/null 2>&1 || fail "disable exit"; assert_eq "$(over bmad-build)" "name-only" "disabled = name-only"
  bash "$ADE" skills disable bmad-build > /dev/null 2>&1 || fail "disable again"; assert_eq "$(over bmad-build)" "name-only" "idempotent off"
  [ -f "$P/.claude/skills/bmad-build/SKILL.md" ] || fail "never deletes the skill"
  assert_eq "$(over bmad-ux)" "name-only" "others kept"
}

never_list() {   # AC3
  fresh; skills_fixture
  bash "$ADE" skills enable bmad-party-mode > "$T/out" 2>&1; assert_eq "$?" 2 "exit 2"
  assert_contains "$T/out" "ade-method's never list" "names the reason"; assert_eq "$(over bmad-party-mode)" "off" "unchanged"
}

add_notifies() {   # AC4
  fresh; skills_fixture
  bash "$ADE" skills add notes > "$T/out" 2>&1 || { cat "$T/out"; fail "add exit"; }
  assert_contains "$CLAUDE_LOG" "plugin install notes@ade-skills --scope project" "installed"
  assert_contains "$NOTIFY_LOG" "[projects/api]" "notifies that folder's sessions"; assert_contains "$NOTIFY_LOG" "/reload-plugins" "with the reload hint"
  : > "$NOTIFY_LOG"; bash "$ADE" skills enable bmad-prd > /dev/null 2>&1
  assert_contains "$NOTIFY_LOG" "[projects/api]" "enable notifies too"; assert_contains "$NOTIFY_LOG" "next prompt" "settings hint"
  : > "$NOTIFY_LOG"; Q="$T/other"; mkdir -p "$Q"; git init -q "$Q"; cd "$Q"; bash "$ADE" skills add git > "$T/out" 2>&1 || fail "add elsewhere"
  [ ! -s "$NOTIFY_LOG" ] || fail "a project in no folder notifies nobody"; assert_contains "$T/out" "/reload-plugins" "prints the hint itself"
}

search() {   # AC5
  fresh; skills_fixture
  bash "$ADE" skills search BROWSER > "$T/out" 2>&1 || fail "search exit"; assert_contains "$T/out" "browser" "by name, any case"
  assert_not_contains "$T/out" "notes" "only matches"
  bash "$ADE" skills search knowledge > "$T/out" 2>&1; assert_contains "$T/out" "notes" "by description"
  bash "$ADE" skills search zzz > "$T/out" 2>&1; assert_eq "$?" 1 "no match exits 1"
}

unknown_names() {   # AC6
  fresh; skills_fixture
  bash "$ADE" skills enable bmad-pdr > "$T/out" 2>&1; assert_eq "$?" 2 "unknown skill"; assert_contains "$T/out" "bmad-prd" "closest skill"
  bash "$ADE" skills add brwoser > "$T/out" 2>&1; assert_eq "$?" 2 "unknown plugin"; assert_contains "$T/out" "browser" "closest plugin"
  assert_not_contains "$CLAUDE_LOG" "brwoser" "nothing installed"
}

disable_keeps_off() {   # review: disable never raises an off skill to name-only
  fresh; skills_fixture; bash "$ADE" skills disable bmod-method > "$T/out" 2>&1 || fail "exit"
  assert_eq "$(over bmod-method)" "off" "stays off"
}

pinned_and_offline() {   # review: ade-skills at a tag by default; offline, the marketplace Claude Code installed is used
  fresh; skills_fixture; unset ADE_SKILLS_REF; git -C "$K" tag -d v0.1.0 > /dev/null; git -C "$K" tag v0.1.0-not-default
  echo '{"plugins": [{"name": "later", "description": "only on main"}]}' > "$K/.claude-plugin/marketplace.json"; commit_tag "$K" main-only
  git -C "$K" tag "$(bash "$ADE" skills --pin)" HEAD~1
  bash "$ADE" skills search later > "$T/out" 2>&1; assert_eq "$?" 1 "the pinned tag, not the branch tip"
  export ADE_SKILLS_REPO="$T/no-such-repo"; M2="$HOME/.claude/plugins/marketplaces/ade-skills/.claude-plugin"; mkdir -p "$M2"
  echo '{"plugins": [{"name": "cached", "description": "from the installed marketplace"}]}' > "$M2/marketplace.json"
  bash "$ADE" skills search cached > "$T/out" 2>&1 || { cat "$T/out"; fail "offline falls back to the installed file"; }
  assert_contains "$T/out" "installed marketplace" "and says so"
}

add_uses_repo() {   # review: add registers the marketplace from $ADE_SKILLS_REPO
  fresh; skills_fixture; bash "$ADE" skills add notes > /dev/null 2>&1 || fail "exit"
  assert_contains "$CLAUDE_LOG" "plugin marketplace add $K" "the configured repo"
}

# the plugins each released ade-skills tag ships (the names in its .claude-plugin/marketplace.json, recorded by hand
# when ade-cli moves its pin): the README is checked against what a user really gets, without the network
released_plugins() {
  case "$1" in
    v0.1.0) echo "git browser" ;;
    v0.9.0) echo "git browser ade notes fde clickup jira linear orgo guard" ;;
    *) return 1 ;;
  esac
}

readme_quick_start() {   # every `ade skills add <name>` in the README's quick start exists at the default pin
  fresh; local pin names line name n=0
  pin="$(bash "$ADE" skills --pin)"
  names="$(released_plugins "$pin")" || fail "no recorded plugin list for the pinned ade-skills $pin (add it to released_plugins)"
  while IFS= read -r line; do
    name="$(printf '%s\n' "$line" | sed -n 's/.*ade skills add \([^ ]*\).*/\1/p')"; [ -n "$name" ] || continue; n=$((n + 1))
    case " $names " in *" $name "*) ;; *) fail "README quick start: ade skills add $name, but ade-skills $pin ships only: $names" ;; esac
  done <<EOF
$(awk '/^## Quick start/ { f = 1; next } /^## / { f = 0 } f' "$REPO/README.md")
EOF
  [ "$n" -gt 0 ] || fail "README quick start has no ade skills add line"
}

ALL="readme_quick_start disable_keeps_off pinned_and_offline add_uses_repo list_states enable_disable never_list add_notifies search unknown_names"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
