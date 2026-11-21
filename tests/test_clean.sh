#!/bin/bash
# story A9: ade clean, ade reset, ade uninstall. Fixture hubs and projects; fakes for tmux, launchctl, systemctl and
# the hub's bin/chat, bin/keys and bin/journal; nothing outside the test folder is touched.
. "$(dirname "$0")/helpers.sh"

dead_pid() { sleep 0 & local p=$!; wait "$p"; echo "$p"; }
clean_fixture() {
  H="$T/hub"; make_hub "$H" hub; echo "HUB_NAME=acme" > "$H/hub.conf"; git init -q "$H"; commit_tag "$H" hub
  export AGENT_STATE="$T/state" TMPDIR="$T/tmp" FAKE_LOG="$T/fake.log"; mkdir -p "$TMPDIR"; : > "$FAKE_LOG"
  S="$AGENT_STATE"; mkdir -p "$S/dispatch" "$S/cursors"
  mkdir -p "$S/sync.lock" "$S/dispatch.lock" "$S/chat.lock"; dead_pid > "$S/sync.lock/pid"
  sleep 300 & LIVE=$!; echo "$LIVE" > "$S/dispatch.lock/pid"; dead_pid > "$S/chat.lock/pid"
  : > "$S/dispatch/old-ticket"; touch -t 202001010000 "$S/dispatch/old-ticket"; : > "$S/dispatch/new-ticket"
  : > "$S/cursors/gone"; touch -t 202001010000 "$S/cursors/gone"; : > "$S/cursors/fresh"
  mkdir -p "$TMPDIR/ade.old1" "$TMPDIR/ade.new1" "$TMPDIR/other.old"; touch -t 202001010000 "$TMPDIR/ade.old1" "$TMPDIR/other.old"
  P="$T/proj"; mkdir -p "$P"; git init -q -b main "$P" 2>/dev/null || git init -q "$P"; git -C "$P" checkout -q -b main 2>/dev/null
  echo a > "$P/a"; commit_tag "$P" base
  for b in done wip feature; do git -C "$P" worktree add -q -b "$b" "$T/wt-$b" main; done
  echo f > "$T/wt-feature/f"; git -C "$T/wt-feature" add f; git -C "$T/wt-feature" commit -qm feature
  echo dirty > "$T/wt-wip/dirty"
  mkdir -p "$H/projects/api"; printf '| Repo | Checkout | Branch |\n|---|---|---|\n| o/api | %s | main |\n' "$P" > "$H/projects/api/ACCESS.md"
  mkdir -p "$T/fakebin"; cat > "$T/fakebin/tmux" <<'F'
#!/bin/bash
[ "$1" = -L ] && shift 2
echo "tmux $*" >> "$FAKE_LOG"
case "$1" in
  list-sessions) [ -f "$FAKE_LOG.gone" ] || echo ade-dead; echo ade-live; echo work ;;
  list-panes) case "$*" in *ade-dead*) echo 1; echo 1 ;; *) echo 0 ;; esac ;;
  kill-session) touch "$FAKE_LOG.gone" ;;
esac
exit 0
F
  for c in launchctl systemctl; do printf '#!/bin/bash\necho "%s $*" >> "$FAKE_LOG"\n' "$c" > "$T/fakebin/$c"; done
  cat > "$H/bin/chat" <<'C'
#!/bin/bash
echo "chat $*" >> "$FAKE_LOG"
case "$1" in status) [ -f "$HUB/.running" ] && echo "running since x" || echo stopped ;; stop) rm -f "$HUB/.running" ;; esac
C
  cat > "$H/bin/keys" <<'K'
#!/bin/bash
echo "keys $*" >> "$FAKE_LOG"
K
  printf '#!/bin/bash\necho "$*" >> "$HUB/journal.log"\n' > "$H/bin/journal"
  chmod +x "$T/fakebin/"* "$H/bin/"*; export PATH="$T/fakebin:$PATH" ADE_HUB="$H"
  mkdir -p "$HOME/.config/ade"; echo "$H" > "$HOME/.config/ade/hub"; echo "$H" > "$HOME/.config/ade/hubs"
}
stop_live() { kill "$LIVE" 2>/dev/null; }
listing() { (cd "$T" && find . -path ./tmp -prune -o -path ./state -prune -o -print | grep -v '/\.git/' | LC_ALL=C sort); }

