#!/bin/bash
# story A8 layer 4: a clean machine. Install ade from this checkout, make a hub from the real template, set up a real
# git project from the pinned real repos, and run the hub commands; real git and tmux.
. "$(dirname "$0")/lib.sh"
step "install from this checkout"; bash "$REPO/install.sh" "$W/prefix" || fail "install"
export PATH="$W/prefix/bin:$PATH"; fake_claude
[ "$(ade version)" = "ade $(cat "$REPO/VERSION")" ] || fail "version"
step "ade with no hub: the guide's steps and the command (A18)"; ade < /dev/null > "$W/home.out" || fail "ade alone"
grep -q "Your hub  *none yet" "$W/home.out" && grep -q "run ade setup at a terminal" "$W/home.out" || { cat "$W/home.out"; fail "first-run hint"; }
step "ade hub new --no-github (real ade-brain template)"
ade hub new e2e --no-github --dir "$W/hubs" --persona devops-sre --client Example --owner owner1 < /dev/null || fail "hub new"
[ -f "$W/hubs/e2e/hub.conf" ] || fail "hub.conf"; [ "$(cat "$HOME/.config/ade/hub")" = "$W/hubs/e2e" ] || fail "default hub"
step "ade init, agent add, skills add in a real git project"
P="$W/proj"; mkdir -p "$P"; git init -q "$P"; cd "$P" || exit 1
ade init || fail "init"; [ -f .ade/rules.md ] && [ -s .ade/method-version ] || fail "method copied"
ade agent add frontend || fail "agent add"; [ -s .ade/agents/frontend.md ] || fail "frontend copied"
ade skills add git || fail "skills add"; grep -q "plugin install git@ade-skills --scope project" "$HOME/claude.log" || fail "claude plugin install"
ade skills list | grep -q "git" || fail "skills list"
step "ade status and ade doctor"
ade status || fail "status"
ade doctor; rc=$?; echo "doctor exit $rc"; [ "$rc" -le 1 ] || fail "doctor did not run (exit $rc)"
step "ade ui on real tmux"
if command -v tmux > /dev/null; then
  export TMUX_TMPDIR="$W" ADE_TMUX_SOCKET=e2e
  ade ui --detach || fail "ui"; ade ui --detach || fail "ui again"
  [ "$(tmux -L e2e list-sessions -F '#{session_name}' | grep -cx "$(ade ui --session)")" = 1 ] || fail "one session"
  tmux -L e2e kill-server
else echo "no tmux here"; fi
echo; echo "e2e clean: ok"
