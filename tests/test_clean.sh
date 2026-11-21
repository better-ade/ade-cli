#!/bin/bash
# story A9: ade clean, ade reset, ade uninstall. Fixture hubs and projects; fakes for tmux, launchctl, systemctl and
# the hub's bin/chat, bin/keys, bin/schedule and bin/journal; nothing outside the test folder is touched. reset and
# uninstall answer only a terminal: their answers are typed on a pseudo-terminal (pty_run).
. "$(dirname "$0")/helpers.sh"

# pty_run <input> <command...>: the command on a fresh pseudo-terminal (its own session), the input typed ahead
# (\n escapes); prints what the terminal showed and exits with the command's code
pty_run() {
  python3 -c '
import os, pty, sys
inp = sys.argv[1].encode().decode("unicode_escape").encode() + b"\x04" * 8   # then end-of-input, never a hang
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
os.write(fd, inp)
out = b""
while True:
    try:
        b = os.read(fd, 4096)
    except OSError:
        break
    if not b:
        break
    out += b
sys.stdout.write(out.decode("utf-8", "replace").replace("\r", ""))
_, st = os.waitpid(pid, 0)
sys.exit(os.WEXITSTATUS(st) if os.WIFEXITED(st) else 1)' "$@"
}
dead_pid() { sleep 0 & local p=$!; wait "$p"; echo "$p"; }
clean_fixture() {
  H="$T/hub"; make_hub "$H" hub; echo "HUB_NAME=acme" > "$H/hub.conf"; git init -q "$H"; commit_tag "$H" hub
  export AGENT_STATE="$T/state" TMPDIR="$T/tmp" FAKE_LOG="$T/fake.log"; mkdir -p "$TMPDIR"; : > "$FAKE_LOG"
  S="$AGENT_STATE"; mkdir -p "$S/dispatch" "$S/events-seen" "$S/chat"
  mkdir -p "$S/sync.lock" "$S/dispatch.lock" "$S/chat/lock"; dead_pid > "$S/sync.lock/pid"
  sleep 300 > /dev/null 2>&1 & LIVE=$!; echo "$LIVE" > "$S/dispatch.lock/pid"; dead_pid > "$S/chat/lock/pid"
  : > "$S/dispatch/old-ticket"; touch -t 202001010000 "$S/dispatch/old-ticket"; : > "$S/dispatch/new-ticket"
  : > "$S/events-seen/gone"; touch -t 202001010000 "$S/events-seen/gone"; : > "$S/events-seen/fresh"
  mkdir -p "$TMPDIR/ade.old1" "$TMPDIR/ade.new1" "$TMPDIR/other.old" "$TMPDIR/ade.busy"; : > "$TMPDIR/ade.busy/now"
  touch -t 202001010000 "$TMPDIR/ade.old1" "$TMPDIR/other.old" "$TMPDIR/ade.busy"   # ade.busy: old folder, a fresh file
  P="$T/proj"; mkdir -p "$P"; git init -q -b main "$P" 2>/dev/null || git init -q "$P"; git -C "$P" checkout -q -b main 2>/dev/null
  echo a > "$P/a"; echo .env > "$P/.gitignore"; commit_tag "$P" base
  for b in done wip feature fresh ign pane; do git -C "$P" worktree add -q -b "$b" "$T/wt-$b" main; done
  git -C "$P" worktree add -q --detach "$T/wt-detached" main
  for b in done feature ign pane; do echo "$b" > "$T/wt-$b/$b"; git -C "$T/wt-$b" add "$b"; git -C "$T/wt-$b" commit -qm "$b"; done
  for b in done ign pane; do git -C "$P" merge -q --no-ff -m "merge $b" "$b"; done   # merged, with commits of their own
  echo dirty > "$T/wt-wip/dirty"; echo SECRET=1 > "$T/wt-ign/.env"; export FAKE_PANE_CWD="$T/wt-pane/src"
  mkdir -p "$H/projects/api"; printf '| Repo | Checkout | Branch |\n|---|---|---|\n| o/api | %s | main |\n' "$P" > "$H/projects/api/ACCESS.md"
  mkdir -p "$T/fakebin"; cat > "$T/fakebin/tmux" <<'F'
#!/bin/bash
[ "$1" = -L ] && shift 2
echo "tmux $*" >> "$FAKE_LOG"
case "$1" in
  has-session) exit "${UI_LIVE:-1}" ;;
  list-sessions) [ -f "$FAKE_LOG.gone" ] || echo ade-dead; echo ade-live; echo work ;;
  list-panes) case "$*" in *pane_current_path*) echo "$FAKE_PANE_CWD" ;; *ade-dead*) echo 1; echo 1 ;; *) echo 0 ;; esac ;;
  kill-session) touch "$FAKE_LOG.gone" ;;
