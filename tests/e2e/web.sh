#!/bin/bash
# story C3: check-ins (ade-brain story S1) and ade web (stories M1, M2) end to end, on a hub made from the real ade-brain
# template. A focus session started by the hub's own bin/work runs a stand-in for Claude (no real Claude, no secret)
# that fires the folder's real hooks, read from its .claude/settings.json, from inside the session. Time is faked
# (a date that runs ahead, for the hook and bin/monitor only) rather than waited for. ade web runs under a pty, as at a
# terminal, and is read over HTTP as the page does. No network after the template clone.

# As root on Linux (the e2e-linux container) the hub's bin/work refuses to run (ade-brain story V1: a hub runs as a
# normal user), so the test runs again as a throwaway user with its own copy of the checkout (lib.sh's REPO is that
# copy), then both are removed. E2E_AS_USER_DRY=1 prints those steps instead of running them (no root needed).
if { [ "$(uname -s)" = Linux ] && [ "$(id -u)" = 0 ]; } || [ -n "${E2E_AS_USER_DRY:-}" ]; then
  u=ade-e2e-web; d="/home/$u/ade-cli"; src="$(cd "$(dirname "$0")/../.." && pwd)"
  as() { if [ -n "${E2E_AS_USER_DRY:-}" ]; then printf '%q ' "$@"; echo; else "$@"; fi; }
  as useradd -m -s /bin/bash "$u" || exit 1
  as cp -a "$src" "$d" && as chown -R "$u:$u" "$d" || { as userdel -r "$u"; exit 1; }
  as runuser -u "$u" -- env -i HOME="/home/$u" PATH="$PATH" LANG=C.UTF-8 ${TERM:+TERM="$TERM"} bash "$d/tests/e2e/web.sh"; rc=$?
  as userdel -r "$u" 2> /dev/null
  exit "$rc"
fi
. "$(dirname "$0")/lib.sh"
export ADE_NO_UPDATE_CHECK=1; unset AGENT_STATE HUB_CHECKIN_MINUTES ADE_WEB_PORT
step "install from this checkout"; bash "$REPO/install.sh" "$W/prefix" > /dev/null || fail "install"
export PATH="$W/prefix/bin:$PATH"; fake_claude
step "ade hub new --no-github (real ade-brain template)"
ade hub new e2e --no-github --dir "$W/hubs" --persona devops-sre --client Example --owner owner1 < /dev/null > "$W/new.log" 2>&1 || { cat "$W/new.log"; fail "hub new"; }
H="$W/hubs/e2e"; F=ops/monitoring; FD="$H/$F"; ST="$HOME/.agent-hub/e2e"; LOG="$ST/events.jsonl"; cd "$W" || exit 1
[ -x "$H/bin/checkin" ] && [ -f "$FD/.claude/settings.json" ] || fail "the hub has bin/checkin and $F's hooks (ade-brain story S1)"
# this machine's value (.local/hub.conf, never committed): a check-in every minute
mkdir -p "$H/.local" && echo "HUB_CHECKIN_MINUTES=1" >> "$H/.local/hub.conf" || fail ".local/hub.conf"

# the clock: a date that runs E2E_SKEW seconds ahead for `date +%s` (the now of bin/inbox, bin/notify and bin/checkin),
# else the real one. SKEW only grows (advance <seconds>): every hook call and bin/monitor run sees one clock
REAL_DATE="$(command -v date)"; mkdir -p "$W/clock"
printf '#!/bin/bash\nif [ "$*" = "+%%s" ]; then echo $(( $(%s +%%s) + ${E2E_SKEW:-0} )); else exec %s "$@"; fi\n' "$REAL_DATE" "$REAL_DATE" > "$W/clock/date"
chmod +x "$W/clock/date"

# the stand-in for Claude in a focus session: it runs each request ($W/sess/req.<n>, a bash script) from inside the
# session (bin/work's launcher is its parent), its output in out.<n>, its exit in rc.<n>. hookrun <event> <json> in a
# request runs every command the folder's settings.json has for that event, as Claude does: sh -c, the JSON on stdin.
mkdir -p "$W/sess" "$W/fakebin"
cat > "$W/hookrun" <<'HR'
#!/bin/bash
python3 -I -c 'import json, sys
for g in json.load(open(sys.argv[1]))["hooks"].get(sys.argv[2], []):
    for h in g["hooks"]: print(h["command"])' "$FD/.claude/settings.json" "$1" | while IFS= read -r c; do
  printf '%s' "$2" | CLAUDE_PROJECT_DIR="$FD" sh -c "$c"; done
