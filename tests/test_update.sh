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

# --- story A11: ade update without stopping anything. A fake release folder, fake claude/tmux, a fixture hub ---
self_fixture() {   # ade installed at $T/prefix as 0.1.0; the release folder names 0.9.0 (good unless $1 = broken)
  export ADE_NO_CLAUDE_UPDATE=1 ADE_TEST_ALLOW_FILE_URLS=1 ADE_CLI_BASE="file://$T/rel" FAKE_LOG="$T/fake.log"; : > "$FAKE_LOG"
  mkdir -p "$T/src" "$T/rel/main" "$T/rel/v0.9.0"; cp "$REPO/ade" "$T/src/ade"; echo 0.1.0 > "$T/src/VERSION"
  bash "$T/src/install.sh" "$T/prefix" > /dev/null 2>&1 || { cp "$REPO/install.sh" "$T/src/"; bash "$T/src/install.sh" "$T/prefix" > /dev/null; }
  echo 0.9.0 > "$T/rel/main/VERSION"
  if [ "${1:-}" = broken ]; then printf '#!/bin/bash\nexit 3\n' > "$T/rel/v0.9.0/ade"; else cp "$REPO/ade" "$T/rel/v0.9.0/ade"; fi
  A="$T/prefix/bin/ade"
}
hub_fixture() {   # a hub that is a clone of $T/origin.git, with fakes for bin/method, bin/notify, bin/sessions, bin/chat
  H="$T/hub"; make_hub "$H" hub; echo "HUB_NAME=acme" > "$H/hub.conf"
  for s in method notify chat journal; do printf '#!/bin/bash\necho "%s $*" >> "$FAKE_LOG"\n' "$s" > "$H/bin/$s"; done
  printf '#!/bin/bash\necho "NAME STATUS"\necho "main ${MAIN_STATE:-busy}"\n' > "$H/bin/sessions"
  printf '#!/bin/bash\necho "chat $*" >> "$FAKE_LOG"\n[ "$1" = status ] && echo "running since x"\nexit 0\n' > "$H/bin/chat"
  chmod +x "$H/bin/"*; git init -q "$H"; commit_tag "$H" hub
  git init -q --bare "$T/origin.git"; git -C "$H" remote add origin "$T/origin.git"; git -C "$H" push -q -u origin HEAD 2> /dev/null
  git clone -q "$T/origin.git" "$T/other" 2> /dev/null; export ADE_HUB="$H"
}
upstream_commit() {   # <file> <text>: a new commit on the hub's origin (from another clone)
  echo "$2" > "$T/other/$1"; git -C "$T/other" add -A; git -C "$T/other" commit -qm "$1"; git -C "$T/other" push -q origin HEAD 2> /dev/null
}
fake_tools() {   # claude (update, plugin update) and tmux log; signals sent to the fake session are logged
  mkdir -p "$T/fakebin" "$HOME/.claude/plugins"
  printf '#!/bin/bash\necho "claude $*" >> "$FAKE_LOG"\n' > "$T/fakebin/claude"
  printf '#!/bin/bash\n[ "$1" = -L ] && shift 2\necho "tmux $*" >> "$FAKE_LOG"\n[ "$1" = has-session ] && exit "${TMUX_LIVE:-1}"\nexit 0\n' > "$T/fakebin/tmux"
  chmod +x "$T/fakebin/"*; export PATH="$T/fakebin:$PATH"
  echo '{"version": 2, "plugins": {"git@ade-skills": [{}], "other@elsewhere": [{}]}}' > "$HOME/.claude/plugins/installed_plugins.json"
}
live_session() {   # a long-running fake agent that logs any signal it gets
  ( trap 'echo "signal TERM" >> "$FAKE_LOG"; exit' TERM; trap 'echo "signal INT" >> "$FAKE_LOG"; exit' INT
    trap 'echo "signal HUP" >> "$FAKE_LOG"' HUP; while :; do sleep 1; done ) > /dev/null 2>&1 & SESSION=$!
}
inode() { ls -i "$1" | awk '{ print $1 }'; }

self_replaced_by_rename() {   # AC1 + AC8: a running ade dash keeps running; the file is renamed over, never written in place
  fresh; self_fixture; fake_tools; H="$T/hub"; make_hub "$H" hub; export ADE_HUB="$H"
  "$A" dash > "$T/dash.out" 2>&1 & D=$!; sleep 3
  before="$(inode "$A")"; "$A" update > "$T/out" 2>&1 || { cat "$T/out"; kill "$D"; fail "update exit"; }
  [ "$(inode "$A")" != "$before" ] || { kill "$D"; fail "replaced by rename (the inode changes)"; }
  assert_eq "$("$A" version)" "ade 0.9.0" "the new version"; assert_contains "$T/out" "ade 0.1.0 -> 0.9.0" "says so"
  ls "$T/prefix/bin" | grep -q '^\.ade-update' && { kill "$D"; fail "no temp file left"; }
  n="$(wc -c < "$T/dash.out")"; sleep 4
  kill -0 "$D" 2> /dev/null || fail "the running dash still runs"
  [ "$(wc -c < "$T/dash.out")" -gt "$n" ] || { kill "$D"; fail "and keeps drawing"; }
  grep -q "ade 0.9.0 is installed; restarting" "$T/dash.out" || { kill "$D"; fail "dash re-execs on the new version"; }
  kill "$D" 2> /dev/null; wait "$D" 2> /dev/null; return 0
}

broken_release_kept_out() {   # AC2
  fresh; self_fixture broken; fake_tools; H="$T/hub"; make_hub "$H" hub; export ADE_HUB="$H"
  before="$(inode "$A")"; "$A" update > "$T/out" 2>&1; assert_eq "$?" 1 "a failed check is an error"
  assert_eq "$(inode "$A")" "$before" "the old file stays"; assert_eq "$("$A" version)" "ade 0.1.0" "old version"
  assert_contains "$T/out" "failed its check" "says why"; ls -a "$T/prefix/bin" | grep -q '^\.ade-update' && fail "temp removed"
  return 0
}

