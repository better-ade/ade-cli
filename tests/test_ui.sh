#!/bin/bash
# story A6: `ade ui` and `ade dash`. A fake tmux records its calls; a fixture hub supplies sessions, unread counts,
# tickets and events; a real tmux run is added where tmux is installed.
. "$(dirname "$0")/helpers.sh"

ui_fixture() {
  make_hub "$T/hub" hub; printf 'HUB_NAME=acme\n' > "$T/hub/hub.conf"; mkdir -p "$T/hub/projects/api" "$T/hub/projects/web" "$T/hub/ops/db"
  export ADE_HUB="$T/hub" AGENT_STATE="$T/state" ADE_NOW="2026-11-21T10:45:00Z" TMUX_LOG="$T/tmux.log"; mkdir -p "$AGENT_STATE"; : > "$TMUX_LOG"
  cat > "$T/hub/bin/sessions" <<'S'
#!/bin/bash
echo "NAME             FOLDER                     PID      PARENT   STARTED               ROLE       STATUS LAST"
echo "1.2              projects/api               123      -        2026-11-21T10:00:00Z  builder    busy   2026-11-21T10:30:00Z"
echo "db               ops/db                     124      -        2026-11-21T08:00:00Z  -          idle   -"
echo "rev              projects/web               125      -        2026-11-21T10:20:00Z  reviewer   blocked -"
S
  printf '#!/bin/bash\n[ "$1" = --count ] && cat "$AGENT_STATE/unread.$2" 2>/dev/null || echo 0\n' > "$T/hub/bin/inbox"
  printf '#!/bin/bash\n[ "$1" = --list ] || { echo "dispatch $*"; exit 0; }\nprintf "ready\\t1.3\\tprojects/api\\nwaiting\\t2.1\\tprojects/api\\n"\n' > "$T/hub/bin/dispatch"
  printf '#!/bin/bash\nprintf "routine    anthropic:sonnet\\nbuilder    anthropic:opus\\n"\n' > "$T/hub/bin/roles"
  chmod +x "$T/hub/bin/"*
  for i in 1 2 3 4 5 6 7 8 9 10; do
    printf '{"time": "2026-11-21T10:%02d:00Z", "from": "projects/api", "to": "all", "kind": "pushed", "text": "event %s"}\n' "$i" "$i"; done > "$AGENT_STATE/events.jsonl"
  mkdir -p "$T/fakebin"; cat > "$T/fakebin/tmux" <<'F'
#!/bin/bash
[ "$1" = -L ] && shift 2
echo "tmux $*" >> "$TMUX_LOG"
case "$1" in
  has-session) [ -f "$TMUX_LOG.session" ]; exit $? ;;
  new-session) touch "$TMUX_LOG.session" ;;
  list-windows) printf '0\torchestrator\t1\n1\tprojects/api:1.2\t0\n2\tops/db\t0\n3\tprojects/web:rev\t0\n' ;;
  list-panes) cat "$TMUX_LOG.panes" 2>/dev/null ;;
  split-window) echo "%9"; echo "%9 ade-dash" > "$TMUX_LOG.panes" ;;
  kill-pane) rm -f "$TMUX_LOG.panes" ;;
esac
exit 0
F
  printf '#!/bin/bash\necho "claude $*"\n' > "$T/fakebin/claude"; chmod +x "$T/fakebin/tmux" "$T/fakebin/claude"; export PATH="$T/fakebin:$PATH"
}

creates_then_attaches() {   # AC1
  fresh; ui_fixture
  bash "$ADE" ui > "$T/out" 2>&1 || { cat "$T/out"; fail "first ui"; }
  grep -E "^tmux new-session -d -s ade-acme -n orchestrator -c $T/hub .*AGENT_TERMINAL=tmux ADE_UI_SESSION=ade-acme .*claude" "$TMUX_LOG" > /dev/null || { cat "$TMUX_LOG"; fail "tab 0 runs the orchestrator"; }
  grep -q "^tmux attach-session -t =ade-acme" "$TMUX_LOG" || fail "attaches"
  bash "$ADE" ui > "$T/out" 2>&1 || fail "second ui"
  assert_eq "$(grep -c '^tmux new-session' "$TMUX_LOG")" 1 "never duplicated"
  assert_eq "$(grep -c '^tmux attach-session' "$TMUX_LOG")" 2 "the second attaches"
}

