#!/bin/bash
# story A19: ade web, a read-only page of the hub's agents and logs. A fixture hub (a fake bin/sessions, a journal, a
# chat log, events, a STATE.md) is served on a loopback address and asked with curl. ade runs with only this test's
# fakes and the system's own commands ($T/sys, without tailscale), so a host's Tailscale never answers. Every
# secret-shaped string is built here at run time from parts; none is written in this file.
. "$(dirname "$0")/helpers.sh"
REAL_HOME="$HOME"   # before fresh: the real ~/.config/ade must not change (web_no_hub_writes)

farm() {   # $T/sys: the system's commands without tailscale; this test's own python3
  python3 - "$T/sys" "$(command -v python3)" <<'PY'
import os, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
os.symlink(sys.argv[2], os.path.join(d, "python3"))
for src in ("/usr/bin", "/bin", "/usr/sbin", "/sbin"):
    try: names = os.listdir(src)
    except OSError: continue
    for n in names:
        p = os.path.join(d, n)
        if n != "tailscale" and not os.path.lexists(p) and os.access(os.path.join(src, n), os.X_OK): os.symlink(os.path.join(src, n), p)
PY
}
rep() { local i=0 out=""; while [ "$i" -lt "$2" ]; do out="$out$1"; i=$((i + 1)); done; printf '%s' "$out"; }   # <text> <times>
free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
# listeners <port>: the local address of every TCP socket listening on that port, one per line
listeners() {
  if command -v lsof > /dev/null 2>&1; then lsof -nP -iTCP:"$1" -sTCP:LISTEN 2> /dev/null | awk 'NR > 1 { print $9 }' | sort -u
  elif command -v ss > /dev/null 2>&1; then ss -ltnH 2> /dev/null | awk -v p=":$1" 'substr($4, length($4) - length(p) + 1) == p { print $4 }' | sort -u
  else fail "neither lsof nor ss: the listening socket cannot be checked"; fi
}
refused() { ! python3 -c 'import socket, sys; socket.create_connection((sys.argv[1], int(sys.argv[2])), 2).close()' "$1" "$2" 2> /dev/null; }

# the secrets of the redaction test, each from parts
S_TG="$(rep 7 9):$(rep Ab 18)"                    # a Telegram bot token: digits, a colon, 36 characters
S_SKD="sk""-proj$(rep x9 6)"                      # an sk- key
S_SKU="sk""_live_$(rep q7 6)"                     # an sk_ key
S_GHL="gh""p_$(rep Zz9 12)"                       # a GitHub token, 36 characters after the prefix
S_GHS="gh""o_$(rep k4 10)"                        # a shorter one (under the hub rule's 32)
S_PAT="github""_pat_$(rep m3 11)"
S_PW="hunter$(rep 2 3)x"                          # after password=
S_PWJ="tr0ub$(rep 4 2)dor"                        # after "password":
S_AUTH="dXNlcjpw$(rep Y 4)=="                     # after Authorization: Basic
S_BEAR="tok$(rep e 3)n$(rep 5 6)"                 # after Bearer
S_GLM="$(rep a1 9).$(rep b2 5)"                   # <id>.<secret>
S_RUN="$(rep Q 20)$(rep 8 20)"                    # a long opaque run
S_AWS="AK""IA$(rep Q7 8)"                          # an AWS access key id
S_AWSS="$(rep aB3/ 5)$(rep xY+9 5)"               # an AWS secret access key: 40 characters, no run the hub's rule sees
S_URL="pw$(rep z 3)$(rep 6 3)"                    # the password in scheme://user:password@host
S_QK="qk$(rep 4 5)v"                              # after ?key=
S_QT="qt$(rep 8 5)w"                              # after &token=
S_JK="json $(rep k 4) phrase"                     # a JSON value with blanks, after "privateKey":
S_PK1="$(rep Mi 5)+$(rep E9 4)"; S_PK2="$(rep p/ 6)$(rep Q 5)"; S_PK3="$(rep z 6)=="   # lines of a private key block, each under every other rule
PK_BEGIN="-----BEGIN RSA PRIV""ATE KEY-----"; PK_END="-----END RSA PRIV""ATE KEY-----"
SECRETS="$S_AWS $S_AWSS $S_URL $S_QK $S_QT $S_PK1 $S_PK2 $S_PK3 $S_TG $S_SKD $S_SKU $S_GHL $S_GHS $S_PAT $S_PW $S_PWJ $S_AUTH $S_BEAR $S_GLM $S_RUN"
secret_lines() {   # <label>: one line per secret, with a word before and after it
  printf '%s tg before %s after\n' "$1" "$S_TG"; printf '%s skd before %s after\n' "$1" "$S_SKD"
  printf '%s sku before %s after\n' "$1" "$S_SKU"; printf '%s ghl before %s after\n' "$1" "$S_GHL"
  printf '%s ghs before %s after\n' "$1" "$S_GHS"; printf '%s pat before %s after\n' "$1" "$S_PAT"
  printf '%s pw before password=%s after\n' "$1" "$S_PW"; printf '%s pwj before {"password": "%s"} after\n' "$1" "$S_PWJ"
  printf '%s auth before Authorization: Basic %s\n' "$1" "$S_AUTH"; printf '%s bear before Bearer %s after\n' "$1" "$S_BEAR"
  printf '%s glm before %s after\n' "$1" "$S_GLM"; printf '%s run before %s after\n' "$1" "$S_RUN"
  printf '%s aws before %s after\n' "$1" "$S_AWS"; printf '%s awss before aws_secret_access_key = %s after\n' "$1" "$S_AWSS"
  printf '%s url before postgres://admin:%s@db.internal/app after\n' "$1" "$S_URL"
  printf '%s query before https://api.internal/v1?key=%s&page=2&token=%s after\n' "$1" "$S_QK" "$S_QT"
  printf '%s jkey before {"privateKey": "%s", "n": 1} after\n' "$1" "$S_JK"
  printf '%s esc before {\\"apiSecret\\": \\"%s\\"} after\n' "$1" "$S_JK"
  printf '%s block before\n%s\n%s\n%s\n%s\n%s\n%s block after\n' "$1" "$PK_BEGIN" "$S_PK1" "$S_PK2" "$S_PK3" "$PK_END" "$1"
  printf '%s oneline before %s%s%s after\n' "$1" "$PK_BEGIN" "$S_PK1" "$PK_END"
}

fixture() {
  fresh; trap 'stop; drop_t' EXIT   # after fresh, which sets its own: a failed check must not leave a server running
  farm; F="$T/fake"; mkdir -p "$F"; CALLS="$T/calls"; : > "$CALLS"; export CALLS
  H="$T/hub"; S="$T/state"; make_hub "$H" hub; echo "HUB_NAME=acme" > "$H/hub.conf"
  mkdir -p "$H/journal" "$H/projects/api" "$H/projects/link" "$H/ops/infra" "$S/logs" "$T/outside"
  echo "CANARY-OUTSIDE" > "$T/outside/STATE.md"; echo "CANARY-CONF" >> "$H/hub.conf"
  ln -s "$T/outside/STATE.md" "$H/projects/link/STATE.md"
  # the fake bin/sessions: the hub's columns; one row with a folder outside the hub, one whose STATE.md is a link out
  cat > "$H/bin/sessions" <<SH
#!/bin/bash
echo "sessions \$*" >> "$CALLS"
printf '%-16s %-26s %-8s %-8s %-21s %-10s %-6s %-20s %s\n' NAME FOLDER PID PARENT STARTED ROLE STATUS LAST ENGINE
printf '%-16s %-26s %-8s %-8s %-21s %-10s %-6s %-20s %s\n' api projects/api 4242 - 2026-11-23T09:00:00Z builder busy 2026-11-23T09:05:00Z claude
printf '%-16s %-26s %-8s %-8s %-21s %-10s %-6s %-20s %s\n' infra ops/infra 4343 - 2026-11-23T08:00:00Z - idle 2026-11-23T08:30:00Z gemini
printf '%-16s %-26s %-8s %-8s %-21s %-10s %-6s %-20s %s\n' evil ../outside 4444 - 2026-11-23T08:00:00Z - idle - claude
printf '%-16s %-26s %-8s %-8s %-21s %-10s %-6s %-20s %s\n' link projects/link 4545 - 2026-11-23T08:00:00Z $S_SKD idle - claude
SH
  chmod +x "$H/bin/sessions"
  TODAY="$(date -u +%Y-%m-%d)"
  { echo "# Journal"; echo "journal entry one"; secret_lines journal; } > "$H/journal/$TODAY.md"
  python3 - "$H/journal" <<'PY'
import os, sys, time
for off in (-1, 1):   # yesterday, and tomorrow in case the date turns during the test
    d = time.strftime("%Y-%m-%d", time.gmtime(time.time() + off * 86400))
    open(os.path.join(sys.argv[1], d + ".md"), "w").write("# Journal\nnearby entry %s\n" % d)
PY
  echo "CANARY-OLD" > "$H/journal/2001-01-01.md"
  { echo "chat line one"; secret_lines chat
    printf 'esc \033[31mred\033[0m \033]0;title\007 bell\007 nul\000 cr\r c1\302\233 bidi\342\200\256 end\n'
    echo '<script>alert(1)</script><img src=x onerror=alert(2)>'
    printf 'split sk\033[0m-%s end\n' "$(rep w6 6)"; } > "$S/logs/chat.log"
  { echo "state of api"; secret_lines state; } > "$H/projects/api/STATE.md"
  python3 - "$S/events.jsonl" "$S_TG $S_SKD $S_SKU $S_GHL $S_GHS $S_PAT $S_GLM $S_RUN $S_AWS" <<'PY'
import json, sys
rows = [("2026-11-23T09:01:00Z", "projects/api", "main", "idle", "api went idle"),
        ("2026-11-23T09:02:00Z", "main", "projects/api", "note", "a note to api"),
        ("2026-11-23T09:03:00Z", "ops/infra", "main", "idle", "infra only"),
        ("2026-11-23T09:04:00Z", "main", "all", "note", "a note to all")]
rows += [("2026-11-23T09:05:00Z", "projects/api", "main", "note", "event before %s after" % s) for s in sys.argv[2].split()]
with open(sys.argv[1], "w") as f:
    for t, a, b, k, x in rows: f.write(json.dumps({"time": t, "from": a, "to": b, "kind": k, "text": x}) + "\n")
    f.write("not json\n")
PY
  export ADE_HUB="$H" AGENT_STATE="$S"
  WPATH="$F:$T/sys"; SRV=""
  # the browser openers: each logs its arguments and keeps a copy of the file it was given (never a real browser)
  local o; for o in open xdg-open; do
    printf '#!/bin/bash\necho "%s $*" >> "$CALLS"; cp "$1" "%s/opened.html" 2> /dev/null; exit 0\n' "$o" "$T" > "$F/$o"; chmod +x "$F/$o"; done
  export DISPLAY=:99; unset SSH_CONNECTION SSH_TTY WAYLAND_DISPLAY; mkdir -p "$T/tmp"
  # story M2: ade web shows its code on its own terminal (/dev/tty), so each run gets one: a new pseudo-terminal as its
  # controlling terminal, its stdout and stderr still the files given. What it writes there goes to $T/tty.out; bytes
  # added to $T/tty.in are typed into it (a newline is Enter). TERM, HUP and INT are passed on; the exit status is its.
  cat > "$T/tty.py" <<'PY'
import fcntl, os, select, signal, subprocess, sys, termios, time
d = sys.argv[1]; m, s = os.openpty()
def ctty(): fcntl.ioctl(s, termios.TIOCSCTTY, 0)
p = subprocess.Popen(sys.argv[2:], stdin=subprocess.DEVNULL, start_new_session=True, preexec_fn=ctty)
# s stays open here: on macOS a terminal that no process holds open stops being the child's terminal
for n in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT): signal.signal(n, lambda n, f: p.send_signal(n))
out = open(os.path.join(d, "tty.out"), "ab", buffering=0); fed = [0]
def pump():
    try: b = os.read(m, 4096) if select.select([m], [], [], 0.05)[0] else b""
    except OSError: b = b""; time.sleep(0.05)
    if b: out.write(b)
    try:
        with open(os.path.join(d, "tty.in"), "rb") as f: data = f.read()
    except OSError: data = b""
    if len(data) > fed[0]: os.write(m, data[fed[0]:]); fed[0] = len(data)
while p.poll() is None: pump()
pump()
sys.exit(p.returncode if p.returncode >= 0 else 128 - p.returncode)
PY
  TTYRUN=(python3 -I "$T/tty.py" "$T")
}
# start [args]: ade web in the background; URL, PORT and K from its first line
start() {
  : > "$T/web.out"; : > "$T/web.err"; : > "$T/tty.out"; rm -f "$T/tty.in"
  PATH="$WPATH" TMPDIR="$T/tmp" "${TTYRUN[@]}" "$ADE" web --no-open "$@" > "$T/web.out" 2> "$T/web.err" &
  SRV=$!; local i=0
  until grep -q '^ade web: http://' "$T/web.out"; do
    kill -0 "$SRV" 2> /dev/null || { cat "$T/web.err" >&2; fail "ade web $* ended before it printed its address"; }
    i=$((i + 1)); [ "$i" -lt 100 ] || fail "ade web $* printed no address in 10 s"; sleep 0.1; done
  URL="$(sed -n 's/^ade web: \(http:.*\)$/\1/p' "$T/web.out" | head -1)"
  K="${URL##*\?k=}"; BASE="${URL%%/\?k=*}"; PORT="${BASE##*:}"; ADDR="${BASE#http://}"; ADDR="${ADDR%:*}"
}
stop() {
  [ -n "${SRV:-}" ] || return 0
  kill "$SRV" 2> /dev/null; local i=0
  while kill -0 "$SRV" 2> /dev/null; do i=$((i + 1)); [ "$i" -lt 100 ] || { kill -9 "$SRV"; fail "ade web did not stop within 10 s of SIGTERM"; }; sleep 0.1; done
  wait "$SRV" 2> /dev/null; SRV=""
}
# get <path> [curl args]: one request to the server's own address; CODE, the body in $T/body, the headers in $T/head.
# The cookie jar is used only when asked for (-b), so each request shows what it alone is allowed.
get() {
  local p="$1"; shift
  CODE="$(curl -q -s --path-as-is --max-time 10 -o "$T/body" -D "$T/head" -w '%{http_code}' "$@" "$BASE$p")" || fail "no answer for $p"
}
# tty_code [old]: the code ade web last wrote to its terminal (story M2), waiting for one other than old
tty_code() {
  local c="" i=0
  while :; do
    c="$(tr -d '\r' < "$T/tty.out" | sed -n 's/.*ade web: the code for the page: \([A-Za-z0-9]*\).*/\1/p' | tail -1)"
    [ -n "$c" ] && [ "$c" != "${1:-}" ] && break
    i=$((i + 1)); [ "$i" -lt 100 ] || fail "no code on ade web's terminal in 10 s"; sleep 0.1; done
  printf '%s' "$c"
}
# post <json> [curl args]: POST /login as the page sends it (its own Origin, the token header, JSON)
post() { local b="$1"; shift; get "/login" -X POST -H "Origin: $BASE" -H "X-Ade-Key: $K" -H "Content-Type: application/json" --data-binary "$b" "$@"; }
set_cookie() { tr -d '\r' < "$T/head" | sed -n 's/^[Ss]et-[Cc]ookie: \([^;]*\);.*/\1/p' | head -1; }
# login: the first visit with the link, then the code from the terminal; CK is the session cookie it set. api: a request
# with that cookie (sent as a header: curl's own cookie jar would keep it from a request whose Host header names another
# host, which is the server's decision to make here)
login() {
  get "/?k=$K"; assert_eq "$CODE" 200 "the link"
  post "{\"code\": \"$(tty_code)\"}"; assert_eq "$CODE" 200 "the code"; CK="$(set_cookie)"; [ -n "$CK" ] || fail "the code set no cookie"
}
api() { local p="$1"; shift; get "$p" -H "Cookie: $CK" -H "X-Ade-Key: $K" "$@"; }
# flat: every string of the JSON body, one per line, in $T/text (the body itself spells < as \u003c)
flat() { python3 -c 'import json, sys
def walk(v):
    if isinstance(v, dict):
        for k in v: walk(k); walk(v[k])
    elif isinstance(v, list):
        for x in v: walk(x)
    elif isinstance(v, str): print(v)
walk(json.load(open(sys.argv[1])))' "$T/body" > "$T/text"; }
json() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"d": d}))' "$T/body" "$1"; }

