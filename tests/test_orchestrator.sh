#!/bin/bash
# story A2: `ade orchestrator`. Fake hubs whose bin/chat logs each call; never the network.
. "$(dirname "$0")/helpers.sh"

# chat_hub <dir> <name>: a hub whose bin/chat logs "<hub name> <args> HUB=<HUB>" to $CHAT_LOG and keeps its state in the hub
chat_hub() {
  make_hub "$1" "$2"; export CHAT_LOG="$T/chat.log"; touch "$CHAT_LOG"
  printf 'HUB_NAME=%s\nHUB_CHANNELS="telegram"\n' "$2" > "$1/hub.conf"
  cat > "$1/bin/chat" <<STUB
#!/bin/bash
echo "$2 \$* HUB=\$HUB" >> "\$CHAT_LOG"
case "\$1" in
  setup) [ "\$2" = telegram ] || { echo "chat: unknown channel \$2 (known: telegram)" >&2; exit 2; } ;;
  start) date > "\$HUB/.running" ;;
  stop) rm -f "\$HUB/.running" ;;
  status) if [ -f "\$HUB/.running" ]; then echo "running since 2026-11-21T10:00Z policy allowlist"; else echo stopped; fi ;;
  logs) [ "\$2" = -n ] && tail -n "\$3" "\$HUB/chat.log" ;;
esac
STUB
  chmod +x "$1/bin/chat"; seq 1 30 | sed 's/^/line /' > "$1/chat.log"
}
REG() { echo "$HOME/.config/ade/orchestrators"; }

new_registers_and_sets_up() {   # AC1
  fresh; chat_hub "$T/a" a; chat_hub "$T/b" b
  bash "$ADE" orchestrator new acme --hub "$T/a" --channel telegram > "$T/out" 2>&1 || { cat "$T/out"; fail "new exit"; }
  assert_eq "$(cat "$(REG)")" "acme	$T/a" "registered name and hub"
  assert_contains "$CHAT_LOG" "a setup telegram HUB=$T/a" "setup ran in that hub"
  for bad in Acme "a b" "x_y" "" "-x" "-" "a
b"; do
    bash "$ADE" orchestrator new "$(printf -- "$bad")" --hub "$T/b" > "$T/out" 2>&1; assert_eq "$?" 2 "bad name [$bad]"; done
  bash "$ADE" orchestrator new acme --hub "$T/b" > "$T/out" 2>&1; assert_eq "$?" 2 "duplicate name"
  assert_contains "$T/out" "acme" "names the duplicate"
  bash "$ADE" orchestrator new other --hub "$T/a" > "$T/out" 2>&1; assert_eq "$?" 2 "second orchestrator for a hub"
  bash "$ADE" orchestrator new other --hub "$T/nothub" > "$T/out" 2>&1; assert_eq "$?" 2 "not a hub"
  assert_eq "$(wc -l < "$(REG)" | tr -d ' ')" 1 "refusals register nothing"
}

start_stop_right_hub() {   # AC2
  fresh; chat_hub "$T/a" a; chat_hub "$T/b" b
  bash "$ADE" orchestrator new one --hub "$T/a" > /dev/null 2>&1 && bash "$ADE" orchestrator new two --hub "$T/b" > /dev/null 2>&1 || fail "new"
  (cd "$T/a" && HUB=/stale bash "$ADE" orchestrator start two) > "$T/out" 2>&1 || { cat "$T/out"; fail "start exit"; }
  assert_contains "$CHAT_LOG" "b start HUB=$T/b" "start in hub b with HUB exported"
  assert_not_contains "$CHAT_LOG" "a start" "hub a not started"
  bash "$ADE" orchestrator stop two > /dev/null 2>&1 || fail "stop exit"
  assert_contains "$CHAT_LOG" "b stop HUB=$T/b" "stop in hub b"
  bash "$ADE" orchestrator start nosuch > "$T/out" 2>&1; assert_eq "$?" 2 "unknown name"
}