work_opens_tab() {   # AC2: with the session up, ade work hands bin/work the tmux mode and the session
  fresh; ui_fixture; printf '#!/bin/bash\necho "work $* AGENT_TERMINAL=${AGENT_TERMINAL:-} ADE_UI_SESSION=${ADE_UI_SESSION:-}"\n' > "$T/hub/bin/work"; chmod +x "$T/hub/bin/work"
  out=$(bash "$ADE" work projects/api); assert_eq "$out" "work projects/api AGENT_TERMINAL= ADE_UI_SESSION=" "no session: unchanged"
  touch "$TMUX_LOG.session"
  out=$(bash "$ADE" work projects/api); assert_eq "$out" "work projects/api AGENT_TERMINAL=tmux ADE_UI_SESSION=ade-acme" "session: a tab in it"
  out=$(AGENT_TERMINAL=iterm bash "$ADE" work projects/api); assert_eq "$out" "work projects/api AGENT_TERMINAL=iterm ADE_UI_SESSION=" "an explicit terminal wins"
  out=$(bash "$ADE" ui --tab-name projects/api 1.2); assert_eq "$out" "projects/api:1.2" "tab name with ticket"
  out=$(bash "$ADE" ui --tab-name ops/db); assert_eq "$out" "ops/db" "tab name without ticket"
}

tab_bar() {   # AC3
  fresh; ui_fixture; mkdir -p "$HOME/.config/ade"; printf 'busy=#ff8800\nblocked=red\n' > "$HOME/.config/ade/theme"
  out=$(bash "$ADE" ui --bar ade-acme); echo "$out" > "$T/out"
  for s in "● 0 orchestrator" "#[fg=#ff8800]⟳ 1 projects/api · builder · 1.2" "○ 2 ops/db" "#[fg=red]⚠ 3 projects/web · reviewer · rev" "[+ new]"; do
    assert_contains "$T/out" "$s" "bar: $s"; done
  printf 'busy=#ff8800;run-shell x\n' > "$HOME/.config/ade/theme"
  bash "$ADE" ui --bar ade-acme > "$T/out" 2>&1; assert_not_contains "$T/out" "run-shell" "a bad colour is ignored"
}

dash_golden() {   # AC4
  fresh; ui_fixture
  bash "$ADE" dash --once > "$T/out" 2>&1 || { cat "$T/out"; fail "dash exit"; }
  diff -u "$REPO/tests/golden/dash.txt" "$T/out" || fail "dash matches the golden file"
}

key_table() {   # AC5
  fresh; ui_fixture; bash "$ADE" ui --detach > /dev/null 2>&1 || fail "ui"
  C="$HOME/.config/ade/ui-ade-acme.tmux.conf"; [ -f "$C" ] || fail "conf written"
  grep -q "^tmux source-file $C" "$TMUX_LOG" || fail "conf loaded"
  for k in "n run-shell" "a run-shell" "t display-popup" "p run-shell" "f run-shell" "? display-popup"; do
    grep -q "^bind-key -T prefix $k" "$C" || fail "binds $k"; done
  grep -q "ui --menu new" "$C" && grep -q "ui --menu approve" "$C" && grep -q "ui --tickets" "$C" && grep -q "ui --menu preview" "$C" \
    && grep -q "ui --sidebar" "$C" && grep -q "ui --keys" "$C" || fail "each key runs its menu or popup"
  bash "$ADE" ui --menu new > /dev/null 2>&1; grep "display-menu" "$TMUX_LOG" | tail -1 > "$T/m"
  for f in projects/api projects/web ops/db; do assert_contains "$T/m" "$f" "folder list: $f"; done
  bash "$ADE" ui --menu role projects/api > /dev/null 2>&1; grep "display-menu" "$TMUX_LOG" | tail -1 > "$T/m"
  assert_contains "$T/m" "work --role builder projects/api" "role list runs ade work"
  bash "$ADE" ui --sidebar > /dev/null 2>&1; grep -q "split-window -h -d -l 44" "$TMUX_LOG" || fail "f opens the sidebar"
  bash "$ADE" ui --sidebar > /dev/null 2>&1; grep -q "kill-pane -t %9" "$TMUX_LOG" || fail "f again closes it"
  bash "$ADE" ui --keys < /dev/null > "$T/out"; for k in n a t p f "?"; do grep -q "^  prefix $k " "$T/out" || fail "help names $k"; done
}