t_local() {
  fixture
  # 8765 when it is free, else a free port: the default port is taken from ADE_WEB_PORT here, since a host may use 8765
  local p; p="$(free_port)"
  ADE_WEB_PORT="$p" start
  assert_eq "$PORT" "$p" "the default port when it is free"; assert_eq "$ADDR" 127.0.0.1 "the address printed"
  [ "${#K}" -ge 32 ] || fail "the token is short: ${#K} characters"
  assert_eq "$(listeners "$PORT")" "127.0.0.1:$PORT" "listens on 127.0.0.1 only"
  assert_contains "$T/web.out" "read-only" "says it is read-only"; assert_contains "$T/web.out" "Ctrl-C" "says how to stop"
  # the default port busy: another free one, on 127.0.0.1 again (another user's ade web would be another HOME)
  local first="$SRV" firsturl="$URL"; SRV=""
  HOME="$T/home2" ADE_WEB_PORT="$p" start
  [ "$PORT" != "$p" ] || fail "a busy default port was used again"
  assert_eq "$(listeners "$PORT")" "127.0.0.1:$PORT" "the free port is on 127.0.0.1 only"
  [ "$URL" != "$firsturl" ] || fail "two servers printed the same link"
  # --port N busy: refused, nothing served
  if PATH="$WPATH" HOME="$T/home3" "${TTYRUN[@]}" "$ADE" web --port "$p" > "$T/out" 2> "$T/err"; then fail "--port on a busy port started"; fi
  assert_contains "$T/err" "port $p is in use" "a busy --port says so"
  stop; SRV="$first"; stop
  # --port N free
  p="$(free_port)"; start --port "$p"; assert_eq "$PORT" "$p" "--port N"; stop
  local a; for a in "--port" "--port x" "--port 0" "--port 70000" "--port 80" "--bind 0.0.0.0" "--host 0.0.0.0" "extra"; do
    # shellcheck disable=SC2086  # the arguments of one case, split on purpose
    PATH="$WPATH" "$ADE" web $a > "$T/out" 2> "$T/err"; assert_eq "$?" 2 "ade web $a is a usage error"
    assert_contains "$T/err" "usage: ade web" "ade web $a prints the usage"; done
  PATH="$WPATH" "$ADE" help > "$T/out"; assert_contains "$T/out" "ade web [--port N] [--tailnet] [--no-open] | --print-link | --stop" "help lists ade web"
}

t_token() {
  fixture; start
  get "/"; assert_eq "$CODE" 403 "no token"; assert_not_contains "$T/body" "acme" "403 carries no data"
  get "/?k=wrong"; assert_eq "$CODE" 403 "a wrong token"
  get "/?k=${K}x"; assert_eq "$CODE" 403 "a longer token"
  get "/?k="; assert_eq "$CODE" 403 "an empty token"
  get "/api/agents"; assert_eq "$CODE" 403 "the API without a cookie"; assert_not_contains "$T/body" "api" "403 carries no agent"
  get "/api/agents?k=$K"; assert_eq "$CODE" 403 "the link's token opens the page only, never the API"
  get "/api/chat" -H "X-Ade-Key: $K" -H "Cookie: ade_web_$PORT=wrong"; assert_eq "$CODE" 401 "a wrong cookie (story M2: the right token header without a session is 401)"
  get "/api/chat" -H "X-Ade-Key: $K" -H "Cookie: ade_web_$PORT=$K"; assert_eq "$CODE" 401 "the link's token is not the cookie"
  assert_not_contains "$T/body" "chat line one" "403 carries no log"
  login
  grep -i '^set-cookie:' "$T/head" > "$T/cookie" || fail "the code sets no cookie"
  assert_contains "$T/cookie" "ade_web_$PORT=" "the cookie is named for the port"
  grep -qi 'httponly' "$T/cookie" || fail "the cookie is not HttpOnly"
  grep -qi 'samesite=strict' "$T/cookie" || fail "the cookie is not SameSite=Strict"
  assert_not_contains "$T/cookie" "$K" "the cookie is not the link's token"
  api "/"; assert_eq "$CODE" 200 "the page with the cookie alone"
  # several cookies of that name (another page on this host can plant one with a longer path): one right one is enough
  get "/api/agents" -H "X-Ade-Key: $K" -H "Cookie: ade_web_$PORT=planted; x=1; $CK"; assert_eq "$CODE" 200 "a planted cookie before the real one"
  get "/api/agents" -H "X-Ade-Key: $K" -H "Cookie: $CK; ade_web_$PORT=planted"; assert_eq "$CODE" 200 "a planted cookie after the real one"
  get "/api/agents" -H "X-Ade-Key: $K" -H "Cookie: ade_web_$PORT=planted; ade_web_$PORT=; ade_web_1=${CK#*=}"; assert_eq "$CODE" 401 "only wrong cookies"
  api "/api/agents"; assert_eq "$CODE" 200 "the API with the cookie"
  assert_not_contains "$T/web.out" "GET " "no access log on stdout"; assert_not_contains "$T/web.err" "$K" "the token is never logged"
  stop
}

t_host() {
  fixture; start; login
  local h
  for h in "127.0.0.1:$PORT" "localhost:$PORT" "LOCALHOST:$PORT"; do api "/api/agents" -H "Host: $h"; assert_eq "$CODE" 200 "Host $h"; done
  for h in "evil.example:$PORT" "127.0.0.1" "localhost" "127.0.0.1:1" "127.0.0.1.evil.example:$PORT" "[::1]:$PORT" "0.0.0.0:$PORT" ""; do
    api "/api/agents" -H "Host: $h"; assert_eq "$CODE" 403 "Host [$h]"; assert_not_contains "$T/body" "projects/api" "Host [$h] gets no data"
    get "/?k=$K" -H "Host: $h"; assert_eq "$CODE" 403 "Host [$h] with the link"; done
  # no CORS header, whatever the Origin; the browser's own guards are set
  for h in "/" "/api/agents" "/api/chat" "/nothing"; do
    api "$h" -H "Origin: https://evil.example"
    if grep -qi '^access-control-' "$T/head"; then fail "a CORS header on $h"; fi
    grep -qi '^x-content-type-options: nosniff' "$T/head" || fail "no nosniff on $h"
    grep -qi '^cache-control: no-store' "$T/head" || fail "no no-store on $h"; done
  api "/"; grep -qi "^content-security-policy: default-src 'none'" "$T/head" || fail "the page has no content security policy"
  grep -qi "frame-ancestors 'none'" "$T/head" || fail "the page may be framed"
  api "/api/agents" -H "Origin: https://evil.example" -H "Sec-Fetch-Site: cross-site"; assert_eq "$CODE" 403 "a cross-site request to the API"
  stop
}

snapshot() { ( cd "$T" && find hub state -exec ls -ldT {} + 2> /dev/null || find hub state -exec ls -ld --full-time {} +; find hub state -type f -exec cksum {} + ) | sort; }
t_readonly() {
  fixture; snapshot > "$T/before"; start; login
  local m p
  for m in POST PUT DELETE PATCH OPTIONS TRACE FOO; do for p in "/" "/?k=$K" "/api/agents" "/api/log?agent=api" "/api/stop"; do
    api "$p" -X "$m" -d 'x=1'; assert_eq "$CODE" 405 "$m $p"; assert_not_contains "$T/body" "projects/api" "$m $p carries no data"
    grep -qi '^allow: GET' "$T/head" || fail "$m $p names no allowed method"; done; done
  CODE="$(curl -q -s -I --max-time 10 -o /dev/null -w '%{http_code}' -H "Cookie: $CK" "$BASE/")"; assert_eq "$CODE" 405 "HEAD"
  for p in "/" "/api/agents" "/api/log?agent=api" "/api/log?agent=infra" "/api/journal" "/api/chat" "/api/stop" "/api/agents?stop=1"; do api "$p"; done
  stop; snapshot > "$T/after"
  cmp -s "$T/before" "$T/after" || { diff "$T/before" "$T/after" >&2; fail "the hub or its state folder changed"; }
  assert_eq "$(sort -u "$CALLS")" "sessions " "the only hub command run is bin/sessions, with no argument"
}

t_page() {
  fixture; start; login; api "/"   # story M2: login ends on POST /login, so the page is asked for
  grep -qi '^content-type: text/html; charset=utf-8' "$T/head" || fail "the page is not HTML"
  assert_contains "$T/body" '<meta name="viewport"' "the page fits a phone"
  # one document: no address but its own API, no script or style from elsewhere
  if grep -Eqi 'https?://|//[a-z0-9.-]+\.[a-z]{2,}|<link|@import|src=' "$T/body"; then fail "the page names an outside address or file"; fi
  local s; for s in agents detail events; do assert_contains "$T/body" "aria-label=\"$s\"" "the page has a $s pane"; done
  api "/api/agents"; grep -qi '^content-type: application/json' "$T/head" || fail "the API is not JSON"
  assert_eq "$(json '[a["name"] for a in d["agents"]]')" "['main', 'api', 'infra', 'evil', 'link']" "the orchestrator, then the agents of bin/sessions"
  assert_eq "$(json 'd["agents"][1]["status"] + " " + d["agents"][1]["folder"] + " " + d["agents"][1]["role"] + " " + d["agents"][1]["engine"]')" "busy projects/api builder claude" "an agent's state"
  assert_eq "$(json 'd["agents"][2]["status"] + " " + d["agents"][2]["last"]')" "idle 2026-11-23T08:30:00Z" "the second agent"
  assert_eq "$(json 'd["hub"]')" acme "the hub's name"
  assert_not_contains "$T/body" 4242 "no process id is served"
  api "/api/log?agent=api"; assert_eq "$CODE" 200 "an agent's log"
  assert_eq "$(json 'd["state"][0]')" "state of api" "the agent's STATE.md"
  assert_contains "$T/body" "api went idle" "an event from the agent"; assert_contains "$T/body" "a note to api" "an event to the agent"
  assert_contains "$T/body" "a note to all" "an event to all"; assert_not_contains "$T/body" "infra only" "another agent's event"
  assert_eq "$(json 'd["events"][0]')" "2026-11-23T09:01:00Z  projects/api -> main  idle: api went idle" "an event line"
  api "/api/log?agent=infra"; assert_eq "$(json 'd["state"]')" "[]" "an agent with no STATE.md"; assert_contains "$T/body" "infra only" "its events"
  api "/api/journal"
  assert_contains "$T/body" "journal entry one" "today's journal"; assert_contains "$T/body" "nearby entry" "yesterday's journal"
  assert_eq "$(json '"nearby entry " + d["yesterday"]["date"] in d["yesterday"]["lines"]')" True "yesterday's file is yesterday's"
  assert_not_contains "$T/body" "CANARY-OLD" "no older journal"
  api "/api/chat"; assert_eq "$(json 'd["lines"][0]')" "chat line one" "the chat log"
  # the sessions list is asked again on a later request (the page asks every 3 s)
  local n; n="$(grep -c . "$CALLS")"; sleep 2.2; api "/api/agents"; [ "$(grep -c . "$CALLS")" -gt "$n" ] || fail "bin/sessions was not run again"
  # a hub whose bin/sessions fails or prints rubbish: an empty list and a note, never a 500
  printf '#!/bin/bash\necho "sessions: broken"; echo "one two three"; exit 3\n' > "$H/bin/sessions"; sleep 2.2
  api "/api/agents"; assert_eq "$CODE" 200 "a failing bin/sessions"; assert_eq "$(json '[a["name"] for a in d["agents"]]')" "['main']" "no agent but the orchestrator"
  assert_eq "$(json 'd["note"]')" "bin/sessions failed (exit 3)" "the note"
  stop
}

t_redact() {
  fixture; start; login
  local p s w
  for p in "/api/chat" "/api/journal" "/api/log?agent=api" "/api/agents"; do
    api "$p"; assert_eq "$CODE" 200 "$p"; flat
    for s in $SECRETS; do assert_not_contains "$T/body" "$s" "$p shows a secret"; assert_not_contains "$T/text" "$s" "$p shows a secret"; done; done
  for p in "/api/chat:chat" "/api/journal:journal" "/api/log?agent=api:state"; do
    api "${p%:*}"; flat
    for w in tg skd sku ghl ghs pat pw pwj bear glm run aws awss url query jkey esc oneline; do
      grep -Eq "${p##*:} $w before .*after" "$T/text" || fail "${p%:*}: the words around the $w secret are gone"; done
    grep -Eq "${p##*:} auth before Authorization: <hidden>" "$T/text" || fail "${p%:*}: the Authorization line"
    assert_contains "$T/text" "password=<hidden> after" "${p%:*}: password="
    assert_not_contains "$T/text" "$S_JK" "${p%:*}: a JSON value with blanks"; assert_not_contains "$T/text" "phrase" "${p%:*}: the end of a JSON value"
    assert_contains "$T/text" "postgres://<hidden>@db.internal/app after" "${p%:*}: the host of a URL is kept"
    assert_contains "$T/text" "?key=<hidden>&page=2&token=<hidden> after" "${p%:*}: query values"
    assert_contains "$T/text" "aws_secret_access_key = <hidden> after" "${p%:*}: the AWS secret"
    # a private key block: one marker for all of it, the lines around it kept
    assert_eq "$(grep -A 2 "${p##*:} block before" "$T/text" | tr '\n' '|')" "${p##*:} block before|<hidden private key>|${p##*:} block after|" "${p%:*}: a private key block"
    if grep -Eq 'BEGIN|PRIV|-----' "$T/text"; then fail "${p%:*}: part of a private key block is shown"; fi; done
  # the end of a block whose beginning is above what is read: the short lines before it go too; a block that never ends
  { echo "tail before"; echo "$S_PK2"; echo "$S_PK3"; echo "$PK_END"; echo "tail after"; echo "$PK_BEGIN"; echo "$S_PK1"; echo "never shown"; } > "$H/ops/infra/STATE.md"
  api "/api/log?agent=infra"; flat
  assert_eq "$(json 'd["state"]')" "['tail before', '<hidden private key>', 'tail after', '<hidden private key>']" "a block cut at either end"
  for s in $SECRETS; do assert_not_contains "$T/text" "$s" "a block cut at either end shows a secret"; done
  # GitLab tokens, Cookie headers, a URL-encoded secret (each built from parts)
  local gl="glpat""-Ab3dEf6hIj9kLm2nOp5q" ck="sess""ion=Zq81mXv0Lw" ue="Ux7""Kp2Qz9"
  { echo "gl before $gl after"; echo "ck before Cookie: $ck; theme=dark"; echo "ue before client_secret%3D$ue&x=1 after"; } > "$H/ops/infra/STATE.md"
  api "/api/log?agent=infra"; flat
  for s in "$gl" "$ck" "$ue"; do assert_not_contains "$T/text" "$s" "a GitLab token, cookie or URL-encoded secret"; done
  assert_contains "$T/text" "gl before <hidden token> after" "a GitLab token"; assert_contains "$T/text" "ck before Cookie: <hidden>" "a Cookie header"
  assert_contains "$T/text" "client_secret%3D<hidden>&x=1 after" "a URL-encoded secret"
  api "/api/log?agent=api"; flat; assert_contains "$T/text" "event before <hidden" "an event's secret is hidden, its words kept"
  api "/api/agents"; assert_eq "$(json 'd["agents"][4]["role"]')" "<hidden key>" "a key in a bin/sessions column"
  # a key an escape sequence splits is one key once the sequence is gone (the hub's order)
  api "/api/chat"; flat; assert_contains "$T/text" "split <hidden key> end" "a split key"
  stop
}

t_escapes() {
  fixture; start; login; api "/api/chat"
  python3 - "$T/body" <<'PY' || fail "a control character or an escape sequence reached the browser"
import json, re, sys
raw = open(sys.argv[1], "rb").read()
assert not re.search(rb"[\x00-\x09\x0b-\x1f\x7f-\xff]", raw), "raw control or non-ASCII byte in the response"
d = json.loads(raw.decode("ascii")); text = "\n".join(d["lines"])
bad = re.search(r"[\x00-\x08\x0b-\x1f\x7f-\x9f‪-‮⁦-⁩]", text)
assert not bad, "control character %r" % (bad and bad.group(0))
line = [l for l in d["lines"] if l.startswith("esc ")][0]
assert line == "esc red  bell nul cr c1 bidi end", repr(line)
assert "<script>alert(1)</script><img src=x onerror=alert(2)>" in d["lines"], "the HTML line is not served as text"
assert b"<script" not in raw and b"<img" not in raw, "a tag is spelled out in the JSON"
PY
  grep -qi '^content-type: application/json' "$T/head" || fail "log text is not served as JSON"
  api "/"
  if grep -Eq 'innerHTML|outerHTML|insertAdjacentHTML|document\.write|eval\(|new Function|srcdoc' "$T/body"; then fail "the page can insert HTML"; fi
  assert_contains "$T/body" "textContent" "the page inserts text"
  assert_not_contains "$T/body" "alert(1)" "no log text in the page itself"; assert_not_contains "$T/body" "chat line one" "no log text in the page itself"
  stop
}

t_paths() {
  fixture; echo "CANARY-ABS" > "$T/canary"; ADE_WEB_OPENED="$T/opened" start; login
  local p; for p in "/api/agents" "/api/log?agent=api" "/api/journal" "/api/chat"; do api "$p"; assert_eq "$CODE" 200 "$p"; done
  for p in "/api/log?agent=nosuch" "/api/log?agent=../../canary" "/api/log?agent=..%2F..%2Fcanary" "/api/log?agent=%2e%2e/outside" \
           "/api/log?agent=$T/canary" "/api/log?agent=projects/api" "/api/log?agent=" "/api/log" "/api/log?agent=api&agent=infra" \
           "/api/log?agent=api%00" "/api/log?agent=API" "/api/log?path=$T/canary" "/api/file?path=$T/canary" "$T/canary" "/$T/canary" \
           "/../../../../etc/hosts" "/..%2f..%2fetc/hosts" "/etc/hosts" "//etc/hosts" "/journal/../hub.conf" "/hub.conf" "/api/journal/2001-01-01" \
           "/api/journal?date=2001-01-01.md&file=$T/canary" "/api/chat/../../canary" "/api" "/api/" "/index.html" "/favicon.ico"; do
    api "$p"
    case "$p" in "/api/journal?"*) assert_eq "$CODE" 200 "a parameter the server does not read: $p" ;; *) assert_eq "$CODE" 404 "$p" ;; esac
    if grep -Eq 'CANARY|localhost' "$T/body"; then fail "$p served a file it was not asked to choose"; fi
  done
  # the server has no switch that writes anywhere: the open trace of the first version is gone
  [ ! -e "$T/opened" ] || fail "ADE_WEB_OPENED still writes a file"
  if grep -q "ADE_WEB_OPENED" "$ADE"; then fail "ade still reads ADE_WEB_OPENED"; fi
  # a folder outside the hub in bin/sessions' own output, and a STATE.md that is a link out of the hub: listed, never read
  for p in evil link; do api "/api/log?agent=$p"; assert_eq "$CODE" 200 "$p is in the list"; assert_eq "$(json 'd["state"]')" "[]" "$p: no STATE.md is read"
    assert_not_contains "$T/body" "CANARY" "$p: a file outside the hub was served"; done
  # a journal folder and a chat log that are links out of the hub and its state folder
  stop; rm -rf "$H/journal" "$S/logs/chat.log"; mkdir "$T/elsewhere"; echo "CANARY-LINKED" > "$T/elsewhere/$TODAY.md"; echo "CANARY-LINKED" > "$T/elsewhere/chat.log"
  ln -s "$T/elsewhere" "$H/journal"; ln -s "$T/elsewhere/chat.log" "$S/logs/chat.log"
  start; login
  for p in "/api/journal" "/api/chat"; do api "$p"; assert_eq "$CODE" 200 "$p"; assert_not_contains "$T/body" "CANARY" "$p followed a link out"; done
  stop
}