esac
exit 0
F
  for c in launchctl systemctl; do printf '#!/bin/bash\necho "%s $*" >> "$FAKE_LOG"\n' "$c" > "$T/fakebin/$c"; done
  cat > "$H/bin/chat" <<'C'
#!/bin/bash
echo "chat $*" >> "$FAKE_LOG"
case "$1" in status) [ -f "$HUB/.running" ] && echo "running since x" || echo stopped ;;
  stop) [ -n "${CHAT_STOP_FAIL:-}" ] && exit 1; rm -f "$HUB/.running" ;; esac
C
  printf '#!/bin/bash\necho "keys $*" >> "$FAKE_LOG"\n' > "$H/bin/keys"
  printf '#!/bin/bash\necho "schedule $*" >> "$FAKE_LOG"\n' > "$H/bin/schedule"
  printf '#!/bin/bash\necho "$*" >> "$HUB/journal.log"\n' > "$H/bin/journal"
  chmod +x "$T/fakebin/"* "$H/bin/"*; export PATH="$T/fakebin:$PATH" ADE_HUB="$H"
  mkdir -p "$HOME/.config/ade"; echo "$H" > "$HOME/.config/ade/hub"; echo "$H" > "$HOME/.config/ade/hubs"
}
stop_live() { kill "$LIVE" 2> /dev/null; wait "$LIVE" 2> /dev/null; return 0; }
listing() { (cd "$T" && find . -path ./tmp -prune -o -path ./state -prune -o -print | grep -v '/\.git/' | LC_ALL=C sort); }
matches() { [[ $1 =~ $2 ]]; }

clean_preview_then_yes() {   # AC1
  fresh; clean_fixture; : > "$T/out"; before="$(listing; ls -R "$AGENT_STATE" "$TMPDIR")"
  bash "$ADE" clean < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; stop_live; fail "preview exit"; }
  assert_eq "$(listing; ls -R "$AGENT_STATE" "$TMPDIR")" "$before" "the preview changes nothing"
  for s in "sync.lock" "chat/lock" "dispatch/old-ticket" "events-seen/gone" "ade.old1" "ade-dead" "wt-done"; do assert_contains "$T/out" "$s" "planned: $s"; done
  assert_not_contains "$FAKE_LOG" "kill-session" "no tmux change in the preview"
  bash "$ADE" clean --yes < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; stop_live; fail "--yes exit"; }
  [ ! -e "$AGENT_STATE/sync.lock" ] && [ ! -e "$AGENT_STATE/chat/lock" ] || fail "stale locks removed"
  [ ! -e "$AGENT_STATE/dispatch/old-ticket" ] && [ -e "$AGENT_STATE/dispatch/new-ticket" ] || fail "only old markers"
  [ ! -e "$AGENT_STATE/events-seen/gone" ] && [ -e "$AGENT_STATE/events-seen/fresh" ] || fail "only expired cursors"
  [ ! -e "$TMPDIR/ade.old1" ] && [ -e "$TMPDIR/ade.new1" ] && [ -e "$TMPDIR/other.old" ] || fail "only ade's old temp folders"
  grep -q "kill-session -t =ade-dead" "$FAKE_LOG" || fail "dead tmux session ended"
  [ ! -e "$T/wt-done" ] || fail "merged clean worktree removed"
  git -C "$P" rev-parse -q --verify refs/heads/done > /dev/null || fail "its branch stays"
  stop_live
}

