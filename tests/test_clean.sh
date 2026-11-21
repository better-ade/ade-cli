#!/bin/bash
# story A9: ade clean, ade reset, ade uninstall. Fixture hubs and projects; fakes for tmux, launchctl, systemctl and
# the hub's bin/chat, bin/keys and bin/journal; nothing outside the test folder is touched.
. "$(dirname "$0")/helpers.sh"

dead_pid() { sleep 0 & local p=$!; wait "$p"; echo "$p"; }
clean_fixture() {
  H="$T/hub"; make_hub "$H" hub; echo "HUB_NAME=acme" > "$H/hub.conf"; git init -q "$H"; commit_tag "$H" hub
  export AGENT_STATE="$T/state" TMPDIR="$T/tmp" FAKE_LOG="$T/fake.log"; mkdir -p "$TMPDIR"; : > "$FAKE_LOG"
  S="$AGENT_STATE"; mkdir -p "$S/dispatch" "$S/events-seen"
  mkdir -p "$S/sync.lock" "$S/dispatch.lock" "$S/chat.lock"; dead_pid > "$S/sync.lock/pid"
  sleep 300 > /dev/null 2>&1 & LIVE=$!; echo "$LIVE" > "$S/dispatch.lock/pid"; dead_pid > "$S/chat.lock/pid"
  : > "$S/dispatch/old-ticket"; touch -t 202001010000 "$S/dispatch/old-ticket"; : > "$S/dispatch/new-ticket"
  : > "$S/events-seen/gone"; touch -t 202001010000 "$S/events-seen/gone"; : > "$S/events-seen/fresh"
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
  fresh; clean_fixture; : > "$T/out"; before="$(listing; ls -R "$AGENT_STATE" "$TMPDIR")"
  bash "$ADE" clean < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; stop_live; fail "preview exit"; }
  assert_eq "$(listing; ls -R "$AGENT_STATE" "$TMPDIR")" "$before" "the preview changes nothing"
  for s in "sync.lock" "chat.lock" "dispatch/old-ticket" "events-seen/gone" "ade.old1" "ade-dead" "wt-done"; do assert_contains "$T/out" "$s" "planned: $s"; done
  assert_not_contains "$FAKE_LOG" "kill-session" "no tmux change in the preview"
  bash "$ADE" clean --yes < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; stop_live; fail "--yes exit"; }
  [ ! -e "$AGENT_STATE/sync.lock" ] && [ ! -e "$AGENT_STATE/chat.lock" ] || fail "stale locks removed"
  [ ! -e "$AGENT_STATE/dispatch/old-ticket" ] && [ -e "$AGENT_STATE/dispatch/new-ticket" ] || fail "only old markers"
  [ ! -e "$AGENT_STATE/events-seen/gone" ] && [ -e "$AGENT_STATE/events-seen/fresh" ] || fail "only expired cursors"
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

# --hub never deletes: fakes for uname ($FAKE_UNAME), the trash CLI and osascript; the two trash fakes log their call
# and move the folder into $HOME/.Trash (FAKE_TRASH_FAIL=1: they move nothing). No real Trash is ever reached.
trash_fakes() {
  local d="$T/osbin"; mkdir -p "$d"; export ADE_TRASH_CLI="$d/trash"
  printf '#!/bin/bash\necho "${FAKE_UNAME:-Linux}"\n' > "$d/uname"
  cat > "$d/trash" <<'F'
#!/bin/bash
echo "trash $*" >> "$FAKE_LOG"; [ -n "${FAKE_TRASH_FAIL:-}" ] && exit 1; mkdir -p "$HOME/.Trash"; mv "$1" "$HOME/.Trash/"
F
  cat > "$d/osascript" <<'F'
#!/bin/bash
printf 'osascript' >> "$FAKE_LOG"; printf ' [%s]' "$@" >> "$FAKE_LOG"; echo >> "$FAKE_LOG"
[ -n "${FAKE_TRASH_FAIL:-}" ] && exit 1; mkdir -p "$HOME/.Trash"; mv "${@: -1}" "$HOME/.Trash/"; echo "folder hub of item .Trash"
F
  chmod +x "$d/"*; export PATH="$d:$PATH"
}
push_hub() { R="$T/remote.git"; git init -q --bare "$R"; git -C "$H" remote add origin "$R"; git -C "$H" push -q -u origin HEAD 2> /dev/null; }
hub_fixture() { fresh; clean_fixture; stop_live; trash_fakes; commit_tag "$H" fixture; }   # a clean, committed hub
matches() { [[ $1 =~ $2 ]]; }