hub_ff_only() {   # AC3
  fresh; self_fixture; fake_tools; hub_fixture; upstream_commit notes.md one
  bash "$ADE" update > "$T/out" 2>&1 || { cat "$T/out"; fail "update exit"; }
  [ -f "$H/notes.md" ] || fail "fast-forwarded"; assert_contains "$FAKE_LOG" "method sync" "then bin/method sync"
  assert_contains "$T/out" "a checkout" "a checkout of ade is not replaced"
  upstream_commit notes.md two; echo local > "$H/scratch"
  head="$(git -C "$H" rev-parse HEAD)"; bash "$ADE" update > "$T/out" 2>&1; assert_eq "$?" 1 "local changes refuse"
  assert_contains "$T/out" "local changes" "the reason"; assert_eq "$(git -C "$H" rev-parse HEAD)" "$head" "unchanged"
  rm "$H/scratch"; echo diverge > "$H/mine"; commit_tag "$H" mine
  head="$(git -C "$H" rev-parse HEAD)"; bash "$ADE" update > "$T/out" 2>&1; assert_eq "$?" 1 "a merge refuses"
  assert_contains "$T/out" "not a fast-forward" "the reason"; assert_eq "$(git -C "$H" rev-parse HEAD)" "$head" "unchanged"
}

nothing_killed_and_notified() {   # AC4 + AC6 + plugins and Claude Code
  fresh; self_fixture; fake_tools; hub_fixture; upstream_commit bin/chat.py '# new chat code'; live_session
  bash "$ADE" update > "$T/out" 2>&1 || { cat "$T/out"; kill "$SESSION"; fail "update exit"; }
  sleep 1; kill -0 "$SESSION" 2> /dev/null || fail "the session still runs"
  grep -q "^signal" "$FAKE_LOG" && { kill "$SESSION"; fail "no signal reached the session"; }
  kill "$SESSION"; wait "$SESSION" 2> /dev/null
  assert_not_contains "$FAKE_LOG" "chat stop" "a busy orchestrator is not stopped"
  assert_contains "$FAKE_LOG" "claude plugin update git@ade-skills" "ade-skills plugins updated"
  assert_not_contains "$FAKE_LOG" "plugin update other@elsewhere" "only ade-skills"; assert_contains "$FAKE_LOG" "claude update" "Claude Code"
  assert_eq "$(grep -c '^notify all' "$FAKE_LOG")" 1 "one notify line"
  grep '^notify all' "$FAKE_LOG" | grep -q "hub" && grep '^notify all' "$FAKE_LOG" | grep -q "/reload-plugins" && grep '^notify all' "$FAKE_LOG" | grep -q "next prompt" || fail "names what changed"
}

restart_when_idle() {   # AC5
  fresh; self_fixture; fake_tools; hub_fixture; upstream_commit bin/chat.py '# new chat code'
  MAIN_STATE=busy bash "$ADE" update > "$T/out" 2>&1 || { cat "$T/out"; fail "busy exit"; }
  assert_not_contains "$FAKE_LOG" "chat stop" "busy: never interrupted"; assert_contains "$T/out" "restarts when it is idle" "scheduled"
  [ -s "$HOME/.config/ade/restart-pending" ] || fail "the pending restart is kept"
  : > "$FAKE_LOG"; MAIN_STATE=idle bash "$ADE" update > "$T/out" 2>&1 || { cat "$T/out"; fail "idle exit"; }
  grep -n -e "chat stop" -e "chat start" "$FAKE_LOG" | tr '\n' ' ' | grep -q "chat stop.*chat start" || fail "graceful restart when idle"
  assert_contains "$FAKE_LOG" "journal ade ade update: restarted the orchestrator" "journaled"
  [ ! -s "$HOME/.config/ade/restart-pending" ] || fail "nothing pending after"
}

check_changes_nothing() {   # AC7 (first half; the daily policy comes with A12)
  fresh; self_fixture; fake_tools; hub_fixture; upstream_commit notes.md one
  before="$(inode "$A"); $(git -C "$H" rev-parse HEAD) $(git -C "$H" rev-parse origin/HEAD 2> /dev/null)"
  "$A" update --check > "$T/out" 2>&1 || { cat "$T/out"; fail "check exit"; }
  for l in "ade 0.1.0 -> 0.9.0" "hub: new commits" "plugin git@ade-skills" "Claude Code"; do assert_contains "$T/out" "$l" "check: $l"; done
  assert_eq "$(inode "$A"); $(git -C "$H" rev-parse HEAD) $(git -C "$H" rev-parse origin/HEAD 2> /dev/null)" "$before" "nothing changed"
  ! grep -Eq "method|notify|claude update|plugin update|source-file" "$FAKE_LOG" || fail "no update ran"
}

ui_reloads() {   # AC8: ade ui reloads its config in place
  fresh; self_fixture; fake_tools; hub_fixture; export TMUX_LIVE=0
  bash "$ADE" update > "$T/out" 2>&1 || { cat "$T/out"; fail "exit"; }
  assert_contains "$FAKE_LOG" "tmux source-file" "reloaded"; ! grep -Eq "tmux (kill-|detach)" "$FAKE_LOG" || fail "never detached or killed"
}

ALL="updates_before_launch once_per_day env_skips failure_never_blocks other_launchers ui_updates self_replaced_by_rename broken_release_kept_out hub_ff_only nothing_killed_and_notified restart_when_idle check_changes_nothing ui_reloads"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