HR
chmod +x "$W/hookrun"
cat > "$W/fakebin/claude-focus" <<'C'
#!/bin/bash
D="$E2E_W/sess"; n=0; echo $$ >> "$E2E_W/pids"
while :; do
  n=$((n + 1)); until [ -f "$D/req.$n" ]; do sleep 0.05; done
  bash "$D/req.$n" > "$D/out.$n" 2>&1; echo $? > "$D/rc.$n.tmp"; mv "$D/rc.$n.tmp" "$D/rc.$n"
done
C
chmod +x "$W/fakebin/claude-focus"
SKEW=0; advance() { SKEW=$((SKEW + $1)); }
clock() { E2E_SKEW="$SKEW" "$W/clock/date" +%s; }
N=0
# sess <bash>: run it inside the focus session; its output in OUT, its exit is sess's (never in a subshell: N counts)
sess() {
  N=$((N + 1)); printf 'export FD=%q PATH=%q E2E_SKEW=%s\n%s\n' "$FD" "$W/clock:$PATH" "$SKEW" "$1" > "$W/sess/req.tmp"; mv "$W/sess/req.tmp" "$W/sess/req.$N"
  local i=0; until [ -f "$W/sess/rc.$N" ]; do i=$((i + 1)); [ "$i" -lt 600 ] || fail "the focus session did not answer in 30 s: $1"; sleep 0.05; done
  OUT="$(cat "$W/sess/out.$N")"; return "$(cat "$W/sess/rc.$N")"
}
# tool: one tool call's PostToolUse hooks
tool() { sess "\"$W/hookrun\" PostToolUse '{\"session_id\":\"focus-1\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}'"; }
nudge_text="hub check-in, from the hub's PostToolUse hook"
nudged() { case "$OUT" in *"$nudge_text"*) return 0 ;; esac; return 1; }
quiets() { grep -c '"kind": *"quiet"' "$LOG" 2> /dev/null; }

step "a busy focus session: bin/work's launcher, the folder's SessionStart and UserPromptSubmit hooks"
# no start watcher (HUB_WORK_START_WAIT=0: this session starts at once); the launcher and its files under $W
mkdir -p "$W/tmp"; L="$(cd "$H" && TMPDIR="$W/tmp" HUB_WORK_START_WAIT=0 WORK_NO_OPEN=1 bin/work --force --claude claude-focus "$F" 2> "$W/work.err" | sed -n 's/^launcher: //p')"
[ -n "$L" ] && [ -f "$L" ] || { cat "$W/work.err"; fail "bin/work wrote no launcher"; }
( bash "$L" > "$W/launcher.out" 2>&1 & echo $! >> "$W/pids" )   # in a subshell: not a job of this shell
sess "\"$W/hookrun\" SessionStart '{\"session_id\":\"focus-1\",\"source\":\"startup\"}'" || fail "SessionStart hooks"
sess "\"$W/hookrun\" UserPromptSubmit '{\"session_id\":\"focus-1\",\"prompt\":\"check the monitors\"}'" || fail "UserPromptSubmit hooks"
(cd "$H" && bin/sessions) > "$W/sessions" || fail "bin/sessions"
grep -Eq "^monitoring +$F .* busy " "$W/sessions" || { cat "$W/sessions"; fail "bin/sessions lists $F busy"; }

step "e2e_checkin_nudge: HUB_CHECKIN_MINUTES=1, the PostToolUse hook nudges once the minute is up, not before"
tool; ! nudged || fail "nudged on the first call: $OUT"
advance 30; tool; ! nudged || fail "nudged 30 s into the period: $OUT"
advance 35; tool
printf '%s' "$OUT" | python3 -c 'import json, sys
d = json.load(sys.stdin)["hookSpecificOutput"]; assert d["hookEventName"] == "PostToolUse", d; t = d["additionalContext"]
for w in (sys.argv[1], sys.argv[2] + "/STATE.md", sys.argv[3] + "/bin/notify main"): assert w in t, (w, t)' "$nudge_text" "$FD" "$H" \
  || fail "no check-in instruction 65 s into the period: $OUT"
echo "nudged at +65 s: $(printf '%s' "$OUT" | cut -c1-150)..."
advance 5; tool; ! nudged || fail "nudged twice in one period"

step "e2e_checkin_resets: bin/notify to main from the session is its check-in; the next tool call is not nudged"
sess "\"$H/bin/notify\" main 'monitoring: checks green; next: alert rules'" || fail "bin/notify from the session"
tail -1 "$LOG" | python3 -c 'import json, sys
e = json.load(sys.stdin); assert e["kind"] == "note" and e["from"] == "ops/monitoring" and e["to"] == "main" and e.get("checkin") is True, e' \
  || fail "the note is not a check-in: $(tail -1 "$LOG")"
