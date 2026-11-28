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
echo "1.2              projects/api               123      -        2026-11-21T10:00:00Z  builder    busy   2026-11-21T10:30:00Z"; echo x >> "$AGENT_STATE/sessions.calls"
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
[ "$1" = -V ] && { echo "tmux ${FAKE_TMUX_V:-3.4}"; exit 0; }
[ "$1" = -L ] && shift 2
echo "tmux $*" >> "$TMUX_LOG"
case "$1" in
  has-session) [ -f "$TMUX_LOG.session" ]; exit $? ;;
  new-session) touch "$TMUX_LOG.session" ;;
  list-windows) if [ -n "${FAKE_WINDOWS:-}" ]; then printf "$FAKE_WINDOWS"; else printf '0\torchestrator\t1\n1\tprojects/api:1.2\t0\n2\tops/db\t0\n3\tprojects/web:rev\t0\n'; fi ;;
  list-panes) cat "$TMUX_LOG.panes" 2>/dev/null ;;
  list-sessions) cat "$TMUX_LOG.sessions" 2>/dev/null ;;
  display-message) echo "/tmp/fake-tmux/ade" ;;
  split-window) echo "%9"; echo "%9 ade-dash" > "$TMUX_LOG.panes" ;;
  kill-pane) rm -f "$TMUX_LOG.panes" ;;
esac
exit 0
F
  printf '#!/bin/bash\necho "claude $*"\n' > "$T/fakebin/claude"
  # the things that open a window, and the process list: recorded, never real
  for c in osascript open; do printf '#!/bin/bash\necho "%s $*" >> "$TMUX_LOG.windows"\n' "$c" > "$T/fakebin/$c"; done
  printf '#!/bin/bash\n[ -f "$TMUX_LOG.orchestrator" ]\n' > "$T/fakebin/pgrep"
  chmod +x "$T/fakebin/"*; export PATH="$T/fakebin:$PATH"; unset TMUX ADE_UI AGENT_TERMINAL ADE_UI_SESSION ADE_HOOK_BIN ADE_HOOK_PORT ADE_HOOK_TOKEN ADE_PTY_ID
  S="$(bash "$ADE" ui --session)"
}

creates_then_attaches() {   # AC1
  fresh; ui_fixture
  bash "$ADE" ui > "$T/out" 2>&1 || { cat "$T/out"; fail "first ui"; }
  grep -E "^tmux new-session -d -s $S -n orchestrator -c $T/hub .*AGENT_TERMINAL=tmux ADE_UI_SESSION=$S .*claude" "$TMUX_LOG" > /dev/null || { cat "$TMUX_LOG"; fail "tab 0 runs the orchestrator"; }
  grep -q "^tmux attach-session -t =$S" "$TMUX_LOG" || fail "attaches"
  bash "$ADE" ui > "$T/out" 2>&1 || fail "second ui"
  assert_eq "$(grep -c '^tmux new-session' "$TMUX_LOG")" 1 "never duplicated"
  assert_eq "$(grep -c '^tmux attach-session' "$TMUX_LOG")" 2 "the second attaches"
}

# a fake bin/work that says what it was handed and, as the hub's tmux mode does today, opens its own detached tmux
# session named after the folder's last part (the hub does not know ade's session name or socket)
fake_work() {
  cat > "$T/hub/bin/work" <<'W'
#!/bin/bash
echo "work $* AGENT_TERMINAL=${AGENT_TERMINAL:-} ADE_UI_SESSION=${ADE_UI_SESSION:-} TMUX=${TMUX:-}"
[ -z "${WORK_EXIT:-}" ] || exit "$WORK_EXIT"
if [ "${AGENT_TERMINAL:-}" = tmux ]; then f=""; for a in "$@"; do case "$a" in projects/*|ops/*) f="${a##*/}" ;; esac; done
  [ -n "${WORK_IN_SESSION:-}" ] || { tmux new-session -d -s "$f" -c "$PWD" "sleep 30"; echo "$f" >> "$TMUX_LOG.sessions"; }