ts_fake() {   # the fake tailscale: `ip -4` prints $TS_IP (none: exit 1), `status --json` prints $TS_JSON; every call is logged
  cat > "$F/tailscale" <<'SH'
#!/bin/bash
echo "tailscale $*" >> "$CALLS"
case "$*" in
  "ip -4") [ -n "${TS_IP:-}" ] || { echo "no current Tailscale IPs; state: NeedsLogin" >&2; exit 1; }; printf '%s\n' "$TS_IP" ;;
  "status --json") printf '%s\n' "${TS_JSON:-}" ;;
  *) exit 64 ;;
esac
SH
  chmod +x "$F/tailscale"
}
ts_json() { printf '{"BackendState": "%s", "Self": {"DNSName": "%s", "TailscaleIPs": ["%s"]}}' "$1" "$2" "${TS_IP:-}"; }
t_tailnet() {
  fixture
  # no tailscale on the PATH: refused, with how to get it; nothing listens
  if PATH="$WPATH" "$ADE" web --tailnet > "$T/out" 2> "$T/err"; then fail "--tailnet started without tailscale"; fi
  assert_contains "$T/err" "Tailscale is not installed" "says Tailscale is missing"; assert_contains "$T/err" "https://tailscale.com/download" "says where to get it"
  assert_contains "$T/err" "ade never installs it" "says ade installs nothing"; [ ! -e "$HOME/.config/ade/web" ] || fail "a link file without a server"
  ts_fake
  # not signed in: no address, or a backend that is not running
  export TS_IP="" TS_JSON; TS_JSON="$(ts_json NeedsLogin "")"
  if PATH="$WPATH" "$ADE" web --tailnet > "$T/out" 2> "$T/err"; then fail "--tailnet started while signed out"; fi
  assert_contains "$T/err" "not signed in" "says Tailscale is not signed in"; assert_contains "$T/err" "tailscale up" "says how to sign in"
  TS_IP="100.100.1.2"; TS_JSON="$(ts_json Stopped "mac.tail1234.ts.net.")"
  if PATH="$WPATH" "$ADE" web --tailnet > "$T/out" 2> "$T/err"; then fail "--tailnet started with Tailscale stopped"; fi
  assert_contains "$T/err" "not signed in" "a stopped Tailscale"
  TS_JSON="not json"
  if PATH="$WPATH" "$ADE" web --tailnet > "$T/out" 2> "$T/err"; then fail "--tailnet started with an unreadable status"; fi
  # an address outside 100.64.0.0/10 is never bound: every interface, loopback, a home network, the range's neighbours
  local a
  for a in 0.0.0.0 127.0.0.1 192.168.1.20 10.0.0.5 100.63.255.255 100.128.0.1 100.64.0.256 100.64.1 "100.64.0.1 0.0.0.0" "fd7a:115c:a1e0::1" "::" "" "x"; do
    TS_IP="$a"; TS_JSON="$(ts_json Running "mac.tail1234.ts.net.")"; [ -n "$a" ] || TS_JSON="$(ts_json Running "")"
    if PATH="$WPATH" "$ADE" web --tailnet > "$T/out" 2> "$T/err"; then fail "--tailnet started on [$a]"; fi
    grep -Eq "not a Tailscale address|not signed in" "$T/err" || fail "[$a]: $(cat "$T/err")"
    assert_not_contains "$T/out" "http://" "[$a]: no address printed"; done
  # an address in the range that this machine does not have: only that address is tried, then refused
  TS_IP="100.127.255.254"; TS_JSON="$(ts_json Running "mac.tail1234.ts.net.")"
  : > "$T/tty.out"; PATH="$WPATH" "${TTYRUN[@]}" "$ADE" web --tailnet > "$T/out" 2> "$T/err" & SRV=$!
  ( sleep 10; kill "$SRV" 2> /dev/null ) & local guard=$!
  if wait "$SRV"; then SRV=""; fail "--tailnet served on an address this machine does not have"; fi
  SRV=""; { kill "$guard"; wait "$guard"; } 2> /dev/null
  assert_contains "$T/err" "cannot listen on 100.127.255.254" "only the Tailscale address is tried"; assert_not_contains "$T/out" "http://" "nothing printed"
  # --tailnet --port, and the server itself: on a loopback address standing in for the Tailscale one (the test switch
  # ADE_WEB_TEST_TAILNET_LOOPBACK accepts a loopback address there, never anything wider)
  TS_IP=127.0.0.2; python3 -c 'import socket; socket.socket().bind(("127.0.0.2", 0))' 2> /dev/null || TS_IP=127.0.0.1
  TS_JSON="$(ts_json Running "Mac.Tail1234.ts.net.")"; : > "$CALLS"
  local p; p="$(free_port)"
  ADE_WEB_TEST_TAILNET_LOOPBACK=1 start --tailnet --port "$p"
  assert_eq "$ADDR:$PORT" "$TS_IP:$p" "the address printed is the Tailscale one"
  assert_eq "$(listeners "$PORT")" "$TS_IP:$PORT" "listens on the Tailscale address only"
  [ "$TS_IP" = 127.0.0.1 ] || refused 127.0.0.1 "$PORT" || fail "--tailnet also answers on 127.0.0.1"
  assert_contains "$T/web.out" "http://mac.tail1234.ts.net:$PORT/?k=$K" "the MagicDNS address is printed"
  assert_contains "$T/web.out" "anyone on your tailnet with the link and the code (shown here) can read these logs" "the plain warning"
  assert_contains "$T/web.out" "the link alone is not enough" "says the link alone is not enough"
  assert_eq "$(sort -u "$CALLS" | tr '\n' ';')" "tailscale ip -4;tailscale status --json;" "tailscale is only asked, never changed"
  login
  local h
  for h in "$TS_IP:$PORT" "mac.tail1234.ts.net:$PORT" "MAC.tail1234.ts.net:$PORT"; do api "/api/agents" -H "Host: $h"; assert_eq "$CODE" 200 "Host $h"; done
  for h in "localhost:$PORT" "mac.tail1234.ts.net" "mac:$PORT" "mac.tail1234.ts.net.:$PORT" "evil.ts.net:$PORT" "100.100.1.2:$PORT"; do
    api "/api/agents" -H "Host: $h"; assert_eq "$CODE" 403 "Host $h on the tailnet"; done
  [ "$TS_IP" = 127.0.0.1 ] || { api "/api/agents" -H "Host: 127.0.0.1:$PORT"; assert_eq "$CODE" 403 "Host 127.0.0.1 on the tailnet"; }
  get "/api/agents"; assert_eq "$CODE" 403 "the token is required on the tailnet too"
  stop
  # without the switch a loopback address from tailscale is refused (checked above for 127.0.0.1); a MagicDNS name
  # that is not a host name is left out
  TS_JSON="$(ts_json Running "bad name/../x.")"; ADE_WEB_TEST_TAILNET_LOOPBACK=1 start --tailnet
  assert_eq "$(grep -c 'http://' "$T/web.out")" 1 "only the address is printed when the name is not a host name"
  login; api "/api/agents" -H "Host: bad name/../x:$PORT"; assert_eq "$CODE" 403 "a name that is not a host name"
  stop; unset TS_IP TS_JSON
  PATH="$WPATH" "$ADE" web --tailnet --print-link > "$T/out" 2> "$T/err"; assert_eq "$?" 2 "--print-link takes no other option"
}

# timed <limit s> <label> <path>: the request answers 200 within the limit
timed() {
  local s; s="$(curl -q -s --max-time 30 -o "$T/body" -w '%{http_code} %{time_total}' -H "Cookie: $CK" -H "X-Ade-Key: $K" "$BASE$3")" || fail "$2: no answer"
  python3 -c 'import sys; code, took, limit = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]); sys.exit(0 if code == "200" and took < limit else "%s s, HTTP %s (limit %s s)" % (took, code, limit))' "${s% *}" "${s#* }" "$1" || fail "$2"
}
t_long() {   # one very long line (the hub's <id>.<secret> rule is quadratic on it) must not hold the server
  fixture
  python3 - "$S/logs/chat.log" "$H/projects/api/STATE.md" "$H/journal/$TODAY.md" "$S/events.jsonl" <<'PY' || fail "the long lines were not written"
import json, sys
long = "a1" * 125000
for p in sys.argv[1:4]:
    with open(p, "w") as f: f.write("line before\n" + long + "\nline after\n")
with open(sys.argv[4], "w") as f:
    f.write(json.dumps({"time": "t", "from": "projects/api", "to": "main", "kind": "note", "text": long}) + "\n")
PY
  start; login
  local p; for p in "/api/chat" "/api/journal" "/api/log?agent=api"; do
    timed 1 "$p with a 250,000-character line" "$p"; flat
    assert_contains "$T/text" "line before" "$p: the line before"; assert_contains "$T/text" "line after" "$p: the line after"
    [ "$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' "$T/text")" -le 2000 ] || fail "$p: a line longer than 2000 characters was sent"
    if grep -q "a1a1a1a1" "$T/text"; then fail "$p: the long run is shown"; fi; done
  api "/api/chat"; flat; assert_contains "$T/text" "[line cut]" "a cut line says so"
  # a line cut in the middle of a key: the piece left at the cut is not shown
  python3 - "$S/logs/chat.log" "$S_SKD" <<'PY'
import sys
head = ("Q" * 40 + " ") * 99   # runs that are hidden, so the line sent is short and its end is in view
with open(sys.argv[1], "w") as f: f.write(head + "y" * (4089 - len(head)) + " " + sys.argv[2] + " tail\n")   # the key starts 6 characters before the cut
PY
  api "/api/chat"; flat; assert_not_contains "$T/text" "sk-p" "the piece of a key at the cut"; assert_not_contains "$T/text" "tail" "nothing after the cut"
  grep -q 'yyyy  *\[line cut\]$' "$T/text" || fail "the end of the cut line is not in view: $(tail -c 60 "$T/text")"
  # the worst a file can hold (256 KB is read): every line as long as the cut allows, each one run and each different
  worst() { python3 -c 'import sys; open(sys.argv[1], "w").write("".join("%s%04d\n" % ("a1" * 2045, i) for i in range(int(sys.argv[2]), int(sys.argv[2]) + 80)))' "$S/logs/chat.log" "$1"; }
  worst 1000; timed 5 "/api/chat with 80 lines of 4,094 characters" "/api/chat"
  timed 1 "the same lines asked again (worked out once)" "/api/chat"
  # three of those at once, lines not seen before: another request is not kept waiting, and SIGTERM stops the server at once
  local asks=""
  worst 2000; for p in 1 2 3; do curl -q -s --max-time 30 -o /dev/null -H "Cookie: $CK" -H "X-Ade-Key: $K" "$BASE/api/chat" & asks="$asks $!"; done
  timed 3 "/api/agents while three long requests run" "/api/agents"
  # shellcheck disable=SC2086  # the pids of the three requests
  wait $asks; asks=""
  worst 3000; for p in 1 2 3; do curl -q -s --max-time 30 -o /dev/null -H "Cookie: $CK" -H "X-Ade-Key: $K" "$BASE/api/chat" & asks="$asks $!"; done
  local t0; t0="$(python3 -c 'import time; print(time.time())')"; kill "$SRV"; wait "$SRV"; SRV=""
  python3 -c 'import sys, time; took = time.time() - float(sys.argv[1]); sys.exit(0 if took < 2 else "SIGTERM took %.1f s" % took)' "$t0" || fail "the server did not stop promptly under load"
  # shellcheck disable=SC2086
  wait $asks; [ ! -e "$HOME/.config/ade/web" ] || fail "the link file is left after a stop under load"
}

t_link() {
  fixture
  local L="$HOME/.config/ade/web"
  PATH="$WPATH" "$ADE" web --print-link > "$T/out" 2> "$T/err"; assert_eq "$?" 1 "--print-link with no server"
  [ ! -s "$T/out" ] && [ ! -s "$T/err" ] || fail "--print-link with no server printed something"
  start
  assert_eq "$(PATH="$WPATH" "$ADE" web --print-link)" "$URL" "--print-link prints the running server's address"
  ( cd / && unset ADE_HUB && assert_eq "$(PATH="$WPATH" "$ADE" web --print-link)" "$URL" "--print-link needs no hub" ) || exit 1
  [ -f "$L" ] || fail "no link file"
  assert_eq "$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777), oct(os.stat(os.path.dirname(sys.argv[1])).st_mode & 0o777))' "$L")" "0o600 0o700" "the link file is 0600 in a 0700 folder"
  # a second ade web for this user: refused, the first one's link is kept
  if PATH="$WPATH" "$ADE" web > "$T/out" 2> "$T/err"; then fail "a second ade web started"; fi
  assert_contains "$T/err" "already running" "the second says one is running"; assert_not_contains "$T/err" "$K" "and does not print the token to stderr"
  assert_eq "$(PATH="$WPATH" "$ADE" web --print-link)" "$URL" "the first link is kept"
  # SIGTERM: stops, the link file is gone, the port is closed
  local port="$PORT"; stop
  [ ! -e "$L" ] || fail "the link file is left after the server stopped"
  PATH="$WPATH" "$ADE" web --print-link > "$T/out" 2> "$T/err"; assert_eq "$?" 1 "--print-link after the stop"; [ ! -s "$T/out" ] || fail "a link after the stop"
  refused 127.0.0.1 "$port" || fail "the port still answers after the stop"; assert_eq "$(listeners "$port")" "" "no listening socket is left"
  assert_contains "$T/web.out" "ade web: stopped" "says it stopped"
  # SIGHUP (the terminal closed): the same
  start; kill -HUP "$SRV"; wait "$SRV"; SRV=""; [ ! -e "$L" ] || fail "the link file is left after SIGHUP"
  # a link file left by a server that was killed: not a link, removed; a new server starts over it
  ( : ) & wait $!; mkdir -p "$HOME/.config/ade"; printf '%s\nhttp://127.0.0.1:1/?k=stale\n' "$!" > "$L"   # the pid of a process that has ended
  PATH="$WPATH" "$ADE" web --print-link > "$T/out"; assert_eq "$?" 1 "a stale link file"; [ ! -s "$T/out" ] || fail "a stale link was printed"
  [ ! -e "$L" ] || fail "the stale link file is kept"
  # the same for a pid that lives (this test's own) whose address no longer answers: a pid can be reused
  printf '%s\nhttp://127.0.0.1:%s/?k=stale\n' "$$" "$(free_port)" > "$L"
  PATH="$WPATH" "$ADE" web --print-link > "$T/out"; assert_eq "$?" 1 "a link file whose address does not answer"; [ ! -s "$T/out" ] && [ ! -e "$L" ] || fail "a dead address was printed or kept"
  printf 'x\nhttp://127.0.0.1:1/?k=stale\n' > "$L"; start; assert_eq "$(PATH="$WPATH" "$ADE" web --print-link)" "$URL" "a new server replaces a stale file"; stop
  # no hub: refused as every hub command
  ( cd / && unset ADE_HUB && PATH="$WPATH" "$ADE" web > "$T/out" 2> "$T/err"; assert_eq "$?" 2 "ade web with no hub" ) || exit 1
}