reset_hub_refusals() {   # AC5: uncommitted, stashed or unpushed work is refused before anything changes
  hub_fixture; echo change >> "$H/hub.conf"
  printf 'y\nacme\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; assert_eq "$?" 2 "uncommitted work refused"
  assert_contains "$T/out" "uncommitted" "says why"; [ -f "$H/hub.conf" ] && [ -d "$HOME/.config/ade" ] || fail "nothing changed"
  git -C "$H" stash -q; printf 'y\nacme\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; assert_eq "$?" 2 "stashed work refused"
  git -C "$H" stash drop -q
  printf 'y\nacme\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; assert_eq "$?" 2 "unpushed work refused (no remote)"
  assert_contains "$T/out" "not pushed" "says why"
  push_hub; echo more >> "$H/hub.conf"; commit_tag "$H" local-only
  printf 'y\nacme\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; assert_eq "$?" 2 "a commit not pushed is refused"
  [ -d "$H" ] && [ -d "$HOME/.config/ade" ] || fail "kept"; assert_not_contains "$FAKE_LOG" "trash" "no trash call"
  mkdir -p "$T/plain"; make_hub "$T/plain" plain
  printf 'y\nplain\n' | bash "$ADE" reset --hub "$T/plain" > "$T/out" 2>&1; assert_eq "$?" 2 "a hub outside git cannot be checked"
  bash "$ADE" reset --hub "$T/proj" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "not a hub"
}

reset_hub_wrong_name() {   # AC5: the hub's name must be typed; a wrong one changes nothing at all
  hub_fixture; push_hub
  printf 'y\nwrong\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; assert_eq "$?" 1 "a wrong name stops"
  [ -d "$H" ] && [ -d "$HOME/.config/ade" ] || fail "a wrong name keeps the hub and the setup"
  printf 'y\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; [ -d "$H" ] || fail "no name keeps the hub"
}

reset_hub_trash_linux() {   # AC5 on Linux: moved to ~/.local/share/ade/trash/<hub>-<UTC time>/, never deleted
  hub_fixture; push_hub; cp -R "$H" "$T/hub2"; export FAKE_UNAME=Linux
  printf 'y\nacme\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1 || { cat "$T/out"; fail "pushed hub exit"; }
  [ ! -e "$H" ] || fail "the hub moved away after typing its name"
  dest="$(ls -d "$HOME/.local/share/ade/trash/"* 2> /dev/null)"; [ "$(printf '%s\n' "$dest" | grep -c .)" = 1 ] || fail "one trash folder"
  matches "$(basename "$dest")" '^hub-[0-9]{8}T[0-9]{6}Z$' || fail "named <hub>-<UTC time>: $dest"
  [ -f "$dest/hub.conf" ] && [ -d "$dest/.git" ] && [ -d "$dest/projects/api" ] || fail "the whole hub is in the trash folder"
  assert_contains "$T/out" "$dest" "says where it went"
  [ -d "$P" ] && [ -d "$R" ] && [ -d "$T/wt-feature" ] && [ -d "$T/hub2" ] || fail "nothing else moved"
  assert_not_contains "$FAKE_LOG" "osascript" "no Finder on Linux"
  restore="$(sed -n 's/^ *to restore: //p' "$T/out")"; [ -n "$restore" ] || fail "prints how to restore"
  eval "$restore" && [ -f "$H/hub.conf" ] && [ -d "$H/.git" ] || fail "the restore line brings it back"
}

reset_hub_trash_macos() {   # AC5 on macOS: the trash CLI when installed, else Finder through osascript
  hub_fixture; push_hub; export FAKE_UNAME=Darwin
  printf 'y\nacme\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1 || { cat "$T/out"; fail "trash CLI exit"; }
  assert_contains "$FAKE_LOG" "trash $H" "the trash CLI moved it"; [ ! -e "$H" ] && [ -d "$HOME/.Trash/hub" ] || fail "in the Trash"
  assert_contains "$T/out" "Put Back" "how to restore"; assert_contains "$T/out" "$HOME/.Trash/hub" "where it went"
  [ ! -e "$HOME/.local/share/ade/trash" ] || fail "not the Linux folder"
}
reset_hub_trash_finder() {   # (the fixture exports TMPDIR inside its test folder, so one fixture per test)
  hub_fixture; push_hub; export FAKE_UNAME=Darwin ADE_TRASH_CLI="$T/no-such-trash"
  printf 'y\nacme\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1 || { cat "$T/out"; fail "Finder exit"; }
  assert_contains "$FAKE_LOG" 'tell application "Finder" to delete' "Finder moved it"; assert_contains "$FAKE_LOG" "[$H]" "the path as one argument"
  [ ! -e "$H" ] && [ -d "$HOME/.Trash/hub" ] || fail "in the Trash (Finder)"; assert_contains "$T/out" "Put Back" "how to restore"
}

reset_hub_trash_fails() {   # a failed move leaves the hub where it was and says so
  hub_fixture; push_hub; export FAKE_UNAME=Darwin FAKE_TRASH_FAIL=1
  printf 'y\nacme\n' | bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; assert_eq "$?" 1 "a failed move is an error"
  [ -f "$H/hub.conf" ] || fail "the hub stays"; assert_contains "$T/out" "still at $H" "says it is still there"
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

ALL="clean_preview_then_yes never_removes_live reset_keeps_hubs reset_keys reset_hub_refusals reset_hub_wrong_name reset_hub_trash_linux reset_hub_trash_macos reset_hub_trash_finder reset_hub_trash_fails uninstall_last journal_lines twice_nothing setup_records_keys"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