elif [ "${AGENT_TERMINAL:-}" != ade ]; then osascript -e 'tell application "Terminal" to do script'; fi
W
  chmod +x "$T/hub/bin/work"
}
work_opens_tab() {   # AC2, and "focus work opens a tab, never a new window"
  fresh; ui_fixture; fake_work
  touch "$TMUX_LOG.session"; echo "$S" > "$TMUX_LOG.sessions"
  out=$(bash "$ADE" work projects/api 2> "$T/err"); assert_eq "$out" "work projects/api AGENT_TERMINAL=tmux ADE_UI_SESSION=$S TMUX=/tmp/fake-tmux/ade" "session: tmux mode, the session, and ade's own tmux server"
  assert_contains "$TMUX_LOG" "tmux rename-window -t =api: projects/api" "the session the hub opened gets the tab's name"
  assert_contains "$TMUX_LOG" "tmux move-window -d -s =api: -t =$S:" "and becomes a tab of the ade ui session"
  [ ! -e "$TMUX_LOG.windows" ] || fail "no Terminal window (osascript, open)"; assert_eq "$(grep -c '^tmux new-session .*-n orchestrator' "$TMUX_LOG")" 0 "the session was there: not made again"
  assert_eq "$(cat "$T/err")" "" "and nothing more is said"
  : > "$TMUX_LOG"; out=$(WORK_IN_SESSION=1 bash "$ADE" work projects/api 2>&1); assert_not_contains "$TMUX_LOG" "move-window" "a hub that opens the tab itself: nothing to move"
  out=$(AGENT_TERMINAL=iterm bash "$ADE" work projects/api); assert_eq "$out" "work projects/api AGENT_TERMINAL=iterm ADE_UI_SESSION= TMUX=" "an explicit terminal wins"
  out=$(bash "$ADE" ui --tab-name projects/api 1.2); assert_eq "$out" "projects/api:1.2" "tab name with ticket"
  out=$(bash "$ADE" ui --tab-name ops/db); assert_eq "$out" "ops/db" "tab name without ticket"
  : > "$TMUX_LOG"; echo "$S" > "$TMUX_LOG.sessions"   # the orchestrator in tab 0 calls ade work: an agent, no terminal
  out=$(CLAUDECODE=1 AGENT_TERMINAL=tmux ADE_UI_SESSION="$S" TMUX="/tmp/fake-tmux/ade,1,0" bash "$ADE" work projects/web < /dev/null 2> /dev/null)
  assert_eq "$out" "work projects/web AGENT_TERMINAL=tmux ADE_UI_SESSION=$S TMUX=/tmp/fake-tmux/ade,1,0" "from tab 0: the same, its own TMUX kept"
  assert_contains "$TMUX_LOG" "tmux move-window -d -s =web: -t =$S:" "still a tab, with nobody at a terminal"
  WORK_EXIT=3 bash "$ADE" work projects/api > /dev/null 2>&1; assert_eq "$?" 3 "the hub's exit code comes back"
}
work_makes_the_session() {   # no ade ui session yet: ade makes it, detached, and the work is a tab in it
  fresh; ui_fixture; fake_work
  out=$(bash "$ADE" work projects/api --role builder 2> "$T/err") || { cat "$T/err"; fail "work"; }
  grep -E "^tmux new-session -d -s $S -n orchestrator -c $T/hub .*AGENT_TERMINAL=tmux ADE_UI_SESSION=$S .*claude" "$TMUX_LOG" > /dev/null || { cat "$TMUX_LOG"; fail "the session is made as ade ui --detach makes it: tab 0 the orchestrator"; }
  assert_not_contains "$TMUX_LOG" "attach-session" "detached: nobody is attached"
  assert_eq "$out" "work projects/api --role builder AGENT_TERMINAL=tmux ADE_UI_SESSION=$S TMUX=/tmp/fake-tmux/ade" "then bin/work in tmux mode"
  assert_contains "$TMUX_LOG" "tmux move-window -d -s =api: -t =$S:" "a tab in it"
  assert_eq "$(cat "$T/err")" "ade: projects/api is a tab in $S; ade ui shows it" "one line: where the tab is"
  [ ! -e "$TMUX_LOG.windows" ] || fail "no Terminal window (osascript, open)"
  fresh; ui_fixture; fake_work; touch "$TMUX_LOG.orchestrator"   # the owner's case: the main agent runs outside tmux (plain ade claude)
  bash "$ADE" work projects/api > "$T/out" 2> "$T/err" || { cat "$T/err"; fail "work"; }
  grep -E "^tmux new-session -d -s $S -n orchestrator -c $T/hub .* ui --place" "$TMUX_LOG" > /dev/null || { cat "$TMUX_LOG"; fail "tab 0 keeps the orchestrator's place"; }
  ! grep -E "^tmux new-session .* claude" "$TMUX_LOG" > /dev/null || fail "never a second orchestrator"
  assert_contains "$TMUX_LOG" "tmux move-window -d -s =api: -t =$S:" "the work is a tab all the same"; [ ! -e "$TMUX_LOG.windows" ] || fail "no Terminal window"
  bash "$ADE" ui --place < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "Your main agent is running in another terminal." "the place says why it is empty"
  assert_contains "$T/out" "claude --remote-control acme" "and Enter starts it here"
}
work_plain() {   # the ways out: ADE_UI=off, no tmux, the ADE app
  fresh; ui_fixture; fake_work
  out=$(ADE_UI=off bash "$ADE" work projects/api 2> "$T/err"); assert_eq "$out" "work projects/api AGENT_TERMINAL= ADE_UI_SESSION= TMUX=" "ADE_UI=off: as before"
  assert_not_contains "$TMUX_LOG" "new-session" "no session made"; assert_eq "$(cat "$T/err")" "" "and nothing said"
  printf '#!/bin/bash\nexit 0\n' > "$T/hook"; chmod +x "$T/hook"
  out=$(ADE_HOOK_BIN="$T/hook" ADE_HOOK_PORT=1 ADE_HOOK_TOKEN=t ADE_PTY_ID=p bash "$ADE" work projects/api 2> "$T/err")
  assert_eq "$out" "work projects/api AGENT_TERMINAL= ADE_UI_SESSION= TMUX=" "inside the ADE app: nothing changes (the hub opens its sub-terminal)"
  assert_not_contains "$TMUX_LOG" "new-session" "no tmux session there"; assert_eq "$(cat "$T/err")" "" "nothing said"
  d="$T/notmux"; mkdir -p "$d"; for c in bash python3 sed awk grep cat dirname basename tr head tail mktemp uname env date cksum; do ln -sf "$(command -v "$c")" "$d/$c"; done
  cp "$T/fakebin/osascript" "$d/osascript"; cp "$T/fakebin/claude" "$d/claude"   # F1: ade work checks Claude Code first
  out=$(PATH="$d" bash "$ADE" work projects/api 2> "$T/err"); assert_eq "$out" "work projects/api AGENT_TERMINAL= ADE_UI_SESSION= TMUX=" "no tmux: as before"
  assert_eq "$(cat "$T/err")" "ade: tabs for focus work need tmux; ade setup --tools installs it" "with one line on how to get tabs"
}
claude_in_the_session() {   # ade claude at a terminal runs the main agent as tab 0 of the ade ui session
  fresh; ui_fixture; fake_work; local d
  pty_run "" bash "$ADE" claude > "$T/out" 2>&1 || { cat "$T/out"; fail "ade claude"; }
  grep -E "^tmux new-session -d -s $S -n orchestrator -c $T/hub .*AGENT_TERMINAL=tmux ADE_UI_SESSION=$S .*claude" "$TMUX_LOG" > /dev/null || { cat "$TMUX_LOG" "$T/out"; fail "tab 0 runs the main agent"; }
  grep -q "^tmux attach-session -t =$S" "$TMUX_LOG" || fail "and the person is attached to it"
  assert_not_contains "$T/out" "claude --remote-control" "not also outside tmux"
  : > "$TMUX_LOG"; AGENT_TERMINAL=tmux ADE_UI_SESSION="$S" pty_run "" bash "$ADE" claude > "$T/out" 2>&1   # what tab 0 itself runs
  assert_contains "$T/out" "claude --remote-control acme" "inside the session: Claude Code itself"; assert_not_contains "$TMUX_LOG" "attach-session" "never a session in a session"
  : > "$TMUX_LOG"; rm -f "$TMUX_LOG.session"; ADE_UI=off pty_run "" bash "$ADE" claude > "$T/out" 2>&1
  assert_contains "$T/out" "claude --remote-control acme" "ADE_UI=off: the plain way"; assert_eq "$(cat "$TMUX_LOG")" "" "no tmux at all"
  pty_run "" bash "$ADE" claude -- --resume > "$T/out" 2>&1; assert_contains "$T/out" "claude --remote-control acme --resume" "ade claude -- args keeps its meaning"
  assert_not_contains "$TMUX_LOG" "new-session" "and runs where it was typed"
  bash "$ADE" claude < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "claude --remote-control acme" "no terminal: the plain way"; assert_not_contains "$TMUX_LOG" "new-session" "no session"
  pty_run "" bash "$ADE" claude projects/api > "$T/out" 2>&1; assert_contains "$T/out" "work projects/api AGENT_TERMINAL=tmux" "ade claude <folder> is still ade work <folder>"
  : > "$TMUX_LOG"; printf '#!/bin/bash\nexit 0\n' > "$T/hook"; chmod +x "$T/hook"
  ADE_HOOK_BIN="$T/hook" ADE_HOOK_PORT=1 ADE_HOOK_TOKEN=t ADE_PTY_ID=p pty_run "" bash "$ADE" claude > "$T/out" 2>&1
  assert_contains "$T/out" "claude --remote-control acme" "inside the ADE app: the plain way"; assert_eq "$(cat "$TMUX_LOG")" "" "no tmux"
  d="$T/notmux"; mkdir -p "$d"; for c in bash python3 git sed awk grep cat dirname basename tr head tail mktemp uname env date cksum stty mkdir chmod mv rm ls cp touch sort wc cut readlink id; do ln -sf "$(command -v "$c")" "$d/$c"; done
  cp "$T/fakebin/claude" "$d/claude"; PATH="$d" pty_run "" "$(command -v bash)" "$ADE" claude > "$T/out" 2>&1
  assert_contains "$T/out" "claude --remote-control acme" "no tmux: the plain way"
  assert_contains "$T/out" "ade: tabs for focus work need tmux; ade setup --tools installs it" "with one line on how to get tabs"
}