CHECKIN_AT="$(tail -1 "$LOG" | python3 -c 'import json, sys, calendar, time; print(calendar.timegm(time.strptime(json.load(sys.stdin)["time"], "%Y-%m-%dT%H:%M:%SZ")))')"
read -r s < "$ST/checkin/ops-monitoring.start"; [ $(( $(clock) - s )) -lt 10 ] || fail "the check-in did not restart the period"
tool; ! nudged || fail "nudged right after the check-in: $OUT"
[ "$(grep -c '"checkin": *true' "$LOG")" = 1 ] || fail "one check-in in the log"

step "e2e_quiet_reaches_main: nudged, no check-in: bin/monitor writes one quiet event to main, once"
advance 40; tool; advance 40; tool; nudged || fail "no nudge a minute after the check-in: $OUT"
q0="$(quiets)"; sleep 1   # the quiet event's second is after the turn's start (ade web: a quiet newer than LAST)
advance 660   # ten minutes after the nudge
(cd "$H" && PATH="$W/clock:$PATH" E2E_SKEW="$SKEW" MONITOR_QUIET=1 bin/monitor) > "$W/monitor.out" 2>&1 || { cat "$W/monitor.out"; fail "bin/monitor"; }
[ "$(quiets)" = $((q0 + 1)) ] || fail "bin/monitor wrote $(( $(quiets) - q0 )) quiet events, not 1"
grep '"kind": *"quiet"' "$LOG" | tail -1 | python3 -c 'import json, sys
e = json.load(sys.stdin); assert e["from"] == "ops/monitoring" and e["to"] == "main" and e["text"].startswith("quiet ") and "nudge" in e["text"], e' \
  || fail "the quiet event: $(grep quiet "$LOG" | tail -1)"
grep '"kind": *"quiet"' "$LOG" | tail -1
advance 60; (cd "$H" && PATH="$W/clock:$PATH" E2E_SKEW="$SKEW" MONITOR_QUIET=1 bin/monitor) > "$W/monitor.out" 2>&1 || fail "bin/monitor again"
[ "$(quiets)" = $((q0 + 1)) ] || fail "a second quiet event for the same nudge"

# ade web under a pty (test_web.sh's harness): its stdout and stderr go to files, its terminal to $W/tty.out
cat > "$W/tty.py" <<'PY'
import fcntl, os, select, signal, subprocess, sys, termios, time
d = sys.argv[1]; m, s = os.openpty()
def ctty(): fcntl.ioctl(s, termios.TIOCSCTTY, 0)
p = subprocess.Popen(sys.argv[2:], stdin=subprocess.DEVNULL, start_new_session=True, preexec_fn=ctty)
for n in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT): signal.signal(n, lambda n, f: p.send_signal(n))
out = open(os.path.join(d, "tty.out"), "ab", buffering=0)
def pump():
    try: b = os.read(m, 4096) if select.select([m], [], [], 0.05)[0] else b""
    except OSError: b = b""; time.sleep(0.05)
    if b: out.write(b)
while p.poll() is None: pump()
pump()
sys.exit(p.returncode if p.returncode >= 0 else 128 - p.returncode)
PY
free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
refused() { ! python3 -c 'import socket, sys; socket.create_connection(("127.0.0.1", int(sys.argv[1])), 2).close()' "$1" 2> /dev/null; }
# get <path> [curl args]: CODE, the body in $W/body, the headers in $W/head
get() { local p="$1"; shift; CODE="$(curl -q -s --max-time 10 -o "$W/body" -D "$W/head" -w '%{http_code}' "$@" "$BASE$p")" || fail "no answer for $p"; }
api() { local p="$1"; shift; get "$p" -H "Cookie: $CK" -H "X-Ade-Key: $K" "$@"; }
json() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"d": d}))' "$W/body" "$1"; }

step "e2e_web_code: ade web --no-open: the link on stdout, the code on the terminal only; 401 until POST /login"
git -C "$H" status --porcelain > "$W/git.before"; git -C "$H" rev-parse HEAD >> "$W/git.before"
: > "$W/tty.out"; : > "$W/web.out"; ADE_WEB_PORT="$(free_port)" python3 -I "$W/tty.py" "$W" ade web --no-open > "$W/web.out" 2> "$W/web.err" & SRV=$!
echo "$SRV" >> "$W/pids"; i=0
until grep -q '^ade web: http://' "$W/web.out"; do
  kill -0 "$SRV" 2> /dev/null || { cat "$W/web.err"; fail "ade web ended before it printed its address"; }
  i=$((i + 1)); [ "$i" -lt 100 ] || fail "ade web printed no address in 10 s"; sleep 0.1; done