clean_preview_then_yes() {   # AC1
  fresh; clean_fixture; before="$(listing; ls -R "$AGENT_STATE" "$TMPDIR")"
  bash "$ADE" clean < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; stop_live; fail "preview exit"; }
  assert_eq "$(listing; ls -R "$AGENT_STATE" "$TMPDIR")" "$before" "the preview changes nothing"
  for s in "sync.lock" "chat.lock" "dispatch/old-ticket" "cursors/gone" "ade.old1" "ade-dead" "wt-done"; do assert_contains "$T/out" "$s" "planned: $s"; done
  assert_not_contains "$FAKE_LOG" "kill-session" "no tmux change in the preview"
  bash "$ADE" clean --yes < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; stop_live; fail "--yes exit"; }
  [ ! -e "$AGENT_STATE/sync.lock" ] && [ ! -e "$AGENT_STATE/chat.lock" ] || fail "stale locks removed"
  [ ! -e "$AGENT_STATE/dispatch/old-ticket" ] && [ -e "$AGENT_STATE/dispatch/new-ticket" ] || fail "only old markers"
  [ ! -e "$AGENT_STATE/cursors/gone" ] && [ -e "$AGENT_STATE/cursors/fresh" ] || fail "only expired cursors"
  [ ! -e "$TMPDIR/ade.old1" ] && [ -e "$TMPDIR/ade.new1" ] && [ -e "$TMPDIR/other.old" ] || fail "only ade's old temp folders"
  grep -q "kill-session -t =ade-dead" "$FAKE_LOG" || fail "dead tmux session ended"
  [ ! -e "$T/wt-done" ] || fail "merged clean worktree removed"
  stop_live
}

never_removes_live() {   # AC2
  fresh; clean_fixture; bash "$ADE" clean --yes < /dev/null > "$T/out" 2>&1
  [ -f "$AGENT_STATE/dispatch.lock/pid" ] || fail "a live owner's lock is kept"
  [ -f "$T/wt-wip/dirty" ] || fail "a worktree with uncommitted changes is kept"
  [ -d "$T/wt-feature" ] || fail "an unmerged worktree is kept"
  ! grep -q "kill-session -t =ade-live" "$FAKE_LOG" || fail "a session with a live agent is kept"
  ! grep -q "kill-session -t =work" "$FAKE_LOG" || fail "only ade-* sessions"
  stop_live
}

reset_keeps_hubs() {   # AC3
  fresh; clean_fixture; stop_live; touch "$H/.running"; bash "$ADE" orchestrator new one --hub "$H" > /dev/null 2>&1 || fail "new"
  export AGENT_LAUNCHAGENTS="$T/LaunchAgents"; mkdir -p "$AGENT_LAUNCHAGENTS" "$HOME/.config/systemd/user" "$HOME/.claude"
  for j in chat monitor briefing; do : > "$AGENT_LAUNCHAGENTS/ai.agent-hub.acme.$j.plist"; : > "$HOME/.config/systemd/user/ai.agent-hub.acme.$j.service"; done
  mkdir -p "$H/.claude"; echo '{"model": "opus", "enabledPlugins": {"ade@ade-skills": true, "git@ade-skills": true}}' > "$H/.claude/settings.json"
  echo keep > "$HOME/.claude/settings.json"
  before="$(cd "$H" && find . -path ./.git -prune -o -type f -print | grep -v -e '^./.claude/settings.json$' -e '^./.running$' -e '^./journal.log$' | sort; cd "$P" && find . -type f | grep -v '/\.git/' | sort)"
  printf 'n\n' | bash "$ADE" reset > "$T/out" 2>&1; [ -d "$HOME/.config/ade" ] || fail "no means nothing"
  assert_not_contains "$FAKE_LOG" "chat stop" "nothing stopped without a yes"
  printf 'y\n' | bash "$ADE" reset > "$T/out" 2>&1 || { cat "$T/out"; fail "reset exit"; }
  assert_contains "$FAKE_LOG" "chat stop" "orchestrator stopped"
  [ ! -e "$HOME/.config/ade" ] || fail "~/.config/ade removed"
  [ ! -e "$AGENT_LAUNCHAGENTS/ai.agent-hub.acme.chat.plist" ] && [ ! -e "$AGENT_LAUNCHAGENTS/ai.agent-hub.acme.monitor.plist" ] || fail "launchd services removed"
  [ -e "$AGENT_LAUNCHAGENTS/ai.agent-hub.acme.briefing.plist" ] || fail "other jobs kept"
  if [ "$(uname)" = Darwin ]; then grep -q "launchctl bootout" "$FAKE_LOG" || fail "launchctl bootout"
  else grep -q "systemctl --user disable --now ai.agent-hub.acme.chat.service" "$FAKE_LOG" || fail "systemctl disable"; fi
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["enabledPlugins"]=={"git@ade-skills": True} and d["model"]=="opus"' "$H/.claude/settings.json" || fail "only the ade plugin entry removed"
  after="$(cd "$H" && find . -path ./.git -prune -o -type f -print | grep -v -e '^./.claude/settings.json$' -e '^./.running$' -e '^./journal.log$' | sort; cd "$P" && find . -type f | grep -v '/\.git/' | sort)"
  assert_eq "$after" "$before" "hub and project files untouched"
  assert_eq "$(cat "$HOME/.claude/settings.json")" keep "Claude Code untouched"; assert_not_contains "$FAKE_LOG" "keys forget" "keys kept"
}