tab_bar() {   # AC3
  fresh; ui_fixture; mkdir -p "$HOME/.config/ade"; printf 'busy=#ff8800\nblocked=red\n' > "$HOME/.config/ade/theme"
  out=$(bash "$ADE" ui --bar "$S"); echo "$out" > "$T/out"
  for s in "● 0 orchestrator" "#[fg=#ff8800]⟳ 1 projects/api · builder · 1.2" "○ 2 ops/db" "#[fg=red]⚠ 3 projects/web · reviewer · rev" "[+ agent]"; do
    assert_contains "$T/out" "$s" "bar: $s"; done
  printf 'busy=#ff8800;run-shell x\n' > "$HOME/.config/ade/theme"
  bash "$ADE" ui --bar "$S" > "$T/out" 2>&1; assert_not_contains "$T/out" "run-shell" "a bad colour is ignored"
}

dash_golden() {   # AC4
  fresh; ui_fixture
  COLUMNS=100 bash "$ADE" dash --once > "$T/out" 2>&1 || { cat "$T/out"; fail "dash exit"; }
  diff -u "$REPO/tests/golden/dash.txt" "$T/out" || fail "dash matches the golden file"
}

key_table() {   # AC5
  fresh; ui_fixture; bash "$ADE" ui --detach > /dev/null 2>&1 || fail "ui"
  C="$HOME/.config/ade/ui-$S.tmux.conf"; [ -f "$C" ] || fail "conf written"
  grep -q "^tmux source-file $C" "$TMUX_LOG" || fail "conf loaded"
  for k in "n run-shell" "a run-shell" "t display-popup" "p run-shell" "f run-shell" "? display-popup" "e display-popup" "l run-shell"; do
    grep -q "^bind-key -T prefix $k" "$C" || fail "binds $k"; done
  grep -q "ui --menu new" "$C" && grep -q "ui --menu approve" "$C" && grep -q "ui --tickets" "$C" && grep -q "ui --menu preview" "$C" \
    && grep -q "ui --sidebar" "$C" && grep -q "ui --keys" "$C" && grep -q "ade' files\"$" "$C" && grep -q "ui --menu links #{pane_id}" "$C" \
    || fail "each key runs its menu or popup"
  bash "$ADE" ui --menu new > /dev/null 2>&1; grep "display-menu" "$TMUX_LOG" | tail -1 > "$T/m"
  for f in projects/api projects/web ops/db; do assert_contains "$T/m" "$f" "folder list: $f"; done
  bash "$ADE" ui --menu role projects/api > /dev/null 2>&1; grep "display-menu" "$TMUX_LOG" | tail -1 > "$T/m"
  assert_contains "$T/m" "work --role builder projects/api" "role list runs ade work"
  bash "$ADE" ui --sidebar > /dev/null 2>&1; grep -q "split-window -h -d -l 44" "$TMUX_LOG" || fail "f opens the sidebar"
  bash "$ADE" ui --sidebar > /dev/null 2>&1; grep -q "kill-pane -t %9" "$TMUX_LOG" || fail "f again closes it"
  bash "$ADE" ui --keys < /dev/null > "$T/out"; for k in n a t p f e l "?"; do grep -q "^  prefix $k " "$T/out" || fail "help names $k"; done
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
  bash "$ADE" ui --bar "$S" > "$T/out"; assert_contains "$T/out" "projects/api · builder · 1.2 #[fg=" "marked"
  grep -q "✉2" "$T/out" || fail "unread count shown"
  echo 0 > "$AGENT_STATE/unread.1.2"; sleep 2; bash "$ADE" ui --bar "$S" > "$T/out"; ! grep -q "✉" "$T/out" || fail "cleared after reading"
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
  RS="$(bash "$ADE" ui --session)"; n=$(tmux -L "$ADE_TMUX_SOCKET" list-sessions -F "#{session_name}" | grep -cx "$RS")
  w=$(tmux -L "$ADE_TMUX_SOCKET" list-windows -t "=$RS" -F '#{window_index} #{window_name}' | head -1)
  tmux -L "$ADE_TMUX_SOCKET" kill-server 2>/dev/null
  assert_eq "$n" 1 "one session"; assert_eq "$w" "0 orchestrator" "tab 0 is the orchestrator"
}