list_shows_status() {   # AC3
  fresh; chat_hub "$T/a" a; chat_hub "$T/b" b; chat_hub "$T/c" c
  for p in "one a" "two b" "three c"; do set -- $p; bash "$ADE" orchestrator new "$1" --hub "$T/$2" > /dev/null 2>&1 || fail "new $1"; done
  bash "$ADE" orchestrator start one > /dev/null 2>&1; rm -rf "$T/c"
  bash "$ADE" orchestrator list > "$T/out" 2>&1 || { cat "$T/out"; fail "list exit"; }
  grep -E "^one +running +telegram +2026-11-21T10:00Z +$T/a$" "$T/out" > /dev/null || { cat "$T/out"; fail "one running since"; }
  grep -E "^two +stopped +telegram +- +$T/b$" "$T/out" > /dev/null || { cat "$T/out"; fail "two stopped"; }
  grep -E "^three +missing +- +- +$T/c$" "$T/out" > /dev/null || { cat "$T/out"; fail "three missing"; }
}

logs_last_lines() {   # AC4
  fresh; chat_hub "$T/a" a; bash "$ADE" orchestrator new one --hub "$T/a" > /dev/null 2>&1 || fail "new"
  out=$(bash "$ADE" orchestrator logs one -n 3); assert_eq "$out" "line 28
line 29
line 30" "last 3 lines, nothing added"
  assert_contains "$CHAT_LOG" "a logs -n 3 HUB=$T/a" "the hub's bin/chat logs"
  out=$(bash "$ADE" orchestrator logs one | wc -l | tr -d ' '); assert_eq "$out" 30 "default is 50 lines (all 30 here)"
  bash "$ADE" orchestrator logs one -n x > /dev/null 2>&1; assert_eq "$?" 2 "bad -n"
}

remove_stops_first() {   # AC5
  fresh; chat_hub "$T/a" a; chat_hub "$T/b" b
  bash "$ADE" orchestrator new one --hub "$T/a" > /dev/null 2>&1 && bash "$ADE" orchestrator new two --hub "$T/b" > /dev/null 2>&1 || fail "new"
  bash "$ADE" orchestrator start one > /dev/null 2>&1
  before=$(cd "$T/a" && ls -A | sort)
  bash "$ADE" orchestrator remove one > "$T/out" 2>&1 || { cat "$T/out"; fail "remove exit"; }
  assert_contains "$CHAT_LOG" "a stop HUB=$T/a" "stopped first"
  assert_eq "$(cat "$(REG)")" "two	$T/b" "only its line dropped"
  [ -f "$T/a/hub.conf" ] && [ -x "$T/a/bin/chat" ] || fail "hub files untouched"
  bash "$ADE" orchestrator remove two > /dev/null 2>&1 || fail "remove stopped one"
  assert_eq "$(grep -c 'b stop' "$CHAT_LOG")" 0 "a stopped orchestrator is not stopped again"
}

registry_modes() {   # AC6
  fresh; chat_hub "$T/a" a; bash "$ADE" orchestrator new one --hub "$T/a" > /dev/null 2>&1 || fail "new"
  mode() { if stat -c %a "$1" > /dev/null 2>&1; then stat -c %a "$1"; else stat -f %Lp "$1"; fi; }
  assert_eq "$(mode "$(REG)")" 600 "file 0600"; assert_eq "$(mode "$HOME/.config/ade")" 700 "folder 0700"
}

unknown_channel_passthrough() {   # AC7
  fresh; chat_hub "$T/a" a
  bash "$ADE" orchestrator new one --hub "$T/a" --channel discord > "$T/out" 2>&1; assert_eq "$?" 2 "hub's exit returned"
  assert_contains "$T/out" "chat: unknown channel discord (known: telegram)" "hub's refusal shown"
  assert_contains "$CHAT_LOG" "a setup discord" "passed through"
  [ ! -s "$(REG)" ] || fail "nothing registered after a refusal"
}

ALL="new_registers_and_sets_up start_stop_right_hub list_shows_status logs_last_lines remove_stops_first registry_modes unknown_channel_passthrough"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