# ---- story M1: the live dashboard ----
# acme: a realistic hub. Times are relative to now: api busy (checked in 4 min ago), web idle, docs ready, mobile busy
# with nothing new for 40 min (waiting at a prompt), new listed 10 min ago and not started, infra blocked (a blocked
# event newer than its LAST), billing quiet (a quiet event newer than everything else it sent); a monitor alerting on
# api, another fine; two unread notes to main (a fake bin/inbox); a sync log; journal entries per folder
acme() {
  fixture; rm -rf "$H/journal" "$H/projects/link" "$S/events.jsonl" "$S/logs/chat.log"
  mkdir -p "$H/journal" "$H/projects/web" "$H/projects/mobile" "$H/projects/docs" "$H/projects/new" "$H/projects/billing" "$S/monitor-state"
  python3 - "$H" "$S" "$S_SKD" <<'PY'
import json, os, sys, time
H, S, key = sys.argv[1:4]; now = time.time()
def at(m): return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - m * 60))
rows = [("api", "projects/api", at(95), "builder", "busy", at(2), "claude"),
        ("web", "projects/web", at(300), "reviewer", "idle", at(12), "claude"),
        ("docs", "projects/docs", at(50), "writer", "ready", at(6), "gemini"),
        ("mobile", "projects/mobile", at(130), "builder", "busy", at(40), "codex"),
        ("new", "projects/new", at(10), "-", "-", "-", "claude"),
        ("infra", "ops/infra", at(200), "sysadmin", "idle", at(36), "claude"),
        ("billing", "projects/billing", at(240), "builder", "idle", at(70), "claude")]
with open(os.path.join(H, "bin", "sessions"), "w") as f:
    f.write('#!/bin/bash\necho "sessions $*" >> "$CALLS"\n')
    f.write("printf '%-10s %-18s %-6s %-6s %-21s %-9s %-6s %-21s %s\\n' NAME FOLDER PID PARENT STARTED ROLE STATUS LAST ENGINE\n")
    for i, r in enumerate(rows):
        f.write("printf '%%-10s %%-18s %%-6s %%-6s %%-21s %%-9s %%-6s %%-21s %%s\\n' %s %s %d - %s %s %s %s %s\n" % (r[0], r[1], 5100 + i, r[2], r[3], r[4], r[5], r[6]))
with open(os.path.join(H, "bin", "inbox"), "w") as f:
    f.write('#!/bin/bash\necho "inbox $*" >> "$CALLS"\necho 2\n')
os.chmod(os.path.join(H, "bin", "inbox"), 0o755)
states = {"": "# STATE\n- orchestrating M1 review; K3 gate running\n",
          "projects/api": "# STATE\n## Now\n- rate limiter: tests green, wiring the middleware\n",
          "projects/web": "# STATE\n- waiting for the API change before the checkout page\n",
          "projects/docs": "# STATE\n- install guide rewritten; ready for review\n",
          "projects/mobile": "# STATE\n- push notifications on Android, key %s in the env\n" % key,
          "projects/billing": "# STATE\n- invoice export: retry on timeout\n",
          "ops/infra": "# STATE\n- blocked: the DNS change needs the owner's account\n"}
for d, t in states.items(): open(os.path.join(H, d, "STATE.md"), "w").write(t)
ev = [(55, "projects/api", "main", "pushed", "rate-limiter pushed to origin", False),
      (34, "ops/infra", "main", "blocked", "needs the owner's DNS account to continue", False),
      (31, "main", "projects/web", "note", "API change lands today; checkout after", False),
      (25, "projects/billing", "main", "idle", "invoice export: retry on timeout", False),
      (20, "projects/docs", "main", "contract", "docs/context/api.md updated", False),
      (14, "projects/api", "main", "note", "check-in: middleware half done, 3 tests left", True),
      (9, "projects/billing", "main", "quiet", "no check-in for 2 rounds", False),
      (7, "projects/web", "main", "ended", "2 commits; hub commit ok", False),
      (4, "projects/api", "main", "note", "check-in: middleware wired, running the suite", True),
      (3, "projects/docs", "main", "note", "a key %s pasted by mistake" % key, False),
      (2, "projects/mobile", "main", "note", "<b>bold</b> & <script>x()</script>", False)]
with open(os.path.join(S, "events.jsonl"), "w") as f:
    for m, a, b, k, x, c in ev:
        e = {"time": at(m), "from": a, "to": b, "kind": k, "text": x}
        if c: e["checkin"] = True
        f.write(json.dumps(e) + "\n")
ms = os.path.join(S, "monitor-state")
open(os.path.join(ms, "projects-api-monitors-d-uptime-sh.status"), "w").write("ALERT api returns 502 on /health\n")
open(os.path.join(ms, "projects-api-monitors-d-uptime-sh.alert"), "w").write("")
open(os.path.join(ms, "ops-infra-monitors-d-disk-sh.status"), "w").write("disk 41% used\n")
with open(os.path.join(S, "logs", "sync.log"), "w") as f:
    f.write("%s synced: 3 commits\n%s synced: nothing to do\n" % (at(45), at(15)))
day = time.strftime("%Y-%m-%d", time.gmtime(now)); hm = lambda m: time.strftime("%H:%M", time.gmtime(now - m * 60))
with open(os.path.join(H, "journal", day + ".md"), "w") as f:
    f.write("# Journal %s\n\n## %s UTC · hub\n- M1 approved; builder started\n\n## %s UTC · projects/api\n- rate limiter: token bucket per key\n- tests: 14 of 17 green\n\n## %s UTC · projects/web\n- checkout waits on the API\n" % (day, hm(90), hm(30), hm(20)))
PY
  chmod +x "$H/bin/sessions"; : > "$CALLS"
}
# watch_open: the opener's call and the file it was given (the fake copies it to $T/opened.html)
token_in_ps() { ps -ww -eo command 2> /dev/null | grep -F -- "$1" | grep -v -F -e "grep -F" > /dev/null; }

web_loopback_only() {
  acme; local p; p="$(free_port)"; ADE_WEB_PORT="$p" start
  assert_eq "$ADDR:$PORT" "127.0.0.1:$p" "the free default port, on 127.0.0.1"
  assert_eq "$(listeners "$PORT")" "127.0.0.1:$PORT" "listens on 127.0.0.1 only"
  local ip; for ip in $(ifconfig 2> /dev/null | awk '$1 == "inet" && $2 !~ /^127\./ { print $2 }'); do refused "$ip" "$PORT" || fail "answers on $ip"; done
  login
  # DNS rebinding: a page on another name that resolves here names that name in Host; another page's Origin is refused too
  local h; for h in "evil.example:$PORT" "127.0.0.1.nip.io:$PORT" "localhost.:$PORT"; do api "/api/agents" -H "Host: $h"; assert_eq "$CODE" 403 "Host $h"; done
  for h in "http://evil.example" "null" "http://127.0.0.1:1" "https://127.0.0.1:$PORT" "http://localhost:$PORT.evil.example"; do
    api "/api/agents" -H "Origin: $h"; assert_eq "$CODE" 403 "Origin $h"; assert_not_contains "$T/body" "projects/api" "Origin $h gets no data"; done
  api "/api/events" -H "Origin: http://evil.example" -H "Origin: http://127.0.0.1:$PORT"; assert_eq "$CODE" 403 "two Origin headers"
  for h in "http://127.0.0.1:$PORT" "http://localhost:$PORT"; do api "/api/agents" -H "Origin: $h"; assert_eq "$CODE" 200 "Origin $h, the page's own"; done
  stop
  for a in "--bind 0.0.0.0" "--host ::" "--listen 0.0.0.0"; do
    # shellcheck disable=SC2086  # the arguments of one case, split on purpose
    PATH="$WPATH" "$ADE" web $a > "$T/out" 2> "$T/err"; assert_eq "$?" 2 "a non-loopback bind ($a) is refused"; done
}

web_token_required() {
  acme; snapshot > "$T/before"
  # ade opens the page itself: the token is in a 0600 file the opener is given, never on a command line or the terminal
  : > "$T/web.out"; : > "$T/tty.out"; PATH="$WPATH" TMPDIR="$T/tmp" "${TTYRUN[@]}" "$ADE" web > "$T/web.out" 2> "$T/web.err" & SRV=$!
  local i=0; until [ -s "$T/opened.html" ] && grep -q 'open in your browser\|is open in your browser' "$T/web.out"; do
    kill -0 "$SRV" 2> /dev/null || { cat "$T/web.err" >&2; fail "ade web ended before it opened the page"; }
    i=$((i + 1)); [ "$i" -lt 100 ] || { cat "$T/web.out" "$T/web.err" "$CALLS" >&2; ls -la "$T/tmp" >&2; fail "ade web opened nothing in 10 s"; }; sleep 0.1; done
  assert_contains "$T/web.out" "read-only" "says it is read-only"; assert_contains "$T/web.out" "ade web --stop" "says how to stop"
  if grep -q '?k=' "$T/web.out" "$T/web.err"; then fail "the link was printed though the page was opened"; fi
  URL="$(PATH="$WPATH" "$ADE" web --print-link)"; K="${URL##*\?k=}"; BASE="${URL%%/\?k=*}"; PORT="${BASE##*:}"
  [ "${#K}" -ge 32 ] || fail "a short token"
  assert_contains "$T/opened.html" "$URL" "the opened file carries the link"; assert_contains "$T/opened.html" 'name="referrer" content="no-referrer"' "the link is not sent on as a referrer"
  local line; line="$(grep -E '^(open|xdg-open) ' "$CALLS")"; assert_not_contains <(echo "$line") "$K" "the opener's argv has no token"
  local f="${line#* }"; case "$f" in "$T/tmp/"*) ;; *) fail "the link file is not in TMPDIR: $f" ;; esac
  assert_eq "$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777), oct(os.stat(os.path.dirname(sys.argv[1])).st_mode & 0o777))' "$f")" "0o600 0o700" "the link file is 0600 in a 0700 folder"
  if token_in_ps "$K"; then fail "the token is in a process's command line"; fi
  # nothing is read before the token: no hub command has run
  if grep -q '^sessions\|^inbox' "$CALLS"; then fail "a hub command ran before any request"; fi
  local p; for p in "/" "/api/agents" "/api/events" "/api/events?since=" "/api/log?agent=api" "/api/journal" "/api/chat" "/?k=" "/?k=${K%?}" "/api/agents?k=$K"; do
    get "$p"; assert_eq "$CODE" 403 "$p without the cookie"; assert_not_contains "$T/body" "api" "$p: 403 carries no data"; done
  get "/api/agents" -H "X-Ade-Key: $K" -H "Cookie: ade_web_$PORT=$K"; assert_eq "$CODE" 401 "the token is not the cookie (story M2: 401, no session)"
  if grep -q '^sessions\|^inbox' "$CALLS"; then fail "a refused request ran a hub command"; fi
  login; [ ! -e "$f" ] || fail "the link file is kept after the link was used"
  api "/api/agents"; assert_eq "$CODE" 200 "the cookie and the token open the API"; api "/api/events"; assert_eq "$CODE" 200 "and the events"
  # a cookie is not kept to one port (another 127.0.0.1 server the browser visits gets it): alone it opens nothing
  get "/api/agents" -H "Cookie: $CK"; assert_eq "$CODE" 403 "the cookie without the token header"
  get "/api/agents" -H "Cookie: $CK" -H "X-Ade-Key: ${K%?}x"; assert_eq "$CODE" 403 "a wrong token header"
  get "/api/agents" -H "X-Ade-Key: $K"; assert_eq "$CODE" 401 "the token header without the cookie"
  get "/" -H "Cookie: $CK"; assert_eq "$CODE" 200 "the page itself (static) with the cookie"; assert_not_contains "$T/body" "$K" "the page does not carry the token"
  if grep -rqF -- "$K" "$T/web.out" "$T/web.err" "$HOME/.local/share/ade" 2> /dev/null; then fail "the token is in a log"; fi
  stop; [ ! -e "$HOME/.config/ade/web" ] || fail "the link file is left"
  # over SSH (or on Linux without a display) nothing is opened: the link is printed as before
  : > "$CALLS"; : > "$T/tty.out"; SSH_CONNECTION="10.0.0.1 22 10.0.0.2 22" PATH="$WPATH" TMPDIR="$T/tmp" "${TTYRUN[@]}" "$ADE" web > "$T/web.out" 2> "$T/web.err" & SRV=$!
  i=0; until grep -q '^ade web: http://' "$T/web.out"; do i=$((i + 1)); [ "$i" -lt 100 ] || fail "over SSH no link was printed"; sleep 0.1; done
  if grep -qE '^(open|xdg-open) ' "$CALLS"; then fail "a browser was opened over SSH"; fi
  stop
  # a link file never used goes when the server stops
  rm -f "$T/opened.html"; : > "$T/tty.out"; PATH="$WPATH" TMPDIR="$T/tmp" "${TTYRUN[@]}" "$ADE" web > "$T/web.out" 2> "$T/web.err" & SRV=$!
  i=0; until [ -s "$T/opened.html" ] && grep -qE '^(open|xdg-open) ' "$CALLS"; do i=$((i + 1)); [ "$i" -lt 100 ] || fail "nothing opened"; sleep 0.1; done
  stop; [ -z "$(ls -A "$T/tmp")" ] || fail "a link file is left in TMPDIR after the stop: $(ls -A "$T/tmp")"
  snapshot > "$T/after"; cmp -s "$T/before" "$T/after" || fail "the hub changed"
}