bare_no_agents() {   # story F1 AC4: bare ade outside the tab view, no agents: one line instead of an empty header; not ade itself
  fresh; ui_fixture; printf '#!/bin/bash\necho "NAME             FOLDER                     PID"\n' > "$T/hub/bin/sessions"
  local how; for how in plain pty; do
    if [ "$how" = plain ]; then bash "$ADE" < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "ade"; }
    else ADE_UI=off pty_run "" bash "$ADE" > "$T/out" 2>&1 || { cat "$T/out"; fail "ade at a terminal, ADE_UI=off"; }; fi
    assert_contains "$T/out" "agents: none running" "[$how] says so"; assert_not_contains "$T/out" "NAME " "[$how] no empty header"
    ! grep -qE '^ +ade {2,}' "$T/out" || { cat "$T/out"; fail "[$how] the next steps do not offer ade itself"; }
    assert_contains "$T/out" "  ade work <folder>    start a focus agent on a folder" "[$how] the other next steps stay"
  done
  bash "$ADE" home > "$T/out" 2>&1; assert_contains "$T/out" "agents: none running" "ade home: the same line"
  assert_contains "$T/out" "  ade                  open your workspace" "ade home still offers ade (another command)"
}

bare_ade_opens_the_tabs() {   # "ade ui as the default": ade alone, at a terminal, with a hub that is set up
  fresh; ui_fixture; fake_work; local d; echo "HUB_ROOT_PROVIDER=anthropic" >> "$T/hub/hub.conf"
  pty_run "" bash "$ADE" > "$T/out" 2>&1 || { cat "$T/out"; fail "ade"; }
  grep -E "^tmux new-session -d -s $S -n orchestrator -c $T/hub .*claude" "$TMUX_LOG" > /dev/null || { cat "$TMUX_LOG" "$T/out"; fail "ade alone makes the session, the main agent as tab 0"; }
  grep -q "^tmux attach-session -t =$S" "$TMUX_LOG" || fail "and attaches"; assert_not_contains "$T/out" "next:" "not the summary"
  pty_run "" bash "$ADE" > "$T/out" 2>&1; assert_eq "$(grep -c '^tmux new-session' "$TMUX_LOG")" 1 "a session that is there is attached to, not made again"
  assert_eq "$(grep -c '^tmux attach-session' "$TMUX_LOG")" 2 "attached"
  : > "$TMUX_LOG"; bash "$ADE" home > "$T/sum" 2>&1 || fail "ade home"   # the summary keeps a name of its own
  for l in "hub: acme ($T/hub)" "1.2              projects/api" "next:" "  ade                  open your workspace: a tab per agent (ade ui)" "  ade work <folder>    start a focus agent on a folder"; do assert_contains "$T/sum" "$l" "ade home: $l"; done
  assert_eq "$(cat "$TMUX_LOG")" "" "ade home never opens anything"
  bash "$ADE" status > "$T/out" 2>&1; assert_contains "$T/out" "NAME             FOLDER" "ade status is still the hub's sessions"; assert_not_contains "$T/out" "next:" "and only that"
  bash "$ADE" < /dev/null > "$T/out" 2>&1; assert_eq "$(cat "$T/out")" "$(grep -v '^  ade  ' "$T/sum")" "no terminal: the summary, as before (less ade itself, F1)"; assert_eq "$(cat "$TMUX_LOG")" "" "nothing opened"
  CLAUDECODE=1 pty_run "" bash "$ADE" > "$T/out" 2>&1; assert_contains "$T/out" "hub: acme" "an agent session: the summary"; assert_eq "$(cat "$TMUX_LOG")" "" "nothing opened"
  ADE_UI=off pty_run "" bash "$ADE" > "$T/out" 2>&1; assert_contains "$T/out" "hub: acme" "ADE_UI=off: the summary"; assert_eq "$(cat "$TMUX_LOG")" "" "nothing opened"
  assert_not_contains "$T/out" "needs tmux" "and no word about tmux"
  ADE_UI_SESSION="$S" AGENT_TERMINAL=tmux pty_run "" bash "$ADE" > "$T/out" 2>&1   # typed in a tab of the session
  assert_contains "$T/out" "hub: acme" "inside the session: the summary"; assert_contains "$T/out" "You are in the tab view already; its keys: prefix ?" "and the key hint"
  assert_not_contains "$TMUX_LOG" "attach-session" "never a session in a session"
  TMUX="/tmp/tmux-1/${ADE_TMUX_SOCKET:-ade},1,0" pty_run "" bash "$ADE" > "$T/out" 2>&1; assert_contains "$T/out" "its keys: prefix ?" "a focus tab too (ade's own tmux server)"
  assert_not_contains "$TMUX_LOG" "attach-session" "not nested"
  d="$T/notmux"; mkdir -p "$d"; for c in bash python3 git sed awk grep cat dirname basename tr head tail mktemp uname env date cksum stty mkdir chmod mv rm ls cp touch sort wc cut readlink id; do ln -sf "$(command -v "$c")" "$d/$c"; done
  cp "$T/fakebin/claude" "$d/claude"; PATH="$d" pty_run "" "$(command -v bash)" "$ADE" > "$T/out" 2>&1
  assert_contains "$T/out" "hub: acme" "no tmux: the summary"; assert_contains "$T/out" "The tab view needs tmux; ade setup --tools installs it." "and the one line"
  PATH="$d" "$(command -v bash)" "$ADE" < /dev/null > "$T/out" 2>&1; assert_not_contains "$T/out" "needs tmux" "not without a terminal"
  fresh; ui_fixture; rm -rf "$T/hub/projects"; : > "$TMUX_LOG"   # a hub whose guide has a required step left
  pty_run "n\n" bash "$ADE" > "$T/out" 2>&1; assert_contains "$T/out" "ADE set-up guide (ade setup)" "set-up not finished: the step list"
  assert_contains "$T/out" "Set up now? [Y/n]" "and its offer"; assert_not_contains "$TMUX_LOG" "new-session" "no tab view yet"
  bash "$ADE" < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "hub: acme" "without a terminal: the summary, as before"
}