reset_keys() {   # AC4
  fresh; clean_fixture; stop_live
  printf '%s\tdeepseek\n%s\ttelegram\n' "$H" "$H" > "$HOME/.config/ade/keys-set"
  printf 'y\ny\nn\n' | bash "$ADE" reset --keys > "$T/out" 2>&1 || { cat "$T/out"; fail "reset --keys exit"; }
  assert_contains "$FAKE_LOG" "keys forget deepseek" "the first key forgotten"
  assert_not_contains "$FAKE_LOG" "keys forget telegram" "a refused one is kept"
  assert_not_contains "$FAKE_LOG" "keys forget glm" "never one ade setup did not set"
  assert_eq "$(grep -c 'Forget the' "$T/out")" 2 "one confirmation per key"
}

reset_hub() {   # AC5
  fresh; clean_fixture; stop_live; cp -R "$H" "$T/hub2"
  printf 'y\nwrong\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; [ -d "$H" ] || fail "a wrong name keeps the hub"
  fresh; clean_fixture; stop_live; echo change >> "$H/hub.conf"
  printf 'y\nacme\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; assert_eq "$?" 2 "uncommitted work refused"; [ -d "$H" ] || fail "kept"
  git -C "$H" checkout -q hub.conf
  printf 'y\nacme\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; assert_eq "$?" 2 "unpushed work refused (no upstream)"
  assert_contains "$T/out" "not pushed" "says why"
  R="$T/remote.git"; git init -q --bare "$R"; git -C "$H" remote add origin "$R"; git -C "$H" push -q -u origin HEAD 2>/dev/null
  printf 'y\nacme\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1 || { cat "$T/out"; fail "pushed hub exit"; }
  [ ! -e "$H" ] || fail "the hub removed after typing its name"
  [ -d "$P" ] && [ -d "$R" ] && [ -d "$T/wt-feature" ] || fail "nothing else removed"
}

uninstall_last() {   # AC6
  fresh; clean_fixture; stop_live; bash "$REPO/install.sh" "$T/prefix" > /dev/null
  printf 'y\n' | "$T/prefix/bin/ade" uninstall > "$T/out" 2>&1 || { cat "$T/out"; fail "uninstall exit"; }
  [ ! -e "$T/prefix/bin/ade" ] || fail "binary removed"; [ ! -e "$HOME/.config/ade" ] || fail "reset first"
  assert_contains "$T/out" "install.sh | bash" "how to reinstall"
  [ "$(tail -1 "$T/out" | grep -c install.sh)" = 1 ] || fail "the binary goes last"
  printf 'y\n' | bash "$ADE" uninstall > "$T/out" 2>&1; assert_eq "$?" 2 "a checkout is never removed"; [ -f "$ADE" ] || fail "checkout kept"
}

journal_lines() {   # AC7
  fresh; clean_fixture; bash "$ADE" clean --yes < /dev/null > /dev/null 2>&1; stop_live
  assert_eq "$(grep -c 'ade clean' "$H/journal.log")" 1 "one clean line"
  printf 'y\n' | bash "$ADE" reset > /dev/null 2>&1; assert_eq "$(grep -c 'ade reset' "$H/journal.log")" 1 "one reset line"
}

twice_nothing() {   # AC8
  fresh; clean_fixture; bash "$ADE" clean --yes < /dev/null > /dev/null 2>&1; stop_live; rm -f "$AGENT_STATE/dispatch.lock/pid"; rmdir "$AGENT_STATE/dispatch.lock"
  bash "$ADE" clean --yes < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "nothing to clean" "clean twice"
  printf 'y\n' | bash "$ADE" reset > /dev/null 2>&1; bash "$ADE" reset < /dev/null > "$T/out" 2>&1 || fail "second reset exit"
  assert_contains "$T/out" "nothing to reset" "reset twice"
}

setup_records_keys() {   # the record --keys relies on: ade setup notes which keys it stored (names only)
  fresh; clean_fixture; stop_live; printf 'y\ntok-xyz\n' | bash "$ADE" setup --telegram > /dev/null 2>&1
  assert_eq "$(cat "$HOME/.config/ade/keys-set")" "$H	telegram" "recorded"; assert_not_contains "$HOME/.config/ade/keys-set" "tok-xyz" "never the value"
}

ALL="clean_preview_then_yes never_removes_live reset_keeps_hubs reset_keys reset_hub uninstall_last journal_lines twice_nothing setup_records_keys"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