web_read_only() {
  acme; snapshot > "$T/before"; start; login
  local m p
  for m in POST PUT DELETE PATCH OPTIONS CONNECT PROPFIND; do for p in "/api/agents" "/api/events?since=" "/api/log?agent=main"; do
    api "$p" -X "$m" -d 'x=1'; assert_eq "$CODE" 405 "$m $p"; assert_not_contains "$T/body" "projects/api" "$m $p carries no data"; done; done
  for p in "/" "/api/agents" "/api/events" "/api/events?since=0-0" "/api/log?agent=main" "/api/log?agent=api" "/api/log?agent=new"; do api "$p"; assert_eq "$CODE" 200 "GET $p"; done
  # the page asks with GET only and never posts a form; its one POST is the code, to /login (story M2)
  api "/"; if grep -Eqi "<form|sendBeacon|WebSocket|EventSource" "$T/body"; then fail "the page can send something other than a GET"; fi
  assert_eq "$(grep -Eoi "method *: *['\"](post|put|delete|patch)" "$T/body" | wc -l | tr -d ' ')" 1 "the page has one request that is not a GET"
  assert_contains "$T/body" 'fetch("/login", {method: "POST"' "and it is the code, to /login"
  stop; snapshot > "$T/after"
  cmp -s "$T/before" "$T/after" || { diff "$T/before" "$T/after" >&2; fail "the hub or its state folder changed"; }
  assert_eq "$(sort -u "$CALLS" | tr '\n' ';')" "inbox --count main;sessions ;" "the only hub commands are bin/sessions and bin/inbox --count main"
}

web_agents_json() {
  acme; start; login; api "/api/agents"; assert_eq "$CODE" 200 "/api/agents"
  assert_eq "$(json '[a["name"] for a in d["agents"]]')" "['main', 'api', 'web', 'docs', 'mobile', 'new', 'infra', 'billing']" "the orchestrator, then bin/sessions"
  assert_eq "$(json '[a["state"] for a in d["agents"]]')" "['unknown', 'busy', 'idle', 'ready', 'busy', 'starting', 'blocked', 'quiet']" "each agent's state"
  assert_eq "$(json '[a["orchestrator"] for a in d["agents"]][:2]')" "[True, False]" "main is the orchestrator"
  assert_eq "$(json 'd["agents"][0]["line"]')" "orchestrating M1 review; K3 gate running" "main's STATE line"
  assert_eq "$(json 'd["agents"][1]["line"]')" "rate limiter: tests green, wiring the middleware" "api's last STATE line"
  assert_eq "$(json '" ".join([d["agents"][1][k] for k in ("folder", "role", "engine")])')" "projects/api builder claude" "api's folder, role, engine"
  assert_eq "$(json 'd["now"] - d["agents"][1]["checkin"] in range(235, 300)')" True "api's check-in time (4 min ago)"
  assert_eq "$(json '[a["name"] for a in d["agents"] if a["checkin"]]')" "['api']" "only api checked in"
  assert_eq "$(json 'd["now"] - d["agents"][6]["since"] in range(2030, 2100)')" True "infra blocked since its blocked event"
  assert_eq "$(json 'd["counts"]["busy"], d["counts"]["quiet"], d["counts"]["blocked"]')" "(2, 1, 1)" "a count per state"
  assert_eq "$(json 'd["monitor"]["checks"], d["monitor"]["alerting"]')" "(2, 1)" "the monitor health"
  assert_eq "$(json 'd["sync"]["text"]')" "synced: nothing to do" "the last sync"; assert_eq "$(json 'd["unread"]')" 2 "unread to main"
  flat; assert_not_contains "$T/text" "$S_SKD" "a key in a STATE line"; assert_contains "$T/text" "key <hidden" "the line is kept, the key hidden"
  assert_not_contains "$T/body" 5101 "no process id is served"
  # the detail of an agent: its STATE.md, its journal entries, the command to act on it
  api "/api/log?agent=api"; assert_eq "$(json 'd["commands"]')" "['ade work projects/api', 'ade ui']" "the commands for api"
  assert_eq "$(json '[l.split("  ", 1)[1].strip() for l in d["journal"]]')" "['- rate limiter: token bucket per key', '- tests: 14 of 17 green']" "api's journal lines"
  api "/api/log?agent=main"; assert_eq "$(json 'd["commands"]')" "['ade claude', 'ade ui']" "the commands for main"
  assert_eq "$(json '[l.split("  ", 1)[1].strip() for l in d["journal"]]')" "['- M1 approved; builder started']" "the hub's journal for main"
  stop
}

web_events_json() {
  acme; start; login
  api "/api/events"; assert_eq "$(json 'd["reset"], len(d["events"])')" "(True, 11)" "the first ask: the whole log"
  assert_eq "$(json '[e["kind"] for e in d["events"]][:3]')" "['pushed', 'blocked', 'note']" "in order"
  assert_eq "$(json '[e["text"] for e in d["events"] if e["checkin"]]')" "['check-in: middleware half done, 3 tests left', 'check-in: middleware wired, running the suite']" "check-ins are marked"
  assert_eq "$(json '[s["text"] for s in d["syncs"]]')" "['synced: 3 commits', 'synced: nothing to do']" "the last syncs"
  flat; assert_not_contains "$T/text" "$S_SKD" "a key in an event"; assert_contains "$T/text" "a key <hidden" "the event's words kept"
  assert_contains "$T/text" "<b>bold</b> & <script>x()</script>" "the text is served as it is, as data"
  if grep -q '<script\|<b>' "$T/body"; then fail "a tag is spelled out in the JSON"; fi
  local c; c="$(json 'd["cursor"]')"
  api "/api/events?since=$c"; assert_eq "$(json 'd["reset"], d["events"]')" "(False, [])" "nothing new"
  printf '{"time":"%s","from":"projects/web","to":"main","kind":"note","text":"new one"}\nnot json\n{"time":"x","from":"main","to":"all","kind":"note","text":"two"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$S/events.jsonl"
  api "/api/events?since=$c"; assert_eq "$(json '[e["text"] for e in d["events"]], d["reset"]')" "(['new one', 'two'], False)" "only what came after the cursor"
  local c2; c2="$(json 'd["cursor"]')"; [ "$c2" != "$c" ] || fail "the cursor did not move"
  # a half-written last line waits for its end
  printf '{"time":"t","from":"main","to":"all","kind":"note","text":"half' >> "$S/events.jsonl"
  api "/api/events?since=$c2"; assert_eq "$(json 'd["events"], d["cursor"]')" "([], '$c2')" "a line not yet ended"
  printf ' done"}\n' >> "$S/events.jsonl"; api "/api/events?since=$c2"; assert_eq "$(json '[e["text"] for e in d["events"]]')" "['half done']" "then the whole line"
  # a bad cursor, one past the end, or a rotated log: the last entries again, reset
  for c in "x" "1-2-3" "${c2%-*}-99999999" "0-0" "-1" "$(rep 9 30)-0"; do api "/api/events?since=$c"; assert_eq "$CODE" 200 "since=$c"; assert_eq "$(json 'd["reset"]')" True "since=$c resets"; done
  api "/api/events?since=a&since=b"; assert_eq "$CODE" 404 "two cursors"
  mv "$S/events.jsonl" "$S/events.jsonl.1"; echo '{"time":"t","from":"main","to":"all","kind":"note","text":"after rotation"}' > "$S/events.jsonl"
  api "/api/events?since=$c2"; assert_eq "$(json '[e["text"] for e in d["events"]], d["reset"]')" "(['after rotation'], True)" "a rotated log starts over"
  # a big log: at most 200 entries, the newest
  python3 -c 'import json, sys
with open(sys.argv[1], "a") as f:
    for i in range(3000): f.write(json.dumps({"time": "t", "from": "main", "to": "all", "kind": "note", "text": "n%d" % i}) + "\n")' "$S/events.jsonl"
  api "/api/events"; assert_eq "$(json 'len(d["events"]), d["events"][-1]["text"]')" "(200, 'n2999')" "the newest 200"
  # the page shows hub text as text only
  api "/"; if grep -Eq 'innerHTML|outerHTML|insertAdjacentHTML|document\.write|eval\(|new Function' "$T/body"; then fail "the page can insert HTML"; fi
  stop
}

web_alerts() {
  acme; start; login; api "/api/agents"
  assert_eq "$(json 'sorted(set(a["kind"] for a in d["alerts"]))')" "['monitor', 'prompt', 'quiet', 'unread']" "the four kinds"
  assert_eq "$(json '[a["agent"] for a in d["alerts"] if a["kind"] == "prompt"]')" "['mobile', 'new']" "busy with an old time, and not started"
  assert_eq "$(json '[__import__("re").sub(r"[0-9]{2}:[0-9]{2}Z", "HH:MMZ", a["text"]) for a in d["alerts"] if a["kind"] == "quiet"]')" "['billing is quiet: no check-in for 25m (since HH:MMZ)']" "the quiet agent (story M3: counted from its last event)"
  assert_eq "$(json '[a["text"] for a in d["alerts"] if a["kind"] == "monitor"]')" "['monitor projects-api / uptime-sh: ALERT api returns 502 on /health']" "the monitor ALERT"
  assert_eq "$(json '[a["text"] for a in d["alerts"] if a["kind"] == "unread"]')" "['2 unread notes to main']" "unread notes to main"
  stop
  # a hub without check-ins, monitors, a sync log or bin/inbox: no alert, no error
  rm -rf "$S/monitor-state" "$S/logs/sync.log" "$H/bin/inbox"; grep -v '"quiet"\|"blocked"\|checkin' "$S/events.jsonl" > "$T/e" && mv "$T/e" "$S/events.jsonl"
  printf '#!/bin/bash\nprintf "NAME FOLDER PID PARENT STARTED ROLE STATUS LAST ENGINE\\napi projects/api 1 - %s builder idle %s claude\\n"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$H/bin/sessions"
  start; login; api "/api/agents"; assert_eq "$CODE" 200 "a plain hub"
  assert_eq "$(json 'd["alerts"], d["unread"], d["sync"], d["monitor"]["checks"]')" "([], None, None, 0)" "no alert and no error"
  assert_eq "$(json '[a["checkin"] for a in d["agents"]]')" "[None, None]" "no check-in is shown"
  stop
}

# the browser checks: Playwright's Chromium (the real HOME's, as `ade shot` finds it); skipped when there is none,
# unless ADE_WEB_REQUIRE_BROWSER=1
browser_ok() {
  local found; found="$(python3 - "$REAL_HOME" <<'PY'
import glob, os, sys
env = os.environ.get("PLAYWRIGHT_BROWSERS_PATH")
bases = [env] if env else [os.path.join(sys.argv[1], ".cache/ms-playwright"), os.path.join(sys.argv[1], "Library/Caches/ms-playwright"), "/opt/ms-playwright"]
for b in bases:
    for pat in ("chromium-*/chrome-linux*/chrome", "chromium-*/chrome-mac*/Chromium.app/Contents/MacOS/Chromium",
                "chromium-*/chrome-mac*/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"):
        for c in sorted(glob.glob(os.path.join(glob.escape(b), pat)), reverse=True):
            if os.access(c, os.X_OK): print(b); print(c); sys.exit(0)
PY
)"
  if [ -n "$found" ]; then BROWSERS="$(echo "$found" | head -1)"; CHROME="$(echo "$found" | tail -1)"; return 0; fi
  [ "${ADE_WEB_REQUIRE_BROWSER:-}" != 1 ] || fail "no Chromium for the browser checks (ADE_WEB_REQUIRE_BROWSER=1)"
  echo "skip: $1 (no Playwright Chromium)"; return 1
}

web_page_renders() {
  acme; start --port "$(free_port)"; login
  # one document: every asset inline; no address but its own API
  api "/"; if grep -Eqi 'https?://|//[a-z0-9.-]+\.[a-z]{2,}|<link|@import|src=' "$T/body"; then fail "the page names an outside address or file"; fi
  if grep -Eo 'url\([^)]{0,30}' "$T/body" | grep -v '^url(data:font/woff2;base64,'; then fail "a url() that is not the inline font"; fi
  grep -qi "^content-security-policy: default-src 'none'; .*font-src data:; connect-src 'self'" "$T/head" || fail "the page's policy allows more than its own API and the inline font"
  local s; for s in "prefers-color-scheme: light" "prefers-reduced-motion: reduce" "max-width: 720px" "●" "○" "◐" "▲" "✖" '"agents"' '"events"' "j k"; do assert_contains "$T/body" "$s" "the page has $s"; done
  browser_ok web_page_renders || { stop; return 0; }
  mkdir -p "$T/shotrepo"; git -C "$T/shotrepo" init -q
  # ade shot captures 0.3 s after load; a cold bin/sessions (bash) can take longer, so keep the server's 2 s list fresh
  ( while curl -q -s -f -o /dev/null --max-time 5 -H "Cookie: $CK" -H "X-Ade-Key: $K" "$BASE/api/agents"; do sleep 1; done ) & local warm=$!   # ends with the server
  local mode w; for mode in wide phone; do
    w=1280; [ "$mode" = phone ] && w=375
    ( cd "$T/shotrepo" && PATH="$WPATH" PLAYWRIGHT_BROWSERS_PATH="$BROWSERS" "$ADE" shot url "$URL" --name "web-$mode" --width "$w" > "$T/shot.out" 2>&1 ) || { cat "$T/shot.out" >&2; fail "ade shot of the page ($mode)"; }
  done
  kill "$warm" 2> /dev/null; wait "$warm" 2> /dev/null
  local png; png="$(find "$T/shotrepo/.ade/evidence" -name '*-web-wide.png' | head -1)"; [ -f "$png" ] && [ -n "$(find "$T/shotrepo/.ade/evidence" -name '*-web-phone.png')" ] || fail "no shot saved"
  # story M2: the link alone shows the code prompt, never the cards: the theme's ground, and no pixel of the busy or idle
  # colours (ade ui's tokens; the dashboard behind the code is checked in a browser by web_premium_checks)
  python3 - "$png" <<'PY' || fail "the shot does not show the code prompt alone"
import struct, sys, zlib
raw = open(sys.argv[1], "rb").read(); assert raw[:8] == b"\x89PNG\r\n\x1a\n"
i = 8; idat = b""; w = h = 0
while i < len(raw):
    n, t = struct.unpack(">I4s", raw[i:i + 8]); body = raw[i + 8:i + 8 + n]; i += 12 + n
    if t == b"IHDR": w, h, depth, ctype = struct.unpack(">IIBB", body[:10]); assert depth == 8 and ctype in (2, 6)
    elif t == b"IDAT": idat += body
bpp = 3 if ctype == 2 else 4; data = zlib.decompress(idat); stride = w * bpp; prev = bytearray(stride); px = []; o = 0
for y in range(h):
    f = data[o]; line = bytearray(data[o + 1:o + 1 + stride]); o += 1 + stride
    for x in range(stride):
        a = line[x - bpp] if x >= bpp else 0; b = prev[x]; c = prev[x - bpp] if x >= bpp else 0
        if f == 1: line[x] = (line[x] + a) & 255
        elif f == 2: line[x] = (line[x] + b) & 255
        elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
        elif f == 4:
            p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    px.append(line); prev = line
def near(rgb, d=40):
    n = 0
    for line in px:
        for x in range(0, len(line), bpp):
            if abs(line[x] - rgb[0]) + abs(line[x + 1] - rgb[1]) + abs(line[x + 2] - rgb[2]) < d: n += 1
    return n
counts = {k: near(v) for k, v in {"bg": (0x1e, 0x1e, 0x2e), "busy": (0xf9, 0xe2, 0xaf), "idle": (0xa6, 0xe3, 0xa1), "orch": (0xcb, 0xa6, 0xf7)}.items()}
assert counts["bg"] > w * h // 4, counts
assert all(counts[k] < 50 for k in ("busy", "idle")), counts
PY
  stop
}

web_stops_cleanly() {
  acme; local L="$HOME/.config/ade/web"
  PATH="$WPATH" "$ADE" web --stop > "$T/out" 2> "$T/err"; assert_eq "$?" 0 "--stop with nothing running"; assert_contains "$T/out" "not running" "says so"
  for a in "--stop --port 1" "--stop extra" "--stop --print-link"; do
    # shellcheck disable=SC2086  # the arguments of one case, split on purpose
    PATH="$WPATH" "$ADE" web $a > "$T/out" 2> "$T/err"; assert_eq "$?" 2 "ade web $a is a usage error"; done
  # --stop: the server ends, its link file and its port are gone
  start; login; local old="$CK" port="$PORT" pid="$SRV"
  PATH="$WPATH" "$ADE" web --stop > "$T/out" 2> "$T/err"; assert_eq "$?" 0 "--stop"; assert_contains "$T/out" "stopped" "says it stopped"
  # $pid is the test's terminal harness: --stop waits for the server itself, the harness ends a moment after it
  local i=0; while kill -0 "$pid" 2> /dev/null; do i=$((i + 1)); [ "$i" -lt 50 ] || fail "the server still runs after --stop"; sleep 0.1; done
  wait "$SRV" 2> /dev/null; SRV=""
  [ ! -e "$L" ] || fail "the link file is left after --stop"; refused 127.0.0.1 "$port" || fail "the port still answers"
  # started again on the same port: nothing stale is reused; the old cookie and link are refused
  start; CK="$old"; api "/api/agents"; assert_eq "$CODE" 401 "the old cookie after a restart (story M2: 401, no session)"
  [ "$(PATH="$WPATH" "$ADE" web --print-link)" = "$URL" ] || fail "--print-link after the restart"
  # --stop never signals a process that is not this user's ade web (a link file naming another pid)
  stop; sleep 30 & local other=$!
  mkdir -p "$(dirname "$L")"; printf '%s\nhttp://127.0.0.1:%s/?k=x\n' "$other" "$(free_port)" > "$L"
  PATH="$WPATH" "$ADE" web --stop > "$T/out" 2> "$T/err"; kill -0 "$other" 2> /dev/null || fail "--stop killed a process that is not ade web"
  kill "$other"; wait "$other" 2> /dev/null; rm -f "$L"
  # Ctrl-C at a terminal (ade opens the page: the fake opener): stops, exit 0, no link file or opener file left
  rm -f "$T/opened.html"
  PATH="$WPATH" TMPDIR="$T/tmp" python3 - "$ADE" "$L" "$T/opened.html" <<'PY' || fail "Ctrl-C did not stop ade web cleanly"
import os, pty, select, signal, sys, time
pid, fd = pty.fork()
if pid == 0:
    signal.signal(signal.SIGINT, signal.SIG_DFL)   # a suite started in the background hands down an ignored SIGINT; a terminal does not
    os.execv(sys.argv[1], [sys.argv[1], "web"])
buf = b""; end = time.time() + 15
while b"Ctrl-C" not in buf and time.time() < end:
    if select.select([fd], [], [], 0.2)[0]:
        try: buf += os.read(fd, 4096)
        except OSError: break
assert b"open in your browser" in buf, buf
assert os.path.exists(sys.argv[2]), "no link file while running"
while not os.path.exists(sys.argv[3]) and time.time() < end: time.sleep(0.1)   # the (fake) browser has had the page
os.write(fd, b"\x03"); end = time.time() + 10; st = None
while time.time() < end:
    got, st = os.waitpid(pid, os.WNOHANG)
    if got: break
    if select.select([fd], [], [], 0.1)[0]:
        try: buf += os.read(fd, 4096)
        except OSError: pass
else:
    os.kill(pid, 9); raise SystemExit("still running 10 s after Ctrl-C")
assert os.WIFEXITED(st) and os.WEXITSTATUS(st) == 0, st
assert not os.path.exists(sys.argv[2]), "the link file is left after Ctrl-C"
assert b"Traceback" not in buf, buf
PY
  [ -z "$(ls -A "$T/tmp")" ] || fail "the opener's file is left after Ctrl-C"
  start; stop
}