work_real_tmux() {   # a real tmux on a private socket: a bin/work that opens its own session, as the hub's does, ends as a tab
  command -v tmux > /dev/null 2>&1 || { echo "skip: no tmux"; return 0; }
  fresh; make_hub "$T/hub" hub; printf 'HUB_NAME=real\n' > "$T/hub/hub.conf"; mkdir -p "$T/hub/projects/api"
  export ADE_HUB="$T/hub" TMUX_TMPDIR="$T" ADE_TMUX_SOCKET="ade-test-$$"; unset TMUX ADE_UI AGENT_TERMINAL ADE_UI_SESSION
  mkdir -p "$T/fakebin"; printf '#!/bin/bash\nsleep 30\n' > "$T/fakebin/claude"; printf '#!/bin/bash\nexit 1\n' > "$T/fakebin/pgrep"; chmod +x "$T/fakebin/"*; export PATH="$T/fakebin:$PATH"
  printf '#!/bin/bash\n[ "$AGENT_TERMINAL" = tmux ] || exit 9\ntmux new-session -d -s api -c "$HUB" "sleep 30"\n' > "$T/hub/bin/work"; chmod +x "$T/hub/bin/work"
  bash "$ADE" work projects/api > "$T/out" 2>&1 || { cat "$T/out"; tmux -L "$ADE_TMUX_SOCKET" kill-server 2> /dev/null; fail "work"; }
  RS="$(bash "$ADE" ui --session)"; w="$(tmux -L "$ADE_TMUX_SOCKET" list-windows -t "=$RS" -F '#{window_index} #{window_name}' | tr '\n' ';')"
  n="$(tmux -L "$ADE_TMUX_SOCKET" list-sessions -F '#{session_name}' | tr '\n' ';')"; tmux -L "$ADE_TMUX_SOCKET" kill-server 2> /dev/null
  assert_eq "$w" "0 orchestrator;1 projects/api;" "tab 0 the orchestrator, tab 1 the focus work"; assert_eq "$n" "$RS;" "one session: the hub's own was taken in"
  assert_contains "$T/out" "ade: projects/api is a tab in $RS; ade ui shows it" "and the line"
  ! tmux list-sessions 2> /dev/null | grep -q "^api:" || fail "nothing on the default tmux server"
}

session_names() {   # review: the session name carries a short hash of the hub path (two hubs named acme never share one)
  fresh; ui_fixture; [[ $S =~ ^ade-acme-[0-9a-f]{6}$ ]] || fail "name and hash: $S"
  make_hub "$T/other" other; echo "HUB_NAME=acme" > "$T/other/hub.conf"
  [ "$(ADE_HUB="$T/other" bash "$ADE" ui --session)" != "$S" ] || fail "another hub named acme gets another session"
}

menu_skips_bad_folders() {   # review: a folder name that is not a plain name never reaches a tmux command
  fresh; ui_fixture; mkdir -p "$T/hub/projects/a\$(touch $T/pwned)" "$T/hub/projects/.hidden" "$T/hub/ops/b;c"
  bash "$ADE" ui --menu new > /dev/null 2>&1; grep "display-menu" "$TMUX_LOG" | tail -1 > "$T/m"
  assert_contains "$T/m" "projects/api" "good folders listed"
  for bad in 'touch' '.hidden' 'b;c'; do assert_not_contains "$T/m" "$bad" "skipped: $bad"; done
  [ ! -e "$T/pwned" ] || fail "nothing ran"
}

sq_refuses() {   # review: paths with $, \\, # or quotes are refused before they go into the tmux config
  fresh; ui_fixture; for d in 'h$x' 'h#x' 'h\x'; do make_hub "$T/$d" h
    ADE_HUB="$T/$d" bash "$ADE" ui --detach > "$T/out" 2>&1; assert_eq "$?" 2 "refused: $d"; done
}

bar_cached() {   # review: the bar's data is cached for 2 seconds (each client redraws every 2 s)
  fresh; ui_fixture; export ADE_UI_CACHE_SECONDS=60   # a slow machine never straddles the window
  bash "$ADE" ui --bar "$S" > /dev/null; bash "$ADE" ui --bar "$S" > /dev/null
  assert_eq "$(wc -l < "$AGENT_STATE/sessions.calls" | tr -d ' ')" 1 "bin/sessions read once within the cache window"
  ADE_UI_CACHE_SECONDS=0 bash "$ADE" ui --bar "$S" > /dev/null
  assert_eq "$(wc -l < "$AGENT_STATE/sessions.calls" | tr -d ' ')" 2 "and again after it"
}

dash_tokens_and_events() {   # UX review: TOKENS only when bin/sessions reports it; events read as plain sentences
  fresh; ui_fixture
  printf '{"time": "2026-11-21T10:11:00Z", "from": "ops/db", "to": "all", "kind": "idle", "text": "tests green"}\n{"time": "2026-11-21T10:12:00Z", "from": "projects/web", "to": "main", "kind": "blocked", "text": "needs the API key"}\n' >> "$AGENT_STATE/events.jsonl"
  COLUMNS=100 bash "$ADE" dash --once > "$T/out" 2>&1
  assert_not_contains "$T/out" "TOKENS" "no TOKENS column when no session reports usage"
  assert_contains "$T/out" "10:10 api pushed event 10" "pushed: folder name, kind, text"
  assert_contains "$T/out" "10:11 db idle" "idle reads short"; assert_not_contains "$T/out" "tests green" "without the STATE text"
  assert_contains "$T/out" "10:12 web blocked: needs the API key" "blocked with its reason"
  sed -i.bak 's/STATUS LAST"/STATUS LAST TOKENS"/; s/2026-11-21T10:30:00Z"/2026-11-21T10:30:00Z 12.3k"/; s/idle   -"/idle   - -"/' "$T/hub/bin/sessions"
  COLUMNS=100 bash "$ADE" dash --once > "$T/out" 2>&1
  assert_contains "$T/out" "TOKENS" "the column shows when reported"; assert_contains "$T/out" "12.3k" "with the session's usage"
}