never_removes_live() {   # AC2 and the review's cases
  fresh; clean_fixture
  bash "$ADE" clean --yes < /dev/null > "$T/out" 2>&1
  [ -f "$AGENT_STATE/dispatch.lock/pid" ] || fail "a live owner's lock is kept"
  [ -f "$T/wt-wip/dirty" ] || fail "a worktree with uncommitted changes is kept"
  [ -d "$T/wt-feature" ] || fail "an unmerged worktree is kept"
  [ -f "$T/wt-ign/.env" ] || fail "a worktree with an ignored file (.env) is kept"
  [ -d "$T/wt-fresh" ] || fail "a fresh branch with no commits of its own is not merged"
  [ -d "$T/wt-pane" ] || fail "a worktree a live tmux pane works in is kept"
  [ -d "$T/wt-detached" ] || fail "a detached worktree is kept"
  [ -d "$TMPDIR/ade.busy" ] || fail "a temp folder with a fresh file is kept"
  ! grep -q "kill-session -t =ade-live" "$FAKE_LOG" || fail "a session with a live agent is kept"
  ! grep -q "kill-session -t =work" "$FAKE_LOG" || fail "only ade-* sessions"
  stop_live
}

lock_gc_guard() {   # the hub's <lock>.gc guard: a lock someone else is checking is left alone, and the guard is ours only
  fresh; clean_fixture; stop_live; mkdir "$AGENT_STATE/sync.lock.gc"
  bash "$ADE" clean --yes < /dev/null > "$T/out" 2>&1
  [ -d "$AGENT_STATE/sync.lock" ] || fail "a lock under another checker's guard is kept"
  [ -d "$AGENT_STATE/sync.lock.gc" ] || fail "another's guard is not removed"
  [ ! -e "$AGENT_STATE/chat/lock.gc" ] || fail "ade's own guard is gone after use"
}