approve_popup() {   # AC6
  fresh; ui_fixture; bash "$ADE" ui --menu approve > /dev/null 2>&1
  grep "display-menu" "$TMUX_LOG" | tail -1 > "$T/m"
  assert_contains "$T/m" "display-popup -E" "runs in a popup terminal"
  assert_contains "$T/m" "dispatch --approve 2.1 projects/api" "the waiting ticket and its folder"
  assert_not_contains "$T/m" "1.3" "only waiting tickets"
  ! grep -qE "script |expect|unbuffer|yes \|" "$T/m" || fail "never a fake TTY"
}

unread_marks() {   # AC7
  fresh; ui_fixture; echo 2 > "$AGENT_STATE/unread.1.2"
  bash "$ADE" ui --bar ade-acme > "$T/out"; assert_contains "$T/out" "projects/api · builder · 1.2 #[fg=" "marked"
  grep -q "✉2" "$T/out" || fail "unread count shown"
  echo 0 > "$AGENT_STATE/unread.1.2"; bash "$ADE" ui --bar ade-acme > "$T/out"; ! grep -q "✉" "$T/out" || fail "cleared after reading"
}

no_tmux_no_glow() {   # AC8
  fresh; ui_fixture; d="$T/notmux"; mkdir -p "$d"; for c in bash python3 sed awk grep cat dirname basename tr head tail mktemp uname env date; do ln -sf "$(command -v "$c")" "$d/$c"; done
  PATH="$d" bash "$ADE" ui > "$T/out" 2>&1; assert_eq "$?" 2 "exit 2"
  if [ "$(uname)" = Darwin ]; then assert_contains "$T/out" "brew install tmux" "macOS command"; else assert_contains "$T/out" "install tmux" "Linux command"; fi
  printf '# Plan\n- step one\n' > "$T/hub/projects/api/PLAN.md"
  out=$(PATH="$d" bash "$ADE" ui --preview projects/api < /dev/null); assert_eq "$out" "# Plan
- step one" "plain text without glow"
  printf '#!/bin/bash\necho "glow $*"\n' > "$d/glow"; chmod +x "$d/glow"
  out=$(PATH="$d" bash "$ADE" ui --preview projects/api < /dev/null); assert_eq "$out" "glow -p $T/hub/projects/api/PLAN.md" "glow when installed"
}

real_tmux() {   # AC1 on a real tmux, when installed
  command -v tmux > /dev/null 2>&1 || { echo "skip: no tmux"; return 0; }
  fresh; make_hub "$T/hub" hub; printf 'HUB_NAME=real\n' > "$T/hub/hub.conf"; export ADE_HUB="$T/hub" TMUX_TMPDIR="$T" ADE_TMUX_SOCKET="ade-test-$$"
  mkdir -p "$T/fakebin"; printf '#!/bin/bash\nsleep 30\n' > "$T/fakebin/claude"; chmod +x "$T/fakebin/claude"; export PATH="$T/fakebin:$PATH"
  unset TMUX
  bash "$ADE" ui --detach > "$T/out" 2>&1 || { cat "$T/out"; fail "real ui"; }
  bash "$ADE" ui --detach > "$T/out" 2>&1 || { cat "$T/out"; fail "real ui again"; }
  n=$(tmux -L "$ADE_TMUX_SOCKET" list-sessions -F '#{session_name}' | grep -c '^ade-real$')
  w=$(tmux -L "$ADE_TMUX_SOCKET" list-windows -t =ade-real -F '#{window_index} #{window_name}' | head -1)
  tmux -L "$ADE_TMUX_SOCKET" kill-server 2>/dev/null
  assert_eq "$n" 1 "one session"; assert_eq "$w" "0 orchestrator" "tab 0 is the orchestrator"
}

ALL="creates_then_attaches work_opens_tab tab_bar dash_golden key_table approve_popup unread_marks no_tmux_no_glow real_tmux"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