web_no_hub_writes() {
  acme; snapshot > "$T/before"
  start; login
  local p i; for i in 1 2; do for p in "/" "/api/agents" "/api/events" "/api/events?since=1-1" "/api/log?agent=main" "/api/log?agent=api" "/api/log?agent=infra" "/api/journal" "/api/chat"; do api "$p"; done; sleep 2.1; done
  stop; snapshot > "$T/after"
  cmp -s "$T/before" "$T/after" || { diff "$T/before" "$T/after" >&2; fail "the hub or its state folder changed"; }
  # this HOME: the link file came and went, the theme was only read
  [ -z "$(ls -A "$HOME/.config/ade" 2> /dev/null)" ] || fail "something is left in ~/.config/ade: $(ls -A "$HOME/.config/ade")"
  # the real ~/.config/ade: no entry added, its web link untouched (ade ui may rewrite its own cache meanwhile)
  assert_eq "$(real_conf)" "$REAL_CONF" "the real ~/.config/ade"
}
real_conf() { ls -A "$REAL_HOME/.config/ade" 2> /dev/null | grep -v '^ui-'; cksum "$REAL_HOME/.config/ade/web" 2> /dev/null; }

# cdp_lib: the Python the browser checks start with: a headless Chromium on a DevTools pipe (argv: the browser, the
# page's address, this test's folder, the folder for screenshots); call, js, settle, key and the contrast check
cdp_lib() { cat <<'PY'
import base64, json, os, re, select, subprocess, sys, tempfile, time
exe, url, tmp, shots = sys.argv[1:5]; origin = url.split("/?", 1)[0]; os.makedirs(shots, exist_ok=True)
r_in, w_in = os.pipe(); r_out, w_out = os.pipe()
args = [exe, "--headless", "--remote-debugging-pipe", "--user-data-dir=" + tempfile.mkdtemp(dir=tmp), "--no-first-run", "--disable-gpu",
        "--hide-scrollbars", "--disable-extensions", "--disable-background-networking", "--disable-sync", "--disable-component-update"]
if sys.platform == "darwin": args += ["--use-mock-keychain", "--password-store=basic"]
elif os.geteuid() == 0 or subprocess.call(["unshare", "-U", "true"], stderr=subprocess.DEVNULL) != 0: args.append("--no-sandbox")
def child(): os.dup2(r_in, 3); os.dup2(w_out, 4)
p = subprocess.Popen(args + ["about:blank"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, pass_fds=(3, 4), preexec_fn=child, start_new_session=True)
os.close(r_in); os.close(w_out); n = [0]; buf = bytearray(); sess = [None]; reqs = []; deadline = time.time() + 90
def send(m, prm=None):
    n[0] += 1; msg = {"id": n[0], "method": m, "params": prm or {}}
    if sess[0] and not m.startswith("Target."): msg["sessionId"] = sess[0]
    os.write(w_in, json.dumps(msg).encode() + b"\0"); return n[0]
def read(until):
    while True:
        i = buf.find(b"\0")
        if i >= 0:
            raw = bytes(buf[:i]); del buf[:i + 1]; return json.loads(raw)
        if not select.select([r_out], [], [], max(0, until - time.time()))[0]: raise SystemExit("the browser did not answer")
        b = os.read(r_out, 1 << 20)
        if not b: raise SystemExit("the browser closed")
        buf.extend(b)
def event(m):
    if m.get("method") == "Network.requestWillBeSent": reqs.append(m["params"]["request"]["url"])
def call(m, prm=None):
    i = send(m, prm)
    while True:
        r = read(deadline)
        if r.get("id") == i:
            if "error" in r: raise SystemExit("%s: %s" % (m, r["error"]))
            return r.get("result", {})
        event(r)
def settle(s):
    end = time.time() + s
    while time.time() < end:
        try:
            i = buf.find(b"\0")
            if i < 0 and not select.select([r_out], [], [], max(0, end - time.time()))[0]: break
            event(read(end + 5))
        except SystemExit: break
def js(expr): return call("Runtime.evaluate", {"expression": expr, "returnByValue": True, "awaitPromise": True}).get("result", {}).get("value")
CONTRAST = r"""(function(){
 function rgb(s){var m=s.match(/[\d.]+/g);return m?m.map(Number):[0,0,0,0]}
 function lum(c){var v=c.slice(0,3).map(function(x){x/=255;return x<=0.03928?x/12.92:Math.pow((x+0.055)/1.055,2.4)});return 0.2126*v[0]+0.7152*v[1]+0.0722*v[2]}
 function bg(e){for(;e;e=e.parentElement){var c=rgb(getComputedStyle(e).backgroundColor);if(c.length<4||c[3]>0.5)return c}return rgb(getComputedStyle(document.body).backgroundColor)}
 var bad=[],n=0,w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT),t;
 while((t=w.nextNode())){var e=t.parentElement;if(!t.nodeValue.trim()||!e||/^[\s\u2500-\u259f]*$/.test(t.nodeValue))continue;var s=getComputedStyle(e);
  if(s.visibility!=="visible"||s.display==="none"||e.getClientRects().length===0||parseFloat(s.opacity)<0.5)continue;
  var r=e.getBoundingClientRect();if(r.width===0||r.height===0)continue;
  var f=rgb(s.color),b=bg(e),a=lum(f),c=lum(b),k=(Math.max(a,c)+0.05)/(Math.min(a,c)+0.05);n++;
  if(k<4.5)bad.push(k.toFixed(2)+" "+s.color+" on "+getComputedStyle(e).backgroundColor+": "+t.nodeValue.trim().slice(0,30))}
 return JSON.stringify({n:n,bad:bad.slice(0,12)})})()"""
def key(k, code):
    vk = ord(k.upper()) if len(k) == 1 else {"Enter": 13, "Escape": 27}[k]
    for ty in ("keyDown", "keyUp"): call("Input.dispatchKeyEvent", {"type": ty, "key": k, "code": code, "text": (k if len(k) == 1 else "\r" if k == "Enter" else "") if ty == "keyDown" else "", "windowsVirtualKeyCode": vk})
def type_text(t): call("Input.insertText", {"text": t})
# story M2: ade web's terminal (the test's pseudo-terminal): the last code it showed, and Enter typed into it
def tty_code(old=None):
    end = time.time() + 10
    while time.time() < end:
        found = re.findall(r"ade web: the code for the page: ([A-Za-z0-9]+)", open(os.path.join(tmp, "tty.out"), "rb").read().decode("utf-8", "replace"))
        if found and found[-1] != old: return found[-1]
        time.sleep(0.1)
    raise SystemExit("no code on ade web's terminal")
def tty_enter(): open(os.path.join(tmp, "tty.in"), "ab").write(b"\n")
def close():
    try: send("Browser.close")
    except OSError: pass
    try: p.wait(5)
    except subprocess.TimeoutExpired: p.kill()
PY
}
web_premium_checks() {
  acme; start --port "$(free_port)"
  browser_ok web_premium_checks || { stop; return 0; }
  { cdp_lib; cat <<'PY'; } | python3 - "$CHROME" "$URL" "$T" "${ADE_WEB_SHOTS:-$T/shots}" || fail "the design checks"
try:
    t = call("Target.createTarget", {"url": "about:blank"})["targetId"]
    sess[0] = call("Target.attachToTarget", {"targetId": t, "flatten": True})["sessionId"]
    call("Page.enable"); call("Network.enable"); call("Runtime.enable")
    # story M2: the link opens on the code prompt; the code from ade web's terminal opens the dashboard in this browser
    call("Page.navigate", {"url": url}); settle(2); type_text(tty_code()); key("Enter", "Enter"); settle(1)
    errs = []
    for name, w, h, scheme in (("dark", 1440, 900, "dark"), ("light", 1440, 900, "light"), ("phone", 375, 812, "dark")):
        call("Emulation.setDeviceMetricsOverride", {"width": w, "height": h, "deviceScaleFactor": 2, "mobile": name == "phone"})
        call("Emulation.setEmulatedMedia", {"features": [{"name": "prefers-color-scheme", "value": scheme}, {"name": "prefers-reduced-motion", "value": "no-preference"}]})
        call("Page.navigate", {"url": url}); settle(4)
        rows = js("document.querySelectorAll('#rows > *').length")
        if not rows or rows < 8: errs.append("%s: %s agent rows" % (name, rows))
        c = json.loads(js(CONTRAST))
        if c["n"] < 40 or c["bad"]: errs.append("%s: contrast below 4.5:1 (%d texts): %s" % (name, c["n"], c["bad"]))
        sw = js("Math.max(document.documentElement.scrollWidth, document.body.scrollWidth)")
        if sw > w: errs.append("%s: scrolls sideways (%s > %s)" % (name, sw, w))
        if not js("document.getAnimations().length"): errs.append("%s: no animation without reduced motion" % name)
        fam = js("document.fonts.check('12px \"JetBrains Mono\"') && [...document.fonts].some(f => f.status === 'loaded')")
        if not fam: errs.append("%s: the inline font did not load" % name)
        shot = call("Page.captureScreenshot", {"format": "png"})["data"]
        open(os.path.join(shots, "ade-web-%s.png" % name), "wb").write(base64.b64decode(shot))
    # reduced motion: every animation off
    call("Emulation.setEmulatedMedia", {"features": [{"name": "prefers-reduced-motion", "value": "reduce"}]}); settle(1)
    left = js("document.getAnimations().length")
    if left: errs.append("reduced motion: %d animations still run" % left)
    # the keyboard: j moves the selection, / opens the filter, ? the help, Esc closes it
    call("Emulation.setDeviceMetricsOverride", {"width": 1440, "height": 900, "deviceScaleFactor": 1, "mobile": False})
    sel0 = js("(document.querySelector('#rows [aria-selected=true]')||{}).textContent||''")
    key("j", "KeyJ"); settle(0.3); sel1 = js("(document.querySelector('#rows [aria-selected=true]')||{}).textContent||''")
    if not sel1 or sel1 == sel0: errs.append("j did not move the selection")
    key("?", "Slash"); settle(0.3)
    if js("getComputedStyle(document.getElementById('help')).display") == "none": errs.append("? shows no help")
    key("Escape", "Escape"); settle(0.3)
    if js("getComputedStyle(document.getElementById('help')).display") != "none": errs.append("Esc does not close the help")
    out = [u for u in reqs if not (u.startswith(origin + "/") or u.startswith("data:"))]
    if out: errs.append("requests that leave the page's origin: %s" % out[:5])
    if errs: raise SystemExit("; ".join(errs))
finally:
    close()
PY
  local s; for s in dark light phone; do [ -s "${ADE_WEB_SHOTS:-$T/shots}/ade-web-$s.png" ] || fail "no $s screenshot"; done
  stop
}

# --- story M2: the link alone is not enough; the page asks for the code ade web shows in its own terminal ---

# tty_has <text>: wait (up to 10 s) until ade web's terminal shows the text
tty_has() { local i=0; until tr -d '\r' < "$T/tty.out" | grep -qF -- "$1"; do i=$((i + 1)); [ "$i" -lt 100 ] || fail "ade web's terminal never showed: $1"; sleep 0.1; done; }
# login_post <json> [curl args]: POST /login with each header given (none added), so each refusal shows what it alone lacks
login_post() { local b="$1"; shift; get "/login" -X POST "$@" --data-binary "$b"; }
WRONG='{"code": "WRONGXYZ"}'   # never a code: O is not in the alphabet

code_required() {
  acme; snapshot > "$T/before"; start
  get "/?k=$K"; assert_eq "$CODE" 200 "the link"
  assert_contains "$T/body" 'data-gate="code"' "the link alone shows the code prompt"
  assert_contains "$T/body" "enter the code shown in your terminal" "the prompt asks for the code"
  [ -z "$(set_cookie)" ] || fail "the link alone set a cookie"
  local p; for p in "/api/agents" "/api/events" "/api/events?since=" "/api/log?agent=api" "/api/journal" "/api/chat" "/api/nope"; do
    get "$p" -H "X-Ade-Key: $K"; assert_eq "$CODE" 401 "$p with the token header but no code"
    assert_not_contains "$T/body" "projects/" "$p: 401 carries no data"; assert_not_contains "$T/body" "chat line" "$p: 401 carries no log"
    get "$p" -H "X-Ade-Key: $K" -H "Cookie: ade_web_$PORT=$K"; assert_eq "$CODE" 401 "$p with the token as the cookie"
    get "$p"; assert_eq "$CODE" 403 "$p without the token header"; done
  get "/"; assert_eq "$CODE" 403 "/ with neither the link nor a session"
  get "/" -H "Cookie: ade_web_$PORT=$K"; assert_eq "$CODE" 403 "/ with the token as the cookie"
  if grep -q '^sessions\|^inbox' "$CALLS"; then fail "a hub command ran before the code"; fi
  stop; snapshot > "$T/after"; cmp -s "$T/before" "$T/after" || fail "the hub changed"
}

code_unlocks() {
  acme; start; get "/?k=$K"
  local c; c="$(tty_code)"; local good="{\"code\": \"$c\"}" o="Origin: $BASE" k="X-Ade-Key: $K" j="Content-Type: application/json"
  # refused before the code is looked at: none of these counts as a wrong try
  login_post "$good" -H "$k" -H "$j"; assert_eq "$CODE" 403 "/login without an Origin"
  login_post "$good" -H "Origin: http://evil.example:$PORT" -H "$k" -H "$j"; assert_eq "$CODE" 403 "/login from another Origin"
  login_post "$good" -H "$o" -H "$o" -H "$k" -H "$j"; assert_eq "$CODE" 403 "/login with two Origins"
  login_post "$good" -H "$o" -H "$j"; assert_eq "$CODE" 403 "/login without the token header"
  login_post "$good" -H "$o" -H "X-Ade-Key: ${K%?}x" -H "$j"; assert_eq "$CODE" 403 "/login with a wrong token header"
  login_post "$good" -H "Host: evil.example:$PORT" -H "$o" -H "$k" -H "$j"; assert_eq "$CODE" 403 "/login to another Host"
  login_post "$good" -H "$o" -H "$k" -H "$j" -H "Sec-Fetch-Site: cross-site"; assert_eq "$CODE" 403 "/login from another site"
  login_post "code=$c" -H "$o" -H "$k"; assert_eq "$CODE" 415 "/login as a form"
  login_post "{\"code\": \"$(rep x 2000)\"}" -H "$o" -H "$k" -H "$j"; assert_eq "$CODE" 413 "/login with a long body"
  login_post "not json" -H "$o" -H "$k" -H "$j"; assert_eq "$CODE" 400 "/login with a body that is not JSON"
  login_post '["x"]' -H "$o" -H "$k" -H "$j"; assert_eq "$CODE" 400 "/login with JSON that is not an object"
  [ -z "$(set_cookie)" ] || fail "a refused /login set a cookie"
  post "$WRONG"; assert_eq "$CODE" 401 "a wrong code"; assert_eq "$(json 'd["left"]')" 4 "the refusals before were not wrong tries"
  [ -z "$(set_cookie)" ] || fail "a wrong code set a cookie"
  # the right code: a session; the dashboard and the API as in M1
  post "$good"; assert_eq "$CODE" 200 "the right code"; assert_eq "$(json 'd["ok"]')" True "says ok"; CK="$(set_cookie)"
  [ -n "$CK" ] || fail "the right code set no cookie"
  # review fix: a code opens one page only (a screen share that showed it opens nothing later); ade web says a page
  # signed in and shows the next code. The code is read without case, spaces or dashes.
  tty_has "a page signed in"; local c2; c2="$(tty_code "$c")"
  post "$good"; assert_eq "$CODE" 401 "a code already used"
  post "{\"code\": \" $(printf '%s' "$c2" | tr 'A-Z' 'a-z' | sed 's/..../&-/')\"}"; assert_eq "$CODE" 200 "the next code, in lower case with a dash"
  api "/api/agents"; assert_eq "$CODE" 200 "the API with the session"; api "/api/chat"; assert_eq "$CODE" 200 "the chat with the session"
  api "/"; assert_eq "$CODE" 200 "the page with the session"; assert_contains "$T/body" 'data-gate="open"' "the page opens on the dashboard"
  get "/" -H "Cookie: $CK"; assert_eq "$CODE" 200 "the page with the session alone"; assert_contains "$T/body" 'data-gate="open"' "open again"
  # M1's checks still hold with a session
  api "/api/agents" -H "Origin: http://evil.example:$PORT"; assert_eq "$CODE" 403 "another Origin with a session"
  api "/api/agents" -H "Host: evil.example:$PORT"; assert_eq "$CODE" 403 "another Host with a session"
  get "/api/agents" -H "Cookie: $CK"; assert_eq "$CODE" 403 "the session without the token header"
  get "/api/agents" -H "Cookie: $CK" -H "X-Ade-Key: ${K%?}x"; assert_eq "$CODE" 403 "the session with a wrong token header"
  api "/api/agents" -H "Sec-Fetch-Site: cross-site"; assert_eq "$CODE" 403 "another site with a session"
  # /login is the only route that is not GET, and it takes POST only
  local m; for m in GET PUT DELETE PATCH; do
    api "/login" -X "$m"; [ "$m" = GET ] && { assert_eq "$CODE" 404 "GET /login"; continue; }
    assert_eq "$CODE" 405 "$m /login"; grep -qi '^allow: POST' "$T/head" || fail "$m /login: Allow is not POST"; done
  api "/api/agents" -X POST -d 'x=1'; assert_eq "$CODE" 405 "POST on the API"; grep -qi '^allow: GET' "$T/head" || fail "the API's Allow is not GET"
  stop
}

code_shown_on_terminal_only() {
  acme; start; local c; c="$(tty_code)"
  [[ "$c" =~ ^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$ ]] || fail "the code is not 8 characters without look-alikes: $c"
  if grep -qF -- "$c" "$T/web.out" "$T/web.err"; then fail "the code is on stdout or stderr"; fi
  if token_in_ps "$c"; then fail "the code is in a process's command line"; fi
  get "/?k=$K"; assert_not_contains "$T/body" "$c" "the page does not carry the code"
  login; api "/"; assert_not_contains "$T/body" "$c" "nor does the open page"
  api "/api/agents"; assert_not_contains "$T/body" "$c" "nor the API"; assert_not_contains "$T/head" "$c" "nor a header"
  stop
  if grep -rlF --exclude=tty.out -- "$c" "$T" "$HOME" 2> /dev/null; then fail "the code is in a file"; fi
  # made by secrets from the alphabet, compared with hmac.compare_digest
  grep -qF 'ALPHA = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"' "$ADE" || fail "the alphabet"
  grep -qF 'secrets.choice(ALPHA)' "$ADE" || fail "the code is not from secrets"
  grep -qF 'hmac.compare_digest(typed' "$ADE" || fail "the code is not compared in constant time"
  # no terminal (a new session, as in an agent's shell or a pipe): refused, exit 2, nothing listens
  local p; p="$(free_port)"
  PATH="$WPATH" TMPDIR="$T/tmp" python3 -I -c 'import subprocess, sys; sys.exit(subprocess.call(sys.argv[1:], start_new_session=True, stdin=subprocess.DEVNULL))' \
    "$ADE" web --no-open --port "$p" > "$T/out" 2> "$T/err" & local nt=$!
  ( sleep 10; kill "$nt" 2> /dev/null ) & local guard=$!
  wait "$nt"; assert_eq "$?" 2 "ade web with no terminal"; { kill "$guard"; wait "$guard"; } 2> /dev/null
  assert_contains "$T/err" "terminal" "says it needs a terminal"; assert_not_contains "$T/out" "http://" "no link printed"
  [ ! -e "$HOME/.config/ade/web" ] || fail "a link file without a terminal"; refused 127.0.0.1 "$p" || fail "something listens without a terminal"
}

code_new_each_start() {
  # the earlier run's session is sent under this run's cookie name (a port is not always free again at once after a
  # stop, so a restart may get another; the name carries the port)
  acme
  start; local c1 k1="$K"; c1="$(tty_code)"; login; local sid1="${CK#*=}"
  stop; start; local c2; c2="$(tty_code)"
  [ "$c2" != "$c1" ] || fail "the same code after a restart"; [ "$K" != "$k1" ] || fail "the same link after a restart"
  CK="ade_web_$PORT=$sid1"; api "/api/agents"; assert_eq "$CODE" 401 "a session from the earlier run"
  get "/" -H "Cookie: $CK"; assert_eq "$CODE" 403 "the page with a session from the earlier run"
  post "{\"code\": \"$c1\"}"; assert_eq "$CODE" 401 "the earlier run's code"
  stop; start; local c3; c3="$(tty_code)"
  [ "$c3" != "$c1" ] && [ "$c3" != "$c2" ] || fail "a code came back"
  stop
}

code_lockout() {
  acme; start; local c; c="$(tty_code)"
  local n; for n in 4 3 2 1; do
    post "$WRONG" -A "client-$n"; assert_eq "$CODE" 401 "wrong code ($n left)"; assert_eq "$(json 'd["left"]')" "$n" "the tries left"; done
  post '{"code": "wrong-zz"}' -A "another-client"; assert_eq "$CODE" 401 "the fifth wrong code, from another client"
  assert_eq "$(json 'd.get("locked")')" True "locked: wrong tries are counted per run, not per client"; assert_eq "$(json 'd["left"]')" 0 "none left"
  post "{\"code\": \"$c\"}"; assert_eq "$CODE" 401 "the right code after the lockout"; assert_eq "$(json 'd.get("locked")')" True "still locked"
  [ -z "$(set_cookie)" ] || fail "a session after the lockout"
  tty_has "used up"
  # Enter in ade's terminal: a fresh code, and five tries again
  printf '\n' >> "$T/tty.in"; local c2; c2="$(tty_code "$c")"
  post "{\"code\": \"$c\"}"; assert_eq "$CODE" 401 "the used-up code"; assert_eq "$(json 'd["left"]')" 4 "five tries for the new code"
  post "{\"code\": \"$c2\"}"; assert_eq "$CODE" 200 "the new code"; CK="$(set_cookie)"
  api "/api/agents"; assert_eq "$CODE" 200 "the API after the new code"
  stop
}

code_session_ends() {
  acme; start; login
  grep -i '^set-cookie:' "$T/head" > "$T/cookie" || fail "no cookie"
  assert_contains "$T/cookie" "ade_web_$PORT=" "the cookie is named for the port"
  local a; for a in "HttpOnly" "SameSite=Strict" "Path=/;" "Max-Age=43200"; do grep -qiF -- "$a" "$T/cookie" || fail "the cookie has no $a"; done
  assert_not_contains "$T/cookie" "$K" "the cookie is not the link's token"
  api "/api/agents"; assert_eq "$CODE" 200 "the session"
  # the lock key: the page sends {"lock": true}; the session is dropped
  get "/?k=$K"; assert_contains "$T/body" "lock: true" "the page can lock"; assert_contains "$T/body" "lock the page" "the help names the lock key"
  post '{"lock": true}' -H "Cookie: $CK"; assert_eq "$CODE" 200 "lock"
  grep -i '^set-cookie:' "$T/head" | grep -qi 'Max-Age=0' || fail "lock does not clear the cookie"
  api "/api/agents"; assert_eq "$CODE" 401 "the API after lock"; get "/" -H "Cookie: $CK"; assert_eq "$CODE" 403 "the page after lock"
  stop
  # 12 hours, shortened for the test (ADE_WEB_TEST_SESSION_SECONDS only ever shortens it)
  ADE_WEB_TEST_SESSION_SECONDS=2 start; login
  grep -i '^set-cookie:' "$T/head" | grep -qi 'Max-Age=2;' || fail "the test switch did not shorten the cookie"
  api "/api/agents"; assert_eq "$CODE" 200 "a fresh session"; sleep 3; api "/api/agents"; assert_eq "$CODE" 401 "an expired session"
  stop
  local v; for v in 99999 0 x; do
    ADE_WEB_TEST_SESSION_SECONDS="$v" start; login
    grep -i '^set-cookie:' "$T/head" | grep -qi 'Max-Age=43200' || fail "ADE_WEB_TEST_SESSION_SECONDS=$v changed the session"; stop; done
}

code_tailnet_too() {
  fixture; ts_fake; export TS_IP TS_JSON
  TS_IP=127.0.0.2; python3 -c 'import socket; socket.socket().bind(("127.0.0.2", 0))' 2> /dev/null || TS_IP=127.0.0.1
  TS_JSON="$(ts_json Running "mac.tail1234.ts.net.")"
  ADE_WEB_TEST_TAILNET_LOOPBACK=1 start --tailnet
  assert_contains "$T/web.out" "the link alone is not enough" "the start message says the link alone is not enough"
  assert_contains "$T/web.out" "the code (shown here)" "and that the code is needed"
  get "/?k=$K"; assert_eq "$CODE" 200 "the link"; assert_contains "$T/body" 'data-gate="code"' "the code prompt on the tailnet"
  get "/api/agents" -H "X-Ade-Key: $K"; assert_eq "$CODE" 401 "the API without the code on the tailnet"
  local c; c="$(tty_code)"; login; api "/api/agents"; assert_eq "$CODE" 200 "the code opens it on the tailnet"
  if grep -qF -- "$c" "$T/web.out" "$T/web.err"; then fail "the code is printed on the tailnet"; fi
  stop; unset TS_IP TS_JSON
}

code_page_premium() {
  acme; start --port "$(free_port)"
  browser_ok code_page_premium || { stop; return 0; }
  { cdp_lib; cat <<'PY'; } | python3 - "$CHROME" "$URL" "$T" "${ADE_WEB_SHOTS:-$T/shots}" || fail "the code prompt in a browser"
def shot(kind, name): open(os.path.join(shots, "ade-web-code-%s-%s.png" % (kind, name)), "wb").write(base64.b64decode(call("Page.captureScreenshot", {"format": "png"})["data"]))
def status(): return js("document.getElementById('gs').textContent") or ""
def wait_for(text, s=5):
    end = time.time() + s
    while time.time() < end:
        if text in status(): return True
        settle(0.2)
    return False
PROMPT = "ade web · enter the code shown in your terminal:"
try:
    t = call("Target.createTarget", {"url": "about:blank"})["targetId"]
    sess[0] = call("Target.attachToTarget", {"targetId": t, "flatten": True})["sessionId"]
    call("Page.enable"); call("Network.enable"); call("Runtime.enable")
    errs = []; code = tty_code()
    for name, w, h, scheme in (("dark", 1440, 900, "dark"), ("light", 1440, 900, "light"), ("phone", 375, 812, "dark")):
        call("Emulation.setDeviceMetricsOverride", {"width": w, "height": h, "deviceScaleFactor": 2, "mobile": name == "phone"})
        call("Emulation.setEmulatedMedia", {"features": [{"name": "prefers-color-scheme", "value": scheme}, {"name": "prefers-reduced-motion", "value": "no-preference"}]})
        call("Page.navigate", {"url": url}); settle(2)
        if js("document.body.dataset.gate") != "code": errs.append("%s: the link alone did not show the code prompt" % name)
        if js("getComputedStyle(document.getElementById('app')).display") != "none": errs.append("%s: the dashboard shows behind the prompt" % name)
        if PROMPT not in (js("document.getElementById('gate').innerText") or "").replace("\n", " "): errs.append("%s: no prompt line" % name)
        if js("document.activeElement && document.activeElement.id") != "gi": errs.append("%s: the code input has no focus (keyboard first)" % name)
        sw = js("Math.max(document.documentElement.scrollWidth, document.body.scrollWidth)")
        if sw > w: errs.append("%s: scrolls sideways (%s > %s)" % (name, sw, w))
        if not js("document.getAnimations().length"): errs.append("%s: no blinking cursor" % name)
        for when in ("prompt",):
            c = json.loads(js(CONTRAST))
            if c["n"] < 1 or c["bad"]: errs.append("%s %s: contrast below 4.5:1 (%d texts): %s" % (name, when, c["n"], c["bad"]))
        shot("prompt", name)
        type_text("WRONGXYZ"); key("Enter", "Enter")
        if not wait_for("✖ wrong code (4 of 5 left)"): errs.append("%s: no wrong-code line: %r" % (name, status()))
        c = json.loads(js(CONTRAST))
        if c["bad"]: errs.append("%s wrong: contrast below 4.5:1: %s" % (name, c["bad"]))
        shot("wrong", name)
        for i in range(4): type_text("WRONGXYZ"); key("Enter", "Enter"); settle(0.4)
        if not wait_for("locked: press Enter in ade's terminal for a new code"): errs.append("%s: no lockout line: %r" % (name, status()))
        c = json.loads(js(CONTRAST))
        if c["bad"]: errs.append("%s locked: contrast below 4.5:1: %s" % (name, c["bad"]))
        shot("locked", name)
        if js("document.body.dataset.gate") != "code": errs.append("%s: a wrong code opened something" % name)
        tty_enter(); code = tty_code(code)
    # the right code opens the dashboard in place; q locks it again
    call("Emulation.setDeviceMetricsOverride", {"width": 1440, "height": 900, "deviceScaleFactor": 1, "mobile": False})
    call("Page.navigate", {"url": url}); settle(2); type_text(code); key("Enter", "Enter"); settle(4)
    if js("document.body.dataset.gate") != "open": errs.append("the right code did not open the dashboard: %r" % status())
    rows = js("document.querySelectorAll('#rows > *').length")
    if not rows or rows < 8: errs.append("%s agent rows after the code" % rows)
    key("q", "KeyQ"); settle(1)
    if js("document.body.dataset.gate") != "code": errs.append("q did not lock the page")
    if js("document.querySelectorAll('#rows > *').length"): errs.append("the agent rows stay after q")
    out = [u for u in reqs if not (u.startswith(origin + "/") or u.startswith("data:"))]
    if out: errs.append("requests that leave the page's origin: %s" % out[:5])
    if errs: raise SystemExit("; ".join(errs))
finally:
    close()
PY
  local s k; for s in dark light phone; do for k in prompt wrong locked; do
    [ -s "${ADE_WEB_SHOTS:-$T/shots}/ade-web-code-$k-$s.png" ] || fail "no $k screenshot ($s)"; done; done
  stop
}

code_no_hub_writes() {
  acme; snapshot > "$T/before"; start
  get "/?k=$K"; local p; for p in "/api/agents" "/api/chat"; do get "$p" -H "X-Ade-Key: $K"; assert_eq "$CODE" 401 "$p before the code"; done
  local c i; c="$(tty_code)"; for i in 1 2 3 4 5; do post "$WRONG"; done; tty_has "used up"
  printf '\n' >> "$T/tty.in"; c="$(tty_code "$c")"
  post "{\"code\": \"$c\"}"; assert_eq "$CODE" 200 "the new code"; CK="$(set_cookie)"
  for p in "/" "/api/agents" "/api/events" "/api/events?since=1-1" "/api/log?agent=main" "/api/log?agent=api" "/api/journal" "/api/chat"; do api "$p"; done
  post '{"lock": true}' -H "Cookie: $CK"; assert_eq "$CODE" 200 "lock"
  stop; snapshot > "$T/after"
  cmp -s "$T/before" "$T/after" || { diff "$T/before" "$T/after" >&2; fail "the hub or its state folder changed"; }
  [ -z "$(ls -A "$HOME/.config/ade" 2> /dev/null)" ] || fail "something is left in ~/.config/ade: $(ls -A "$HOME/.config/ade")"
  assert_eq "$(real_conf)" "$REAL_CONF" "the real ~/.config/ade"
  assert_eq "$(sort -u "$CALLS" | tr '\n' ';')" "inbox --count main;sessions ;" "the only hub commands are bin/sessions and bin/inbox --count main"
}

# ---- story M3: ade web reads right on a fresh hub, and its quiet alert says how long ----
# new_hub: a hub as bin/init leaves it: no session, no event, the hub template's STATE.md (headings and placeholders only)
# at its root. quiet_hub: acme plus two more quiet agents, each with another last sign of life (billing: an event;
# qlast: its LAST; qcheck: a check-in), and a sender whose folder name is 32 characters long; $T/signs: each quiet
# agent's last sign of life (name, time)
TEMPLATE_STATE='# State: acme\n\nUpdated: (UTC date and time, by whom)\n\n## Live\n\n## Staged\n\n## Open\n\n## Waiting on\n\n## Next session starts with\n'
LONG_FOLDER="projects/customer-portal-backend"   # 32 characters
new_hub() {
  fixture; rm -rf "$H/journal" "$H/projects/link" "$S/events.jsonl" "$S/logs/chat.log"
  printf '#!/bin/bash\necho "sessions $*" >> "$CALLS"\necho "NAME FOLDER PID PARENT STARTED ROLE STATUS LAST ENGINE"\n' > "$H/bin/sessions"
  # shellcheck disable=SC2059  # the template's newlines, on purpose
  printf "$TEMPLATE_STATE" > "$H/STATE.md"; : > "$CALLS"
}
quiet_hub() {
  acme; python3 - "$H" "$S" "$T/signs" "$LONG_FOLDER" <<'PY'
import json, os, sys, time
H, S, signs, long = sys.argv[1:5]; now = time.time()
def at(m): return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - m * 60))
with open(os.path.join(H, "bin", "sessions"), "a") as f:
    for i, (n, d, last) in enumerate((("qlast", "projects/qlast", at(5)), ("qcheck", "projects/qcheck", at(30)))):
        f.write("printf '%%-10s %%-18s %%-6s %%-6s %%-21s %%-9s %%-6s %%-21s %%s\\n' %s %s %d - %s builder idle %s claude\n" % (n, d, 5200 + i, at(60), last))