URL="$(sed -n 's/^ade web: \(http:.*\)$/\1/p' "$W/web.out" | head -1)"; K="${URL##*\?k=}"; BASE="${URL%%/\?k=*}"; PORT="${BASE##*:}"
case "$BASE" in http://127.0.0.1:*) ;; *) fail "not a loopback link: $URL" ;; esac
[ "${#K}" -ge 32 ] || fail "a short token in the link"
i=0; until CODE_TTY="$(tr -d '\r' < "$W/tty.out" | sed -n 's/.*ade web: the code for the page: \([A-Za-z0-9]*\).*/\1/p' | tail -1)"; [ -n "$CODE_TTY" ]; do
  i=$((i + 1)); [ "$i" -lt 100 ] || { cat "$W/tty.out"; fail "no code on ade web's terminal in 10 s"; }; sleep 0.1; done
if grep -qF -- "$CODE_TTY" "$W/web.out" "$W/web.err"; then fail "the code is on stdout or stderr, not only the terminal"; fi
echo "link on stdout: http://127.0.0.1:$PORT/?k=<token>; a ${#CODE_TTY}-character code on the terminal only"
get "/?k=$K"; [ "$CODE" = 200 ] || fail "the link: $CODE"
get "/api/agents" -H "X-Ade-Key: $K"; [ "$CODE" = 401 ] || fail "/api/agents before the code: $CODE, not 401"
get "/login" -X POST -H "Origin: $BASE" -H "X-Ade-Key: $K" -H "Content-Type: application/json" --data-binary '{"code": "wrong0"}'
[ "$CODE" != 200 ] || fail "a wrong code was taken"
get "/api/agents" -H "X-Ade-Key: $K"; [ "$CODE" = 401 ] || fail "/api/agents after a wrong code: $CODE, not 401"
get "/login" -X POST -H "Origin: $BASE" -H "X-Ade-Key: $K" -H "Content-Type: application/json" --data-binary "{\"code\": \"$CODE_TTY\"}"
[ "$CODE" = 200 ] || fail "POST /login with the terminal's code: $CODE"
CK="$(tr -d '\r' < "$W/head" | sed -n 's/^[Ss]et-[Cc]ookie: \([^;]*\);.*/\1/p' | head -1)"
case "$CK" in "ade_web_$PORT="?*) ;; *) fail "the session cookie: $CK" ;; esac
api "/api/agents"; [ "$CODE" = 200 ] || fail "/api/agents after the code: $CODE, not 200"
echo "/api/agents: 401 before the code, 200 after"

step "e2e_web_shows_quiet: /api/agents lists $F, quiet, with its last check-in; /api/events has the quiet event"
json '[(a["name"], a["folder"], a["state"]) for a in d["agents"]]'
[ "$(json '[a["state"] for a in d["agents"] if a["folder"] == "ops/monitoring"]')" = "['quiet']" ] || fail "$F is not listed as quiet"
[ "$(json '[a["checkin"] for a in d["agents"] if a["folder"] == "ops/monitoring"]')" = "[$CHECKIN_AT]" ] || fail "$F's last check-in is not $CHECKIN_AT"
json '[a["text"] for a in d["alerts"] if a["kind"] == "quiet"]'
[ "$(json '[a["agent"] for a in d["alerts"] if a["kind"] == "quiet"]')" = "['monitoring']" ] || fail "no quiet alert for monitoring"
api "/api/events"; [ "$CODE" = 200 ] || fail "/api/events: $CODE"
[ "$(json '[e["from"] for e in d["events"] if e["kind"] == "quiet"]')" = "['ops/monitoring']" ] || fail "/api/events has no quiet event from $F"
[ "$(json '[e["text"] for e in d["events"] if e.get("checkin")]')" = "['monitoring: checks green; next: alert rules']" ] || fail "/api/events: the check-in"

step "e2e_web_stop: ade web --stop ends it; the port is closed and the hub's git status is as before"
ade web --stop > "$W/stop.out" 2>&1 || { cat "$W/stop.out"; fail "ade web --stop"; }
grep -q stopped "$W/stop.out" || fail "--stop does not say it stopped: $(cat "$W/stop.out")"
# $SRV is the pty harness: it ends a moment after the server (commit e88fdca)
i=0; while kill -0 "$SRV" 2> /dev/null; do i=$((i + 1)); [ "$i" -lt 50 ] || fail "ade web still runs 5 s after --stop"; sleep 0.1; done
wait "$SRV" 2> /dev/null
refused "$PORT" || fail "port $PORT still answers"
git -C "$H" status --porcelain > "$W/git.after"; git -C "$H" rev-parse HEAD >> "$W/git.after"
cmp -s "$W/git.before" "$W/git.after" || { diff "$W/git.before" "$W/git.after"; fail "ade web changed the hub's git status"; }

echo; echo "e2e web: ok"
