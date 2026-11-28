#!/bin/bash
# story F1: `ade work <folder>` checks the hub's Claude Code command (HUB_CLAUDE, else claude) before it starts
# anything. A minimal hub whose bin/work logs that it ran, and a fake tmux that logs every call.
. "$(dirname "$0")/helpers.sh"

work_fixture() {   # a hub at $T/hub, its bin/work logging to $T/work.ran; a fake tmux logging to $T/tmux.log
  make_hub "$T/hub" hub; mkdir -p "$T/hub/ops/monitoring" "$T/fakebin"; export ADE_HUB="$T/hub" TMUX_LOG="$T/tmux.log"
  printf '#!/bin/bash\necho "work $*" >> "%s/work.ran"; echo "hub work"\n' "$T" > "$T/hub/bin/work"; chmod +x "$T/hub/bin/work"
  printf '#!/bin/bash\necho "tmux $*" >> "$TMUX_LOG"\nexit 0\n' > "$T/fakebin/tmux"
  printf '#!/bin/bash\nexit 0\n' > "$T/fakebin/claude-alt"; chmod +x "$T/fakebin/tmux" "$T/fakebin/claude-alt"
  export PATH="$T/fakebin:$PATH"; : > "$TMUX_LOG"
}

work_needs_claude() {   # AC1: the hub's Claude Code command not found: exit non-zero, nothing started, one line
  fresh; work_fixture; printf 'HUB_NAME=acme\nHUB_CLAUDE=no-such-claude\n' > "$T/hub/hub.conf"
  local ui rc; for ui in off on; do
    ADE_UI="$ui" bash "$ADE" work ops/monitoring > "$T/out" 2>&1; rc=$?
    [ "$rc" != 0 ] || { cat "$T/out"; fail "[ADE_UI=$ui] exits non-zero"; }
    assert_eq "$(grep -c . "$T/out")" 1 "[ADE_UI=$ui] one line"
    assert_contains "$T/out" "no-such-claude" "[ADE_UI=$ui] names the missing command"
    assert_contains "$T/out" "ade setup" "[ADE_UI=$ui] and ade setup as the fix"
    [ ! -e "$T/work.ran" ] || fail "[ADE_UI=$ui] the hub's bin/work never ran (no agent row)"
    assert_eq "$(cat "$TMUX_LOG")" "" "[ADE_UI=$ui] no tmux window"
  done
  printf 'HUB_NAME=acme\nHUB_CLAUDE=claude-alt\n' > "$T/hub/hub.conf"   # the command is there: work goes ahead
  bash "$ADE" work ops/monitoring > "$T/out" 2>&1 || { cat "$T/out"; fail "a hub whose command is found starts"; }
  assert_contains "$T/work.ran" "work ops/monitoring" "the hub's bin/work ran"
  # the command bin/work runs, as its lib.sh picks it: this machine's .local/hub.conf wins, AGENT_CLAUDE over both,
  # --claude over all; a Gemini session runs no Claude Code (bin/work checks the Gemini CLI itself)
  mkdir -p "$T/hub/.local"; echo "HUB_CLAUDE=no-such-local" > "$T/hub/.local/hub.conf"; rm -f "$T/work.ran"
  bash "$ADE" work ops/monitoring > "$T/out" 2>&1 && fail ".local/hub.conf: refused"; assert_contains "$T/out" "no-such-local" "the machine's value"
  AGENT_CLAUDE=claude-alt bash "$ADE" work ops/monitoring > "$T/out" 2>&1 || { cat "$T/out"; fail "AGENT_CLAUDE wins"; }
  bash "$ADE" work ops/monitoring --claude claude-alt > "$T/out" 2>&1 || { cat "$T/out"; fail "--claude wins"; }
  AGENT_CLAUDE=claude-alt bash "$ADE" work ops/monitoring --claude no-such-flag > "$T/out" 2>&1 && fail "--claude: refused when missing"
  assert_contains "$T/out" "no-such-flag" "names it"
  bash "$ADE" work ops/monitoring --provider gemini --model gemini-x > "$T/out" 2>&1 || { cat "$T/out"; fail "gemini: no Claude Code needed"; }
  echo "HUB_PROVIDER=gemini" >> "$T/hub/hub.conf"; bash "$ADE" work ops/monitoring > "$T/out" 2>&1 || { cat "$T/out"; fail "a gemini hub"; }
  bash "$ADE" work ops/monitoring --provider anthropic > "$T/out" 2>&1 && fail "--provider anthropic on a gemini hub: checked"
  rm -f "$T/work.ran"; bash "$ADE" work > "$T/out" 2>&1; assert_contains "$T/work.ran" "work" "no folder: bin/work answers (its usage)"
}

ALL="work_needs_claude"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
