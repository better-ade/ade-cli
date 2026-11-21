#!/bin/bash
# owner requirement (with A4): before ade launches Claude Code it updates it, at most once per 24 h, never blocking.
. "$(dirname "$0")/helpers.sh"

update_fixture() {   # a hub and a fake claude that logs "update" and launches; $UPDATE_RC / $UPDATE_SLEEP shape the update
  unset ADE_NO_CLAUDE_UPDATE
  make_hub "$T/hub" hub; printf 'HUB_NAME=acme\n' > "$T/hub/hub.conf"; export ADE_HUB="$T/hub" LOG="$T/claude.log"; : > "$LOG"
  mkdir -p "$T/fakebin"; cat > "$T/fakebin/claude" <<'C'
#!/bin/bash
if [ "${1:-}" = update ]; then echo update >> "$LOG"; sleep "${UPDATE_SLEEP:-0}"; exit "${UPDATE_RC:-0}"; fi
echo "launch $*" >> "$LOG"
C
  chmod +x "$T/fakebin/claude"; export PATH="$T/fakebin:$PATH"
}

updates_before_launch() {
  fresh; update_fixture; bash "$ADE" claude > "$T/out" 2>&1 || { cat "$T/out"; fail "exit"; }
  assert_eq "$(head -1 "$LOG")" update "update first"; assert_eq "$(sed -n 2p "$LOG" | cut -d' ' -f1)" launch "then the launch"
  [ -f "$HOME/.config/ade/claude-updated" ] || fail "stamp written"
}

once_per_day() {
  fresh; update_fixture; bash "$ADE" claude > /dev/null 2>&1; bash "$ADE" claude > /dev/null 2>&1
  assert_eq "$(grep -c '^update' "$LOG")" 1 "once within 24 h"
  echo $(( $(date +%s) - 90000 )) > "$HOME/.config/ade/claude-updated"; bash "$ADE" claude > /dev/null 2>&1
  assert_eq "$(grep -c '^update' "$LOG")" 2 "again after 24 h"
}

env_skips() {
  fresh; update_fixture; ADE_NO_CLAUDE_UPDATE=1 bash "$ADE" claude > /dev/null 2>&1
  assert_not_contains "$LOG" update "skipped"; assert_contains "$LOG" launch "launched"
}

failure_never_blocks() {
  fresh; update_fixture; UPDATE_RC=1 bash "$ADE" claude > "$T/out" 2>&1 || fail "a failed update still launches"
  assert_contains "$LOG" launch "launched"; assert_eq "$(grep -c 'update' "$T/out")" 1 "one line about it"
  fresh; update_fixture; s=$(date +%s); UPDATE_SLEEP=30 ADE_CLAUDE_UPDATE_TIMEOUT=2 bash "$ADE" claude > /dev/null 2>&1
  [ $(( $(date +%s) - s )) -lt 15 ] || fail "a hanging update is cut off by the timeout"; assert_contains "$LOG" launch "launched after the timeout"
}

other_launchers() {   # ade work and ade orchestrator start update too
  fresh; update_fixture; bash "$ADE" work projects/x > /dev/null 2>&1; assert_eq "$(head -1 "$LOG")" update "ade work"
  fresh; update_fixture; printf '#!/bin/bash\nexit 0\n' > "$T/hub/bin/chat"; chmod +x "$T/hub/bin/chat"
  bash "$ADE" orchestrator new one --hub "$T/hub" > /dev/null 2>&1; bash "$ADE" orchestrator start one > /dev/null 2>&1
  assert_eq "$(head -1 "$LOG")" update "ade orchestrator start"
}

ui_updates() {   # ade ui updates before it opens the orchestrator tab
  fresh; update_fixture; printf '#!/bin/bash\n[ "$1" = -L ] && shift 2\necho "tmux $*" >> "$LOG"\n[ "$1" = has-session ] && exit 1\nexit 0\n' > "$T/fakebin/tmux"
  chmod +x "$T/fakebin/tmux"; bash "$ADE" ui --detach > /dev/null 2>&1
  grep -n -e '^update' -e 'new-session' "$LOG" | head -1 | grep -q ':update' || { cat "$LOG"; fail "update before the session starts"; }
}

ALL="updates_before_launch once_per_day env_skips failure_never_blocks other_launchers ui_updates"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