# story U1: ade ui beside a JetBrains IDE
tmux_version() {   # AC3: tmux older than 3.2 (no display-popup) stops before anything starts
  fresh; ui_fixture; local v
  for v in 3.1c 3.0a 2.9 1.8; do rm -f "$TMUX_LOG.session"; : > "$TMUX_LOG"
    FAKE_TMUX_V="$v" bash "$ADE" ui > "$T/out" 2>&1; assert_eq "$?" 1 "tmux $v: exit 1"
    assert_contains "$T/out" "ade ui needs tmux 3.2 or newer (found $v)" "names the version found and the one needed"
    if [ "$(uname)" = Darwin ]; then assert_contains "$T/out" "brew upgrade tmux" "how to update it"; else assert_contains "$T/out" "update tmux" "how to update it"; fi
    assert_eq "$(grep -c 'new-session\|attach-session' "$TMUX_LOG")" 0 "tmux $v: nothing starts"
    FAKE_TMUX_V="$v" bash "$ADE" ui --detach > /dev/null 2>&1; assert_eq "$?" 1 "--detach too"
  done
  for v in 3.2 3.2a 3.4 3.10 next-3.6 master; do rm -f "$TMUX_LOG.session"; : > "$TMUX_LOG"
    FAKE_TMUX_V="$v" bash "$ADE" ui > "$T/out" 2>&1 || { cat "$T/out"; fail "tmux $v starts"; }
    grep -q "^tmux attach-session -t =$S" "$TMUX_LOG" || fail "tmux $v: attaches as today"; done
}
ide_safe_keys() {   # AC4: ADE_UI_MOUSE=off, ADE_UI_ARROWS=off (or ~/.config/ade/ui); a JetBrains terminal is told once
  fresh; ui_fixture; local C
  bash "$ADE" ui --detach > "$T/out" 2>&1 || fail "ui"; C="$HOME/.config/ade/ui-$S.tmux.conf"
  grep -qx "set -g mouse on" "$C" || fail "mouse on by default"; grep -qx "bind-key -T prefix Left previous-window" "$C" || fail "Left by default"
  assert_not_contains "$T/out" "ADE_UI_MOUSE" "no hint outside a JetBrains terminal"
  rm -f "$TMUX_LOG.session"; ADE_UI_MOUSE=off bash "$ADE" ui --detach > /dev/null 2>&1
  grep -qx "set -g mouse off" "$C" || fail "ADE_UI_MOUSE=off: mouse off"; grep -qx "bind-key -T prefix Right next-window" "$C" || fail "the arrows stay"
  rm -f "$TMUX_LOG.session"; ADE_UI_ARROWS=off bash "$ADE" ui --detach > /dev/null 2>&1
  grep -qx "set -g mouse on" "$C" || fail "the mouse stays"
  assert_not_contains "$C" "previous-window" "ADE_UI_ARROWS=off: no prefix Left"; assert_not_contains "$C" "next-window" "nor Right"
  assert_not_contains "$C" "prefix 0" "prefix 0-9 are tmux's own, untouched"
  ADE_UI_ARROWS=off bash "$ADE" ui --keys < /dev/null > "$T/out"; assert_contains "$T/out" "prefix 0-9   switch tabs" "the help: 0-9 still switch"; assert_not_contains "$T/out" "Left, Right" "and no arrows"
  mkdir -p "$HOME/.config/ade"; printf 'ADE_UI_MOUSE=off\nADE_UI_ARROWS=off\n' > "$HOME/.config/ade/ui"
  rm -f "$TMUX_LOG.session"; bash "$ADE" ui --detach > /dev/null 2>&1
  grep -qx "set -g mouse off" "$C" || fail "the file: mouse off"; assert_not_contains "$C" "previous-window" "the file: no arrows"
  rm -f "$TMUX_LOG.session"; ADE_UI_MOUSE=on bash "$ADE" ui --detach > /dev/null 2>&1; grep -qx "set -g mouse on" "$C" || fail "the variable wins over the file"
  printf 'ADE_UI_MOUSE=$(touch pwned)\nADE_UI_ARROWS=off; touch pwned\n' > "$HOME/.config/ade/ui"
  rm -f "$TMUX_LOG.session"; (cd "$T" && bash "$ADE" ui --detach > /dev/null 2>&1); [ ! -e "$T/pwned" ] || fail "the file is read, never run"
  grep -qx "set -g mouse on" "$C" || fail "an odd value: as default"
  rm "$HOME/.config/ade/ui"; rm -f "$TMUX_LOG.session"
  TERMINAL_EMULATOR=JetBrains-JediTerm bash "$ADE" ui --detach > "$T/out" 2>&1 || fail "ui in JetBrains"
  assert_contains "$T/out" "ADE_UI_MOUSE=off" "a JetBrains terminal: how to turn the mouse off"; assert_contains "$T/out" "ADE_UI_ARROWS=off" "and the arrows"
  assert_contains "$T/out" "~/.config/ade/ui" "and where to keep them"
  rm -f "$TMUX_LOG.session"; TERMINAL_EMULATOR=JetBrains-JediTerm bash "$ADE" ui --detach > "$T/out" 2>&1
  assert_not_contains "$T/out" "ADE_UI_MOUSE" "said once"
}
u1_docs() {   # AC5
  fresh; local f
  bash "$ADE" help > "$T/help" 2>&1; cp "$REPO/CHANGELOG.md" "$T/changes"   # any section: a release renames Unreleased
  assert_contains "$REPO/README.md" "### Use it beside your IDE" "README section"
  for f in "$REPO/README.md" "$T/help" "$T/changes"; do
    for s in ADE_EDITOR ADE_UI_MOUSE=off ADE_UI_ARROWS=off "tmux 3.2" "{path}"; do assert_contains "$f" "$s" "$(basename "$f"): $s"; done; done
}

