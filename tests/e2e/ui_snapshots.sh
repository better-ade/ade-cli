#!/bin/bash
# story A8 layer 7: real tmux at 120x36 and 80x24. An outer tmux shows a client attached to ade ui, so capture-pane
# sees the whole screen (tab bar included). Snapshots of the tab bar, the fleet sidebar and each popup are compared
# with tests/golden/ui-<W>x<H>-<view>.txt; UPDATE_GOLDEN=1 rewrites them. Captures land in $UI_CAPTURES (CI artifact).
. "$(dirname "$0")/lib.sh"
command -v tmux > /dev/null || { echo "no tmux here: skipped"; exit 0; }
OUT="${UI_CAPTURES:-$W/captures}"; mkdir -p "$OUT"; G="$REPO/tests/golden"; rc=0
H="$W/hub"; mkdir -p "$H/bin" "$H/projects/api" "$H/projects/web" "$H/ops/db"; : > "$H/bin/lib.sh"; echo "HUB_NAME=snap" > "$H/hub.conf"
printf '# Plan for the hub\n- step one\n- step two\n' > "$H/PLAN.md"
cat > "$H/bin/sessions" <<'S'
#!/bin/bash
echo "NAME             FOLDER                     PID      PARENT   STARTED               ROLE       STATUS LAST"
echo "1.2              projects/api               123      -        2026-11-21T10:00:00Z  builder    busy   2026-11-21T10:30:00Z"
echo "db               ops/db                     124      -        2026-11-21T08:00:00Z  -          idle   -"
S
printf '#!/bin/bash\n[ "$1" = --count ] && { [ "$2" = 1.2 ] && echo 2 || echo 0; }\n' > "$H/bin/inbox"
printf '#!/bin/bash\n[ "$1" = --list ] && printf "ready\\t1.3\\tprojects/api\\nwaiting\\t2.1\\tprojects/api\\n"\n' > "$H/bin/dispatch"
printf '#!/bin/bash\nprintf "routine    anthropic:sonnet\\nbuilder    anthropic:opus\\n"\n' > "$H/bin/roles"
chmod +x "$H/bin/"*; export AGENT_STATE="$W/state"; mkdir -p "$AGENT_STATE"
for i in 1 2 3; do printf '{"time": "2026-11-21T10:0%s:00Z", "from": "projects/api", "to": "all", "kind": "pushed", "text": "event %s"}\n' "$i" "$i"; done > "$AGENT_STATE/events.jsonl"
bash "$REPO/install.sh" "$W/prefix" > /dev/null || fail "install"; export PATH="$W/prefix/bin:$PATH"
fake_claude; export ADE_HUB="$H" ADE_NOW="2026-11-21T10:45:00Z" TMUX_TMPDIR="$W" ADE_TMUX_SOCKET=snap LANG=C.UTF-8 LC_ALL=C.UTF-8
o() { tmux -L outer "$@"; }
shot() {   # shot <name> <text to wait for>: capture the outer screen once the text shows, then compare
  local f="$OUT/ui-$SIZE-$1.txt" _
  for _ in $(seq 1 40); do o capture-pane -p -t o | sed 's/[[:space:]]*$//' > "$f"; grep -qF -- "$2" "$f" && break; sleep 0.25; done
  grep -qF -- "$2" "$f" || { echo "never saw [$2] in $1:"; cat "$f"; rc=1; return; }
  if [ "${UPDATE_GOLDEN:-}" = 1 ]; then cp "$f" "$G/ui-$SIZE-$1.txt"; echo "golden ui-$SIZE-$1 updated"
  elif ! diff -u "$G/ui-$SIZE-$1.txt" "$f"; then echo "ui-$SIZE-$1 differs from its golden file"; rc=1; fi
}
key() { o send-keys -t o C-b "$@"; }
for SIZE in 120x36 80x24; do
  step "ade ui at $SIZE"
  ade ui --detach > /dev/null || fail "ade ui --detach"
  o -f /dev/null new-session -d -s o -x "${SIZE%x*}" -y "${SIZE#*x}" "env TMUX= tmux -L snap attach-session -t =$(ade ui --session)"
  o set -g prefix C-q; o unbind-key C-b; o set -g status off
  shot bar "[+ new]"
  key f; shot sidebar "EVENTS"; key f; sleep 0.5
  key "?"; shot help "prefix ?"; o send-keys -t o Enter; sleep 0.5
  key t; shot tickets "waiting"; o send-keys -t o Enter; sleep 0.5
  key n; shot menu-new "New agent"; o send-keys -t o q; sleep 0.5
  key a; shot menu-approve "Approve a ticket"; o send-keys -t o q; sleep 0.5
  key p; shot preview "step two"; o send-keys -t o Enter; sleep 0.5
  o kill-server; tmux -L snap kill-server; sleep 0.5
done
[ "$rc" = 0 ] && echo && echo "e2e ui snapshots: ok"; exit "$rc"