ev = [(2, "projects/qlast", "quiet", "no check-in for 2 rounds", False), (12, "projects/qcheck", "note", "check-in: still on it", True),
      (3, "projects/qcheck", "quiet", "no check-in for 2 rounds", False), (1, long, "note", "a note from a folder with a long name", False)]
with open(os.path.join(S, "events.jsonl"), "a") as f:
    for m, a, k, x, c in ev:
        e = {"time": at(m), "from": a, "to": "main", "kind": k, "text": x}
        if c: e["checkin"] = True
        f.write(json.dumps(e) + "\n")
# billing's last sign of life is its idle event (25 min ago, as acme writes it)
idle = [e["time"] for e in map(json.loads, open(os.path.join(S, "events.jsonl"))) if e["from"] == "projects/billing" and e["kind"] == "idle"][0]
open(signs, "w").write("billing %s\nqlast %s\nqcheck %s\n" % (idle, at(5), at(12)))
PY
}
# m3_lib: after cdp_lib, the Python the M3 browser checks share: opened (the dashboard after the code), view (a width
# and a colour scheme), the colour of a theme token, one element's text, colour and title, and a screenshot
m3_lib() { cat <<'PY'
errs = []
def view(w, h, scheme="dark", scale=1):
    call("Emulation.setDeviceMetricsOverride", {"width": w, "height": h, "deviceScaleFactor": scale, "mobile": w < 500})
    call("Emulation.setEmulatedMedia", {"features": [{"name": "prefers-color-scheme", "value": scheme}, {"name": "prefers-reduced-motion", "value": "no-preference"}]}); settle(0.5)
def opened(w=1440, h=900, scheme="dark", code=True):
    t = call("Target.createTarget", {"url": "about:blank"})["targetId"]
    sess[0] = call("Target.attachToTarget", {"targetId": t, "flatten": True})["sessionId"]
    call("Page.enable"); call("Network.enable"); call("Runtime.enable")
    view(w, h, scheme); call("Page.navigate", {"url": url}); settle(2)
    if code: type_text(tty_code()); key("Enter", "Enter"); settle(4)
def token(name): return js("(function(){var s=document.createElement('span');s.style.color='var(--%s)';document.body.appendChild(s);var c=getComputedStyle(s).color;s.remove();return c})()" % name)
def el(sel): return js("(function(){var e=document.querySelector(%s);return e?{t:e.textContent,c:getComputedStyle(e).color,title:e.title||'',h:e.getBoundingClientRect().height,sw:e.scrollWidth,cw:e.clientWidth,w:e.getBoundingClientRect().width,shown:e.getClientRects().length>0}:null})()" % json.dumps(sel))
def cell(name, part): return el('#rows .row[data-name="%s"] .%s' % (name, part)) or {"t": None, "c": None, "title": ""}
def shot(name): open(os.path.join(shots, name + ".png"), "wb").write(base64.b64decode(call("Page.captureScreenshot", {"format": "png"})["data"]))
PY
}
# in_browser <test>: the Python on stdin, after cdp_lib and m3_lib, in a headless Chromium; what it adds to errs fails
in_browser() {
  { cdp_lib; m3_lib; echo "try:"; sed 's/^/    /'; printf 'finally:\n    close()\nif errs: raise SystemExit("; ".join(errs))\n'; } |
    python3 - "$CHROME" "$URL" "$T" "${ADE_WEB_SHOTS:-$T/shots}" || fail "$1 in a browser"
}