# story U5: ade ui with the mouse alone. tq: a tmux command quoted as one tmux argument, as ade quotes it
tq() { local v="${1//\\/\\\\}"; printf '"%s"' "${v//\"/\\\"}"; }
prefix_cmd() { sed -n "s/^bind-key -T prefix $(printf '%s' "$1" | sed 's/[?]/[?]/') //p" "$C"; }   # the command a prefix key runs
ui_conf_made() { fresh; ui_fixture; bash "$ADE" ui --detach > /dev/null 2>&1 || fail "ui"; C="$HOME/.config/ade/ui-$S.tmux.conf"; }
click_buttons() {   # AC1
  ui_conf_made; local k cmd
  assert_contains "$C" "set -g status-left \"#(ADE_HUB=" "the bar is ade's"; assert_contains "$C" "ui --bar $S #{client_width} #{mouse} 1)\"" "it gets the width, the mouse and the ranges (tmux 3.4: yes)"
  bash "$ADE" ui --bar "$S" 120 1 1 > "$T/out"
  assert_contains "$T/out" "rev#[norange]  #[bg=#1e1e2e]#[fg=#89b4fa]#[range=left][+ agent]#[norange] #[range=user|k-t][tickets]#[norange] #[range=user|k-e][files]#[norange] #[range=user|k-a][approve]#[norange] #[range=user|k-f][dash]#[norange] #[range=user|k-?][? keys]#[norange]" "the row of buttons, in order"
  assert_contains "$T/out" "#[range=window|1]" "a tab is a window range: a click goes to it"
  cmd="$(prefix_cmd n)"; [ -n "$cmd" ] || fail "prefix n"
  grep -qxF "bind-key -T root MouseDown1StatusLeft $cmd" "$C" || fail "[+ agent] runs prefix n's command"
  for k in t e a f "?"; do cmd="$(prefix_cmd "$k")"; [ -n "$cmd" ] || fail "prefix $k"
    grep -qxF "    if-shell -F \"#{==:#{mouse_status_range},k-$k}\" { $cmd }" "$C" || { cat "$C"; fail "the $k button runs prefix $k's command"; }; done
  grep -qxF "  } { select-window -t= }" "$C" || fail "a click on a tab still goes to it"
  bash "$ADE" ui --bar "$S" 99 1 1 > "$T/out"; assert_contains "$T/out" "#[range=left][+]#[norange] #[range=right][≡ menu]#[norange]" "under 100 columns: [+] [≡ menu]"
  assert_not_contains "$T/out" "[tickets]" "and no more"
  bash "$ADE" ui --bar "$S" 120 1 0 > "$T/out"; assert_contains "$T/out" "[+]#[norange] #[range=right][≡ menu]" "tmux 3.2 or 3.3 (no user ranges): [+] [≡ menu] at any width"
  assert_not_contains "$T/out" "range=user" "never a range tmux 3.2 cannot draw"
  rm -f "$TMUX_LOG.session"; FAKE_TMUX_V=3.2 bash "$ADE" ui --detach > /dev/null 2>&1; assert_contains "$C" "#{mouse} 0)\"" "tmux 3.2: the bar is told"
  FAKE_WINDOWS='0\torchestrator\t1\n1\tprojects/api:x#[range=left]\t0\n' bash "$ADE" ui --bar "$S" 120 1 1 > "$T/out"
  assert_contains "$T/out" "x##[range=left]" "a # in a tab's name is shown, never drawn as a range"
}
click_menu() {   # AC2
  ui_conf_made; local k cmd m
  m="$(sed -n 's/^bind-key -T root MouseDown1StatusRight //p' "$C")"; [ -n "$m" ] || fail "[≡ menu] is bound"
  case "$m" in "display-menu "*) ;; *) fail "[≡ menu] opens a menu: $m" ;; esac
  for k in MouseDown3StatusLeft MouseDown3StatusRight MouseDown3StatusDefault; do grep -qxF "bind-key -T root $k $m" "$C" || fail "a right click ($k) opens the same menu"; done
  printf '%s\n' "$m" > "$T/m"; assert_contains "$T/m" "prefix" "the title names the prefix"
  bash "$ADE" ui --keys < /dev/null | sed -n 's/^  prefix \([^ 0]\) .*/\1/p' > "$T/keys"; [ "$(wc -l < "$T/keys")" -ge 9 ] || fail "the keys popup lists the actions"
  while IFS= read -r k; do cmd="$(prefix_cmd "$k")"; [ -n "$cmd" ] || fail "prefix $k is bound"
    assert_contains "$T/m" " $(tq "$k") $(tq "$cmd")" "the menu has prefix $k, with its key, running its command"; done < "$T/keys"
}
click_tab_menu() {   # AC3
  ui_conf_made; local m
  sed -n '/^bind-key -T root MouseDown3Status {/,/^}/p' "$C" > "$T/b"; grep -q "display-menu -t= -x W -y W" "$T/b" || { cat "$C"; fail "a right click on a tab: a menu for that tab"; }
  for s in "$(tq "go to it") $(tq g) $(tq "select-window -t #{window_id}")" "$(tq "preview its plan") $(tq p) $(tq "$(prefix_cmd p)")" "$(tq "links in its pane") $(tq l) $(tq "$(prefix_cmd l)")" \
    "$(tq "#{?#{==:#{window_index},0},,close it}") $(tq x) $(tq "confirm-before -p \"close ##{b:window_name}? y/n\" \"kill-window -t #{window_id}\"")"; do
    assert_contains "$T/b" "$s" "tab menu: $s"; done
  assert_not_contains "$T/b" "rename" "rename waits for U2"
  [ "$(grep -o 'kill-window' "$C" | wc -l | tr -d ' ')" = 1 ] || fail "kill-window only behind the y/n"
  ! grep -E 'run-shell[^"]*"[^"]*window_name' "$C" > /dev/null || fail "a tab's name never goes into a shell string"
  ! grep -E 'window_name[^ ]*\\" \\"kill|kill-window -t #\{window_name' "$C" > /dev/null || fail "a tab is a target by id, never by name"
}
click_scroll_select() {   # AC4
  ui_conf_made; local want=xclip c
  for c in pbcopy xclip; do printf '#!/bin/bash\ncat > /dev/null\n' > "$T/fakebin/$c"; chmod +x "$T/fakebin/$c"; done
  rm -f "$TMUX_LOG.session"; bash "$ADE" ui --detach > /dev/null 2>&1 || fail ui
  [ "$(uname)" = Darwin ] && want=pbcopy; [ "$want" = xclip ] && want="xclip -selection clipboard"
  grep -qxF "set -s copy-command \"$want\"" "$C" || { grep copy "$C"; fail "a drag copies to the system clipboard ($want)"; }
  for t in copy-mode copy-mode-vi; do grep -qxF "bind-key -T $t MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel" "$C" || fail "$t: the drag's end copies"; done
  grep -qxF "bind-key -T copy-mode-vi Escape send-keys -X cancel" "$C" || fail "Esc leaves scrolling (vi keys too)"
  sed -n '/^bind-key -T root WheelUpPane/,/^}/p' "$C" > "$T/w"
  assert_contains "$T/w" "bind-key -T root WheelUpPane if-shell -F \"#{||:#{pane_in_mode},#{mouse_any_flag}}\" { send-keys -M } {" "the wheel: the app's own, else history"
  assert_contains "$T/w" "copy-mode -e" "the wheel scrolls the pane's history, no prefix"
  assert_contains "$T/w" "if-shell -F \"#{?@ade-scrolled,0,1}\" {" "once a session"
  assert_contains "$T/w" "set-option @ade-scrolled 1" "it is noted"; assert_contains "$T/w" "display-message \"scrolling: q or Esc to return\"" "the one line"
}
click_off() {   # AC5
  fresh; ui_fixture; ADE_UI_MOUSE=off bash "$ADE" ui --detach > /dev/null 2>&1; C="$HOME/.config/ade/ui-$S.tmux.conf"
  grep -qx "set -g mouse off" "$C" || fail "mouse off"; assert_not_contains "$C" "status-format[1]" "no first-run line either"
  for m in 0 off; do bash "$ADE" ui --bar "$S" 120 "$m" 1 > "$T/out"
    for s in "[+" "[≡" "[tickets]" "range=left" "range=right" "range=user"; do assert_not_contains "$T/out" "$s" "mouse $m: no $s"; done
    assert_contains "$T/out" "○ 2 ops/db" "the tabs stay"; done
  ADE_UI_MOUSE=off bash "$ADE" ui --bar "$S" > "$T/out"; assert_not_contains "$T/out" "[+" "no mouse word given: ADE_UI_MOUSE decides"
}
click_first_run() {   # AC6
  fresh; ui_fixture; local i H="$HOME/.config/ade/hints" line="Click a tab or a button; right click for every action. Keys: ? keys"
  for i in 1 2 3; do rm -f "$TMUX_LOG.session"; bash "$ADE" ui --detach > /dev/null 2>&1; C="$HOME/.config/ade/ui-$S.tmux.conf"
    grep -qx "set -g status 2" "$C" || fail "session $i: a second line"; assert_contains "$C" "$line" "session $i: the hint, under the bar"; done
  bash "$ADE" ui --detach > /dev/null 2>&1; assert_eq "$(grep -cx ui-click "$H")" 3 "a running session is not a new one"
  rm -f "$TMUX_LOG.session"; bash "$ADE" ui --detach > /dev/null 2>&1
  grep -qx "set -g status on" "$C" || fail "after 3 sessions: one line"; assert_not_contains "$C" "$line" "and no hint"
  fresh; ui_fixture; bash "$ADE" ui --detach > /dev/null 2>&1; C="$HOME/.config/ade/ui-$S.tmux.conf"
  grep -q "^bind-key -T root MouseDown1StatusDefault if-shell -F \"#{==:#{status},2}\" { set-option -g status on ; run-shell -b \".* ui --hint-off\" }$" "$C" || fail "a click on the line hides it (only while it shows)"
  bash "$ADE" ui --hint-off > /dev/null 2>&1 || fail "hint-off"; rm -f "$TMUX_LOG.session"; bash "$ADE" ui --detach > /dev/null 2>&1
  assert_not_contains "$C" "$line" "dismissed: never again"; grep -qx ui-click-off "$HOME/.config/ade/hints" || fail "remembered in hints"
}
click_real_tmux() {   # the config ade ui writes loads on a real tmux (a private socket), with the mouse bindings in it
  command -v tmux > /dev/null 2>&1 || { echo "skip: no tmux"; return 0; }
  fresh; make_hub "$T/hub" hub; printf 'HUB_NAME=real\n' > "$T/hub/hub.conf"; export ADE_HUB="$T/hub" TMUX_TMPDIR="$T" ADE_TMUX_SOCKET="ade-test-$$"; unset TMUX
  mkdir -p "$T/fakebin"; printf '#!/bin/bash\nsleep 30\n' > "$T/fakebin/claude"; chmod +x "$T/fakebin/claude"; export PATH="$T/fakebin:$PATH"
  bash "$ADE" ui --detach > "$T/out" 2>&1 || { cat "$T/out"; tmux -L "$ADE_TMUX_SOCKET" kill-server 2> /dev/null; fail "real ui"; }
  tmux -L "$ADE_TMUX_SOCKET" list-keys -T root > "$T/keys" 2>&1; tmux -L "$ADE_TMUX_SOCKET" show-options -g status-format > "$T/opts" 2>&1
  tmux -L "$ADE_TMUX_SOCKET" kill-server 2> /dev/null
  for k in MouseDown1StatusLeft MouseDown1StatusRight MouseDown1Status MouseDown3Status MouseDown3StatusLeft MouseDown1StatusDefault WheelUpPane; do
    assert_contains "$T/keys" " $k " "real tmux: $k bound"; done
  assert_contains "$T/keys" "close #" "the close asks first"; assert_contains "$T/opts" "Click a tab or a button" "the first-run line"
}
u5_docs() {   # AC7
  fresh; local f
  bash "$ADE" help > "$T/help" 2>&1; cp "$REPO/CHANGELOG.md" "$T/changes"   # any section: a release renames Unreleased
  assert_contains "$REPO/README.md" "### Use it with the mouse" "README section"
  for f in "$REPO/README.md" "$T/help" "$T/changes"; do
    for s in "[≡ menu]" "right click" "ADE_UI_MOUSE=off"; do assert_contains "$f" "$s" "$(basename "$f"): $s"; done; done
}

ALL="click_buttons click_menu click_tab_menu click_scroll_select click_off click_first_run click_real_tmux u5_docs tmux_version ide_safe_keys u1_docs dash_tokens_and_events session_names menu_skips_bad_folders sq_refuses bar_cached creates_then_attaches work_opens_tab work_makes_the_session work_plain claude_in_the_session bare_ade_opens_the_tabs bare_no_agents work_real_tmux tab_bar dash_golden key_table approve_popup unread_marks no_tmux_no_glow real_tmux"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
