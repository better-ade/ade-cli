#!/bin/bash
# story A4: `ade claude`. A fake claude prints where it ran, its arguments and a few environment values.
. "$(dirname "$0")/helpers.sh"

claude_hub() {   # a hub named acme with an orchestrator model, and a fake claude on PATH
  make_hub "$T/hub" hub; printf 'HUB_NAME=acme\nHUB_ROOT_MODEL=opus\n' > "$T/hub/hub.conf"
  mkdir -p "$T/hub/.claude" "$T/fakebin"
  printf '#!/bin/bash\necho "pwd:$PWD"\necho "HUB:$HUB"\nfor a in "$@"; do echo "arg:$a"; done\n' > "$T/fakebin/claude"
  chmod +x "$T/fakebin/claude"; export PATH="$T/fakebin:$PATH" ADE_HUB="$T/hub"
}
settings() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$T/hub/.claude/settings.json" "$1"; }

runs_claude_at_root() {   # AC1
  fresh; claude_hub; mkdir -p "$T/elsewhere"
  out=$(cd "$T/elsewhere" && bash "$ADE" claude) || fail "exit"
  assert_eq "$out" "pwd:$T/hub
HUB:$T/hub
arg:--model
arg:opus
arg:--remote-control
arg:acme" "claude at the hub root with the orchestrator model and Remote Control"
  sed 's/^HUB_ROOT_MODEL=.*//' "$T/hub/hub.conf" > "$T/c" && mv "$T/c" "$T/hub/hub.conf"
  out=$(bash "$ADE" claude | grep -c 'arg:--model'); assert_eq "$out" 0 "no model set: no --model"
}

enables_ade_plugin() {   # AC2
  fresh; claude_hub; echo '{"model": "opus", "enabledPlugins": {"git@ade-skills": true}}' > "$T/hub/.claude/settings.json"
  bash "$ADE" claude > /dev/null || fail "exit"; bash "$ADE" claude > /dev/null || fail "second exit"
  assert_eq "$(settings 'd["extraKnownMarketplaces"]["ade-skills"]["source"]')" "{'source': 'github', 'repo': 'better-ade/ade-skills'}" "marketplace listed"
  assert_eq "$(settings 'd["enabledPlugins"]')" "{'git@ade-skills': True, 'ade@ade-skills': True}" "ade enabled, others kept, once"
  assert_eq "$(settings 'd["model"]')" "opus" "other keys kept"
  rm "$T/hub/.claude/settings.json"; bash "$ADE" claude > /dev/null || fail "no settings exit"
  assert_eq "$(settings 'd["enabledPlugins"]["ade@ade-skills"]')" "True" "created when missing"
  echo '{bad' > "$T/hub/.claude/settings.json"; bash "$ADE" claude > "$T/out" 2>&1; assert_eq "$?" 1 "bad JSON refused"
  assert_eq "$(cat "$T/hub/.claude/settings.json")" "{bad" "bad JSON left as it was"
  assert_not_contains "$T/out" "pwd:" "claude not started"
}

folder_is_work() {   # AC3
  fresh; claude_hub
  out=$(bash "$ADE" claude projects/x); assert_eq "$out" "hub work
arg:projects/x" "runs bin/work projects/x"
}

passthrough_and_refusal() {   # AC4
  fresh; claude_hub
  out=$(bash "$ADE" claude -- --resume | tail -1); assert_eq "$out" "arg:--resume" "--resume passed through"
  for args in "-- --dangerously-skip-permissions" "projects/x --dangerously-skip-permissions" "-- --resume --dangerously-skip-permissions" \
    "-- --allow-dangerously-skip-permissions" "-- --permission-mode bypassPermissions" "-- --permission-mode=bypassPermissions" \
    "projects/x --mode bypasspermissions" "-- --DANGEROUSLY-SKIP-PERMISSIONS"; do
    bash "$ADE" claude $args > "$T/out" 2>&1; assert_eq "$?" 2 "refused: $args"; assert_not_contains "$T/out" "pwd:" "nothing started"
  done
}

no_hub() {   # AC5
  fresh; mkdir -p "$T/nowhere"; (cd "$T/nowhere" && bash "$ADE" claude) > "$T/out" 2>&1; assert_eq "$?" 2 "exit"
  assert_contains "$T/out" "no hub found" "says no hub"; assert_contains "$T/out" "ade hub new <name>" "hint"
}

hub_claude_settings() {   # review: HUB_CLAUDE, HUB_CLAUDE_CONFIG_DIR, opus[1m] never globbed; no claude: settings untouched
  fresh; claude_hub; printf '#!/bin/bash\necho "alt CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"\nfor a in "$@"; do echo "arg:$a"; done\n' > "$T/fakebin/claude-alt"
  chmod +x "$T/fakebin/claude-alt"
  printf 'HUB_NAME=acme\nHUB_ROOT_MODEL="opus[1m]"\nHUB_CLAUDE=claude-alt\nHUB_CLAUDE_CONFIG_DIR=%s/cfg\n' "$T" > "$T/hub/hub.conf"; : > "$T/hub/opus1"
  out=$(bash "$ADE" claude); echo "$out" > "$T/out"
  assert_contains "$T/out" "alt CLAUDE_CONFIG_DIR=$T/cfg" "HUB_CLAUDE runs, with the config dir exported"
  assert_contains "$T/out" "arg:opus[1m]" "opus[1m] passed as is (a file opus1 in the hub never matches)"
  rm -f "$T/hub/.claude/settings.json"; printf 'HUB_NAME=acme\nHUB_CLAUDE=no-such-claude\n' > "$T/hub/hub.conf"
  bash "$ADE" claude > "$T/out" 2>&1; assert_eq "$?" 2 "missing claude exits 2"
  [ ! -e "$T/hub/.claude/settings.json" ] || fail "settings untouched when claude is missing"
}

ALL="hub_claude_settings runs_claude_at_root enables_ade_plugin folder_is_work passthrough_and_refusal no_hub"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