web_state_placeholder() {   # AC1
  acme
  # shellcheck disable=SC2059  # the template's newlines, on purpose
  printf "$TEMPLATE_STATE" > "$H/projects/docs/STATE.md"
  printf '# STATE\n- waiting for the API change\nUpdated: (UTC date and time, by whom)\n- Owner: (a name)\n## Live\n' > "$H/projects/web/STATE.md"
  printf '# STATE\n- rate limiter wired\nUpdated: 2026-11-27T10:00Z, by api\n## Live\n' > "$H/projects/api/STATE.md"
  start; login; api "/api/agents"
  assert_eq "$(json '[a["line"] for a in d["agents"] if a["name"] in ("docs", "web", "api")]')" "['Updated: 2026-11-27T10:00Z, by api', 'waiting for the API change', '']" \
    "a placeholder line is skipped; a real value is kept; headings and placeholders only give no line"
  browser_ok web_state_placeholder || { stop; return 0; }
  in_browser web_state_placeholder <<'PY'
opened()
for who, want in (("docs", "no state yet"), ("web", "waiting for the API change")):
    got = cell(who, "ln")["t"]
    if got != want: errs.append("%s's row reads %r, not %r" % (who, got, want))
PY
  stop
}

web_main_not_running() {   # AC2
  new_hub; rm -f "$H/STATE.md"; start; login; api "/api/agents"
  assert_eq "$(json '[(a["name"], a["running"], a["line"]) for a in d["agents"]]')" "[('main', False, None)]" "main has no session and the hub root no STATE.md"
  browser_ok web_main_not_running || { stop; return 0; }
  in_browser web_main_not_running <<'PY'
opened()
ck, ln, dim = cell("main", "ck"), cell("main", "ln"), token("dim")
if ck["t"] != "not running" or ck["c"] != dim: errs.append("main's row: %r in %s, not 'not running' in the dim %s" % (ck["t"], ck["c"], dim))
if ln["t"] != "no STATE.md yet": errs.append("main's line reads %r, not 'no STATE.md yet'" % ln["t"])
txt = js("document.getElementById('app').innerText")
if "unknown" in txt: errs.append("the page still says unknown")
head = el("#dbody .dh span:last-child")
if not head or head["t"] != "not running" or head["c"] != dim: errs.append("main's detail heading: %r" % head)
if "no STATE.md yet" not in (js("document.getElementById('dbody').innerText") or ""): errs.append("main's detail does not say no STATE.md yet")
PY
  stop
  # the template's STATE.md at the root: a file with no state in it yet
  # shellcheck disable=SC2059  # the template's newlines, on purpose
  printf "$TEMPLATE_STATE" > "$H/STATE.md"; start; login; api "/api/agents"
  assert_eq "$(json 'd["agents"][0]["line"]')" "" "the template's STATE.md gives no line"
  in_browser web_main_not_running <<'PY'
opened()
if cell("main", "ln")["t"] != "no state yet": errs.append("main's line with the template's STATE.md: %r" % cell("main", "ln")["t"])
PY
  stop
}

web_quiet_for() {   # AC3
  quiet_hub; start; login; api "/api/agents"
  assert_eq "$(json '[a["name"] for a in d["agents"] if a["state"] == "quiet"]')" "['billing', 'qlast', 'qcheck']" "three quiet agents"
  python3 - "$T/body" "$T/signs" <<'PY' || fail "the quiet alerts"
import calendar, json, sys, time
d = json.load(open(sys.argv[1])); got = {a["agent"]: a["text"] for a in d["alerts"] if a["kind"] == "quiet"}; bad = []
for line in open(sys.argv[2]):
    name, t = line.split(); s = calendar.timegm(time.strptime(t, "%Y-%m-%dT%H:%M:%SZ"))
    want = "%s is quiet: no check-in for %dm (since %sZ)" % (name, (d["now"] - s) // 60, t[11:16])
    if got.get(name) != want: bad.append("%r, not %r" % (got.get(name), want))
if bad: raise SystemExit("; ".join(bad))
PY
  stop
}

web_quiet_row() {   # AC4
  quiet_hub; start; login
  browser_ok web_quiet_row || { stop; return 0; }
  in_browser web_quiet_row <<'PY'
opened()
q, ok, dim, idle = cell("qcheck", "ck"), cell("api", "ck"), token("dim"), token("idle")
if not re.fullmatch(r"last check-in [0-9]+m[0-9]{2}s ago", q["t"] or "") or q["c"] != dim: errs.append("a quiet row's check-in: %r in %s (dim is %s)" % (q["t"], q["c"], dim))
if "✓" in (q["t"] or ""): errs.append("a quiet row is ticked")
if not (ok["t"] or "").startswith("✓ checked in ") or ok["c"] != idle: errs.append("a busy row's check-in: %r in %s (idle is %s)" % (ok["t"], ok["c"], idle))
PY
  stop
}

web_legend() {   # AC5
  acme; start; login
  browser_ok web_legend || { stop; return 0; }
  in_browser web_legend <<'PY'
opened()
for i, s in enumerate(("busy", "idle", "ready", "quiet", "blocked")):
    c = el("#counts span:nth-child(%d)" % (i + 1))
    if not c or s not in c["title"] or len(c["title"]) < len(s) + 10: errs.append("the %s count's title: %r" % (s, c and c["title"]))
for i, w in (("sync", "sync"), ("mon", "monitor"), ("unread", "unread")):
    c = el("#" + i)
    if not c or w not in c["title"]: errs.append("#%s's title: %r" % (i, c and c["title"]))
mk = cell("mobile", "mk")
if mk["t"] != "!" or "mobile may be waiting at a prompt" not in mk["title"] or "alert" not in mk["title"]: errs.append("mobile's ! title: %r" % mk["title"])
if cell("web", "mk")["title"]: errs.append("a row with no alert has a title on its mark")
PY
  stop
  new_hub; start; login
  in_browser web_legend <<'PY'
opened()
for i, want in (("sync", "sync none yet"), ("mon", "monitors none")):
    c = el("#" + i)
    if not c or c["t"] != want or not c["title"]: errs.append("#%s reads %r (title %r), not %r" % (i, c and c["t"], c and c["title"], want))
PY
  stop
}

web_wide_names() {   # AC6
  quiet_hub; start; login
  browser_ok web_wide_names || { stop; return 0; }
  LONG_FOLDER="$LONG_FOLDER" in_browser web_wide_names <<'PY'
long = os.environ["LONG_FOLDER"]
opened(1280, 800)
who = js("(function(){var r=[].filter.call(document.querySelectorAll('#feed .ev .who'),function(e){return e.textContent===%s})[0];return r?[r.scrollWidth,r.clientWidth]:null})()" % json.dumps(long))
if not who or who[0] > who[1]: errs.append("at 1280 px the sender %s is cut: %r" % (long, who))
view(375, 812)
ch = js("(function(){var s=document.createElement('span');s.textContent='0000000000';s.style.position='absolute';document.getElementById('feed').appendChild(s);var w=s.getBoundingClientRect().width/10;s.remove();return w})()")
w = el("#feed .ev .who")["w"]
if abs(w - 13 * ch) > 1: errs.append("at phone width the sender column is %.1f px, not 13ch (%.1f px)" % (w, 13 * ch))
PY
  stop
}

web_short_text() {   # AC7
  fixture; sed -i.bak 's/^HUB_NAME=.*/HUB_NAME=acme-customer-operations/' "$H/hub.conf"; rm -f "$H/hub.conf.bak"
  long_lines() { tr -d '\r' < "$1" | grep -v 'http://' | awk 'length($0) > 100' || true; }
  local p; p="$(free_port)"; start --port 65535 2> /dev/null || start --port "$p"; tty_code > /dev/null
  [ -z "$(long_lines "$T/web.out")$(long_lines "$T/tty.out")" ] || fail "the start message (--no-open) has a line over 100 columns: $(long_lines "$T/web.out")$(long_lines "$T/tty.out")"
  stop
  # ade opens the page itself (the fake opener)
  : > "$T/web.out"; : > "$T/tty.out"; PATH="$WPATH" TMPDIR="$T/tmp" "${TTYRUN[@]}" "$ADE" web > "$T/web.out" 2> "$T/web.err" & SRV=$!
  local i=0; until grep -q 'Ctrl-C' "$T/web.out"; do i=$((i + 1)); [ "$i" -lt 100 ] || fail "ade web did not open the page"; sleep 0.1; done
  [ -z "$(long_lines "$T/web.out")" ] || fail "the start message (opened) has a line over 100 columns: $(long_lines "$T/web.out")"
  stop
  # --tailnet: on a loopback address standing in for the Tailscale one
  ts_fake; export TS_IP TS_JSON; TS_IP=127.0.0.2; python3 -c 'import socket; socket.socket().bind(("127.0.0.2", 0))' 2> /dev/null || TS_IP=127.0.0.1
  TS_JSON="$(ts_json Running "mac.tail1234.ts.net.")"; ADE_WEB_TEST_TAILNET_LOOPBACK=1 start --tailnet
  [ -z "$(long_lines "$T/web.out")" ] || fail "the start message (--tailnet) has a line over 100 columns: $(long_lines "$T/web.out")"
  stop; unset TS_IP TS_JSON
  # the code page: one hint line under the prompt; ? shows the rest (and types nothing into the code)
  start
  browser_ok web_short_text || { stop; return 0; }
  in_browser web_short_text <<'PY'
for w, h in ((1440, 900), (375, 812)):
    if sess[0] is None: opened(w, h, code=False)
    else: view(w, h); call("Page.navigate", {"url": url}); settle(2)
    hints = js("[].filter.call(document.querySelectorAll('#gate .gh'),function(e){return e.getClientRects().length>0}).map(function(e){return [e.textContent,e.getBoundingClientRect().height]})")
    if len(hints) != 1 or hints[0][1] > 21: errs.append("%d px: the hint under the prompt is not one line: %r" % (w, hints))
    if "--print-link" in (js("document.getElementById('gate').innerText") or ""): errs.append("%d px: the long hint is still shown" % w)
    key("?", "Slash"); settle(0.3)
    if "--print-link" not in (js("document.getElementById('gate').innerText") or ""): errs.append("%d px: ? does not show the rest" % w)
    if js("document.getElementById('gi').value"): errs.append("%d px: ? went into the code" % w)
    key("?", "Slash"); settle(0.3)
    if "--print-link" in (js("document.getElementById('gate').innerText") or ""): errs.append("%d px: ? again does not hide it" % w)
    js("document.querySelector('#gate .gh').click()"); settle(0.3)   # a phone has no ? key: a tap on the hint does it
    if "--print-link" not in (js("document.getElementById('gate').innerText") or ""): errs.append("%d px: a tap on the hint does not show the rest" % w)
    js("document.querySelector('#gate .gh').click()"); settle(0.3)
PY
  stop
}

# shots_saved <kind> <folder>: the three screenshots of one hub are there
shots_saved() { local s; for s in dark light phone; do [ -s "$2/ade-web-$1-$s.png" ] || fail "no $1 $s screenshot"; done; }
web_devex_screens() {   # AC8: for the owner, in ADE_WEB_SHOTS (else this test's folder, which each new hub replaces:
  local out                # so each hub's shots are checked before the next)
  new_hub; start; login
  browser_ok web_devex_screens || { stop; return 0; }
  out="${ADE_WEB_SHOTS:-$T/shots}"
  ADE_WEB_SHOTS="$out" in_browser web_devex_screens <<'PY'
opened(1440, 900, "dark", 2)
for name, w, h, scheme in (("dark", 1440, 900, "dark"), ("light", 1440, 900, "light"), ("phone", 375, 812, "dark")):
    view(w, h, scheme, 2); settle(3.5); shot("ade-web-fresh-" + name)
PY
  stop; shots_saved fresh "$out"
  quiet_hub; start; login; out="${ADE_WEB_SHOTS:-$T/shots}"
  ADE_WEB_SHOTS="$out" in_browser web_devex_screens <<'PY'
opened(1440, 900, "dark", 2)
for name, w, h, scheme in (("dark", 1440, 900, "dark"), ("light", 1440, 900, "light"), ("phone", 375, 812, "dark")):
    view(w, h, scheme, 2); settle(3.5); shot("ade-web-quiet-" + name)
PY
  stop; shots_saved quiet "$out"
}

REAL_CONF="$(real_conf)"
# bash tests/test_web.sh [test ...]: those tests only (each name a function above)
if [ "$#" -gt 0 ]; then for t in "$@"; do "$t"; done; echo ok; exit 0; fi
t_local
t_token
t_host
t_readonly
t_page
t_redact
t_escapes
t_paths
t_long
t_tailnet
t_link
web_loopback_only
web_token_required
web_read_only
web_agents_json
web_events_json
web_alerts
web_page_renders
web_stops_cleanly
web_no_hub_writes
web_premium_checks
code_required
code_unlocks
code_shown_on_terminal_only
code_new_each_start
code_lockout
code_session_ends
code_tailnet_too
code_page_premium
code_no_hub_writes
web_state_placeholder
web_main_not_running
web_quiet_for
web_quiet_row
web_legend
web_wide_names
web_short_text
web_devex_screens
echo ok