reset_keeps_hubs() {   # AC3
  fresh; clean_fixture; stop_live; touch "$H/.running"; bash "$ADE" orchestrator new one --hub "$H" > /dev/null 2>&1 || fail "new"
  export AGENT_LAUNCHAGENTS="$T/LaunchAgents"; mkdir -p "$AGENT_LAUNCHAGENTS" "$HOME/.config/systemd/user" "$HOME/.claude"
  for j in chat monitor briefing; do : > "$AGENT_LAUNCHAGENTS/ai.agent-hub.acme.$j.plist"; : > "$HOME/.config/systemd/user/ai.agent-hub.acme.$j.service"; done
  mkdir -p "$H/.claude"; echo '{"model": "opus", "enabledPlugins": {"ade@ade-skills": true, "git@ade-skills": true}}' > "$H/.claude/settings.json"
  echo keep > "$HOME/.claude/settings.json"
  before="$(cd "$H" && find . -path ./.git -prune -o -type f -print | grep -v -e '^./.claude/settings.json$' -e '^./.running$' -e '^./journal.log$' | sort; cd "$P" && find . -type f | grep -v '/\.git/' | sort)"
  pty_run 'n\n' bash "$ADE" reset > "$T/out" 2>&1; [ -d "$HOME/.config/ade" ] || fail "no means nothing"
  assert_not_contains "$FAKE_LOG" "chat stop" "nothing stopped without a yes"
  pty_run 'y\n' bash "$ADE" reset > "$T/out" 2>&1 || { cat "$T/out"; fail "reset exit"; }
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

answers_only_from_a_person() {   # review: a pipe or an agent session is refused, before anything changes
  fresh; clean_fixture; stop_live
  printf 'y\n' | bash "$ADE" reset > "$T/out" 2>&1; assert_eq "$?" 2 "a pipe is refused"
  assert_contains "$T/out" "refuses piped" "says why"; [ -d "$HOME/.config/ade" ] || fail "nothing changed (pipe)"
  export CLAUDECODE=1; pty_run 'y\n' bash "$ADE" reset > "$T/out" 2>&1; assert_eq "$?" 2 "an agent session is refused"; unset CLAUDECODE
  assert_contains "$T/out" "Claude Code session" "says why"; [ -d "$HOME/.config/ade" ] || fail "nothing changed (agent)"
  bash "$REPO/install.sh" "$T/prefix" > /dev/null
  printf 'y\n' | "$T/prefix/bin/ade" uninstall > "$T/out" 2>&1; assert_eq "$?" 2 "uninstall refuses a pipe too"
  [ -f "$T/prefix/bin/ade" ] || fail "still installed"
}

orchestrator_stop_fails() {   # review: a failed stop keeps ~/.config/ade, is not reported as stopped, and exits 1
  fresh; clean_fixture; stop_live; touch "$H/.running"; bash "$ADE" orchestrator new one --hub "$H" > /dev/null 2>&1 || fail "new"
  export CHAT_STOP_FAIL=1; pty_run 'y\n' bash "$ADE" reset > "$T/out" 2>&1; assert_eq "$?" 1 "exit 1"
  [ -f "$HOME/.config/ade/orchestrators" ] || fail "the registry is kept"
  assert_not_contains "$H/journal.log" "orchestrators stopped" "not journaled as stopped"
}

reset_keys() {   # AC4
  fresh; clean_fixture; stop_live
  printf '%s\tdeepseek\n%s\ttelegram\n' "$H" "$H" > "$HOME/.config/ade/keys-set"
  pty_run 'y\ny\nn\n' bash "$ADE" reset --keys > "$T/out" 2>&1 || { cat "$T/out"; fail "reset --keys exit"; }
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
echo "trash $*" >> "$FAKE_LOG"; [ -n "${FAKE_TRASH_FAIL:-}" ] && exit 1; mkdir -p "$HOME/.Trash"
if [ -e "$HOME/.Trash/$(basename "$1")" ]; then mv "$1" "$HOME/.Trash/$(basename "$1") 12.00.01"; else mv "$1" "$HOME/.Trash/"; fi
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
refused() {   # <why>: reset --hub with the right answers exits 2, says why, and changes nothing
  pty_run 'y\nacme\n' bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; local rc=$?
  [ "$rc" = 2 ] || { cat "$T/out"; fail "refused ($1): exit $rc"; }
  assert_contains "$T/out" "$1" "says why"; [ -f "$H/hub.conf" ] && [ -d "$HOME/.config/ade" ] || fail "nothing changed ($1)"
  assert_not_contains "$FAKE_LOG" "trash" "no trash call ($1)"; assert_not_contains "$FAKE_LOG" "schedule" "no schedule call ($1)"
}

reset_hub_refusals() {   # AC5: unsaved, ignored, stashed or unpushed work, and a hub in use, are refused first
  hub_fixture; push_hub; echo change >> "$H/hub.conf"; refused "uncommitted"
  git -C "$H" stash -q; refused "stashed"; git -C "$H" stash drop -q
  echo .env > "$H/.gitignore"; commit_tag "$H" ignore; git -C "$H" push -q 2> /dev/null; echo SECRET=1 > "$H/.env"; refused "ignored files"; rm "$H/.env"
  git -C "$H" worktree add -q -b side "$T/hub-side" 2> /dev/null; git -C "$H" push -q -u origin side 2> /dev/null; refused "linked worktree"
  git -C "$H" worktree remove "$T/hub-side"; git -C "$H" branch -q -D side
  mkdir -p "$H/projects/inner"; git init -q "$H/projects/inner"; echo i > "$H/projects/inner/i"
  commit_tag "$H/projects/inner" inner; git -C "$H" add projects/inner 2> /dev/null; git -C "$H" commit -qm gitlink; git -C "$H" push -q 2> /dev/null
  refused "another repository"
  git -C "$H" rm -q --cached projects/inner; rm -rf "$H/projects/inner"; git -C "$H" commit -qm "no inner"; git -C "$H" push -q 2> /dev/null
  echo t > "$H/t"; commit_tag "$H" tagged v-local; git -C "$H" reset -q --hard HEAD~1; refused "not pushed"; git -C "$H" tag -d v-local > /dev/null
  git -C "$H" checkout -q --detach; echo d > "$H/d"; commit_tag "$H" detached; refused "not pushed"; git -C "$H" checkout -q -
  export UI_LIVE=0; refused "live ade ui"; unset UI_LIVE
  printf '#!/bin/bash\necho "NAME STATUS"\necho "api busy"\n' > "$T/sessions"; cp "$H/bin/sessions" "$T/sessions.keep"
  cp "$T/sessions" "$H/bin/sessions"; git -C "$H" commit -qam live; git -C "$H" push -q 2> /dev/null; refused "live agent"
  cp "$T/sessions.keep" "$H/bin/sessions"; git -C "$H" commit -qam idle; git -C "$H" push -q 2> /dev/null
  sleep 300 > /dev/null 2>&1 & L=$!; echo "$L" > "$AGENT_STATE/sync.lock/pid"; refused "live owner"; kill "$L"; wait "$L" 2> /dev/null; return 0
}
reset_hub_refusals_2() {   # (one fixture per test: it exports TMPDIR inside its folder)
  hub_fixture; refused "not pushed anywhere"
  mkdir -p "$T/plain"; make_hub "$T/plain" plain
  pty_run 'y\nplain\n' bash "$ADE" reset --hub "$T/plain" > "$T/out" 2>&1; assert_eq "$?" 2 "a hub outside git cannot be checked"
  bash "$ADE" reset --hub "$T/proj" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "not a hub"
}

reset_hub_path_guards() {   # review: never /, $HOME or a folder holding $HOME or ~/.config/ade
  fresh; clean_fixture; stop_live; make_hub "$HOME" home; git init -q "$HOME"
  bash "$ADE" reset --hub "$HOME" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "the home folder"
  assert_contains "$T/out" "never moves" "says why"
  make_hub "$T" top; bash "$ADE" reset --hub "$T" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "a folder holding home"
  assert_contains "$T/out" "holds your home" "says why"
}

reset_hub_wrong_name() {   # AC5: the hub's name must be typed; a wrong one changes nothing at all
  hub_fixture; push_hub
  pty_run 'y\nwrong\n' bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; assert_eq "$?" 1 "a wrong name stops"
  [ -d "$H" ] && [ -d "$HOME/.config/ade" ] || fail "a wrong name keeps the hub and the setup"
  pty_run 'y\n' bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; [ -d "$H" ] || fail "no name keeps the hub"
}

reset_hub_trash_linux() {   # AC5 on Linux: renamed into ~/.local/share/ade/trash/<hub>-<UTC time>/, never deleted
  hub_fixture; push_hub; cp -R "$H" "$T/hub2"; echo "$T/hub2" >> "$HOME/.config/ade/hubs"; export FAKE_UNAME=Linux
  pty_run 'y\nacme\n' bash "$ADE" reset --hub "$H" > "$T/out" 2>&1 || { cat "$T/out"; fail "pushed hub exit"; }
  [ ! -e "$H" ] || fail "the hub moved away after typing its name"
  dest="$(ls -d "$HOME/.local/share/ade/trash/"* 2> /dev/null)"; [ "$(printf '%s\n' "$dest" | grep -c .)" = 1 ] || fail "one trash folder"
  matches "$(basename "$dest")" '^hub-[0-9]{8}T[0-9]{6}Z$' || fail "named <hub>-<UTC time>: $dest"
  [ -f "$dest/hub.conf" ] && [ -d "$dest/.git" ] && [ -d "$dest/projects/api" ] || fail "the whole hub is in the trash folder"
  assert_contains "$T/out" "$dest" "says where it went"; assert_contains "$FAKE_LOG" "schedule uninstall" "its jobs uninstalled"
  [ -d "$P" ] && [ -d "$R" ] && [ -d "$T/wt-feature" ] && [ -d "$T/hub2" ] || fail "nothing else moved"
  assert_not_contains "$FAKE_LOG" "osascript" "no Finder on Linux"
  assert_contains "$T/hub2/journal.log" "moving the hub $H to the Trash" "journaled before the move"
  assert_contains "$T/hub2/journal.log" "moved to $dest" "and after"
  restore="$(sed -n 's/^ *to restore: //p' "$T/out")"; [ -n "$restore" ] || fail "prints how to restore"
  eval "$restore" && [ -f "$H/hub.conf" ] && [ -z "$(git -C "$H" status --porcelain --ignored)" ] || fail "the restore line brings it back, clean"
  rm -rf "$HOME/.local/share/ade/trash"; mv "$H" "$T/back"; mkdir -p "$HOME/.config/ade"
  pty_run 'y\n' bash "$ADE" reset --hub "$H" > "$T/out" 2>&1 || { cat "$T/out"; fail "second run exit"; }
  assert_contains "$T/out" "nothing to do for $H" "a second reset --hub has nothing to do"
}

reset_hub_trash_macos() {   # AC5 on macOS: the trash CLI when installed, else Finder through osascript
  hub_fixture; push_hub; export FAKE_UNAME=Darwin
  pty_run 'y\nacme\n' bash "$ADE" reset --hub "$H" > "$T/out" 2>&1 || { cat "$T/out"; fail "trash CLI exit"; }
  assert_contains "$FAKE_LOG" "trash $H" "the trash CLI moved it"; [ ! -e "$H" ] && [ -d "$HOME/.Trash/hub" ] || fail "in the Trash"
  assert_contains "$T/out" "Put Back" "how to restore"; assert_contains "$T/out" "$HOME/.Trash/hub" "where it went"
  [ ! -e "$HOME/.local/share/ade/trash" ] || fail "not the Linux folder"
}
reset_hub_trash_clash() {   # review: a name already in the Trash: only the Put Back hint, never a wrong path
  hub_fixture; push_hub; export FAKE_UNAME=Darwin; mkdir -p "$HOME/.Trash/hub"; echo other > "$HOME/.Trash/hub/mine"
  pty_run 'y\nacme\n' bash "$ADE" reset --hub "$H" > "$T/out" 2>&1 || { cat "$T/out"; fail "clash exit"; }
  assert_contains "$T/out" "Put Back" "the hint"; assert_not_contains "$T/out" "$HOME/.Trash/hub" "no path that names the other folder"
  assert_not_contains "$T/out" "mv '" "no mv line"; assert_eq "$(cat "$HOME/.Trash/hub/mine")" other "the other folder untouched"
}
reset_hub_trash_finder() {   # (the fixture exports TMPDIR inside its test folder, so one fixture per test)
  hub_fixture; push_hub; export FAKE_UNAME=Darwin ADE_TRASH_CLI="$T/no-such-trash"
  pty_run 'y\nacme\n' bash "$ADE" reset --hub "$H" > "$T/out" 2>&1 || { cat "$T/out"; fail "Finder exit"; }
  assert_contains "$FAKE_LOG" 'tell application "Finder" to delete' "Finder moved it"; assert_contains "$FAKE_LOG" "[$H]" "the path as one argument"
  [ ! -e "$H" ] && [ -d "$HOME/.Trash/hub" ] || fail "in the Trash (Finder)"; assert_contains "$T/out" "Put Back" "how to restore"
}

reset_hub_trash_fails() {   # a failed move leaves the hub, keeps the setup, says so in the journal, exits 1
  hub_fixture; push_hub; cp -R "$H" "$T/hub2"; echo "$T/hub2" >> "$HOME/.config/ade/hubs"; export FAKE_UNAME=Darwin FAKE_TRASH_FAIL=1
  pty_run 'y\nacme\n' bash "$ADE" reset --hub "$H" > "$T/out" 2>&1; assert_eq "$?" 1 "a failed move is an error"
  [ -f "$H/hub.conf" ] || fail "the hub stays"; assert_contains "$T/out" "still at $H" "says it is still there"
  [ -d "$HOME/.config/ade" ] || fail "the setup is kept"
  assert_contains "$T/hub2/journal.log" "moving the hub $H to the Trash FAILED" "the journal says it failed"
  assert_not_contains "$T/hub2/journal.log" "config removed" "and nothing it did not do"
  [ -z "$(git -C "$H" status --porcelain --ignored)" ] || fail "nothing written into the hub"
}

reset_hub_cross_device() {   # review: Linux moves only by rename on one filesystem; another one is refused
  local shm=/dev/shm
  if ! { [ -d "$shm" ] && [ -w "$shm" ]; } || [ "$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_dev == os.stat(sys.argv[2]).st_dev)' "$shm" "${TMPDIR:-/tmp}")" = True ]; then
    echo "skip reset_hub_cross_device: no second filesystem here" >&2; return 0; fi
  hub_fixture; push_hub; export FAKE_UNAME=Linux; X="$(mktemp -d "$shm/ade-test.XXXXXX")"; trap 'rm -rf "$X"; drop_t' EXIT
  git clone -q "$R" "$X/hub" 2> /dev/null; cp "$H/hub.conf" "$X/hub/" 2> /dev/null; H="$X/hub"
  refused "another filesystem"
}

uninstall_last() {   # AC6
  fresh; clean_fixture; stop_live; bash "$REPO/install.sh" "$T/prefix" > /dev/null
  pty_run 'y\n' "$T/prefix/bin/ade" uninstall > "$T/out" 2>&1 || { cat "$T/out"; fail "uninstall exit"; }
  [ ! -e "$T/prefix/bin/ade" ] || fail "binary removed"; [ ! -e "$HOME/.config/ade" ] || fail "reset first"
  assert_contains "$T/out" "install.sh | bash" "how to reinstall"
  [ "$(grep -v '^$' "$T/out" | tail -1 | grep -c install.sh)" = 1 ] || fail "the binary goes last"
  bash "$ADE" uninstall < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "a checkout is never removed"; [ -f "$ADE" ] || fail "checkout kept"
}

journal_lines() {   # AC7
  fresh; clean_fixture; bash "$ADE" clean --yes < /dev/null > /dev/null 2>&1; stop_live
  assert_eq "$(grep -c 'ade clean' "$H/journal.log")" 1 "one clean line"
  pty_run 'y\n' bash "$ADE" reset > /dev/null 2>&1; assert_eq "$(grep -c 'ade reset' "$H/journal.log")" 1 "one reset line"
}

twice_nothing() {   # AC8
  fresh; clean_fixture; bash "$ADE" clean --yes < /dev/null > /dev/null 2>&1; stop_live; rm -f "$AGENT_STATE/dispatch.lock/pid"; rmdir "$AGENT_STATE/dispatch.lock"
  bash "$ADE" clean --yes < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "nothing to clean" "clean twice"
  pty_run 'y\n' bash "$ADE" reset > /dev/null 2>&1; bash "$ADE" reset < /dev/null > "$T/out" 2>&1 || fail "second reset exit"
  assert_contains "$T/out" "nothing to reset" "reset twice"
}

setup_records_keys() {   # the record --keys relies on: ade setup notes which keys it stored (names only)
  fresh; clean_fixture; stop_live; printf 'y\ntok-xyz\n' | bash "$ADE" setup --telegram > /dev/null 2>&1
  assert_eq "$(cat "$HOME/.config/ade/keys-set")" "$H	telegram" "recorded"; assert_not_contains "$HOME/.config/ade/keys-set" "tok-xyz" "never the value"
}

ALL="clean_preview_then_yes never_removes_live lock_gc_guard reset_keeps_hubs answers_only_from_a_person orchestrator_stop_fails reset_keys reset_hub_refusals reset_hub_refusals_2 reset_hub_path_guards reset_hub_wrong_name reset_hub_trash_linux reset_hub_trash_macos reset_hub_trash_clash reset_hub_trash_finder reset_hub_trash_fails reset_hub_cross_device uninstall_last journal_lines twice_nothing setup_records_keys"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
