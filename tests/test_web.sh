#!/bin/bash
# story A19: ade web, a read-only page of the hub's agents and logs. A fixture hub (a fake bin/sessions, a journal, a
# chat log, events, a STATE.md) is served on a loopback address and asked with curl. ade runs with only this test's
# fakes and the system's own commands ($T/sys, without tailscale), so a host's Tailscale never answers. Every
# secret-shaped string is built here at run time from parts; none is written in this file.
. "$(dirname "$0")/helpers.sh"

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
SECRETS="$S_TG $S_SKD $S_SKU $S_GHL $S_GHS $S_PAT $S_PW $S_PWJ $S_AUTH $S_BEAR $S_GLM $S_RUN"
secret_lines() {   # <label>: one line per secret, with a word before and after it
  printf '%s tg before %s after\n' "$1" "$S_TG"; printf '%s skd before %s after\n' "$1" "$S_SKD"
  printf '%s sku before %s after\n' "$1" "$S_SKU"; printf '%s ghl before %s after\n' "$1" "$S_GHL"
  printf '%s ghs before %s after\n' "$1" "$S_GHS"; printf '%s pat before %s after\n' "$1" "$S_PAT"
  printf '%s pw before password=%s after\n' "$1" "$S_PW"; printf '%s pwj before {"password": "%s"} after\n' "$1" "$S_PWJ"
  printf '%s auth before Authorization: Basic %s\n' "$1" "$S_AUTH"; printf '%s bear before Bearer %s after\n' "$1" "$S_BEAR"
  printf '%s glm before %s after\n' "$1" "$S_GLM"; printf '%s run before %s after\n' "$1" "$S_RUN"
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
  python3 - "$S/events.jsonl" "$S_TG $S_SKD $S_SKU $S_GHL $S_GHS $S_PAT $S_GLM $S_RUN" <<'PY'
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
  export ADE_HUB="$H" AGENT_STATE="$S" ADE_WEB_OPENED="$T/opened"; : > "$T/opened"
  WPATH="$F:$T/sys"; SRV=""
}
# start [args]: ade web in the background; URL, PORT and K from its first line
start() {
  : > "$T/web.out"; : > "$T/web.err"
  PATH="$WPATH" "$ADE" web "$@" > "$T/web.out" 2> "$T/web.err" &
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
# login: the first visit; CK is the cookie it set. api: a request with that cookie (sent as a header: curl's own cookie
# jar would keep it from a request whose Host header names another host, which is the server's decision to make here)
login() { get "/?k=$K"; assert_eq "$CODE" 200 "the link"; CK="$(tr -d '\r' < "$T/head" | sed -n 's/^[Ss]et-[Cc]ookie: \([^;]*\);.*/\1/p' | head -1)"; [ -n "$CK" ] || fail "the first visit set no cookie"; }
api() { local p="$1"; shift; get "$p" -H "Cookie: $CK" "$@"; }
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
  if PATH="$WPATH" HOME="$T/home3" "$ADE" web --port "$p" > "$T/out" 2> "$T/err"; then fail "--port on a busy port started"; fi
  assert_contains "$T/err" "port $p is in use" "a busy --port says so"
  stop; SRV="$first"; stop
  # --port N free
  p="$(free_port)"; start --port "$p"; assert_eq "$PORT" "$p" "--port N"; stop
  local a; for a in "--port" "--port x" "--port 0" "--port 70000" "--port 80" "--bind 0.0.0.0" "--host 0.0.0.0" "extra"; do
    # shellcheck disable=SC2086  # the arguments of one case, split on purpose
    PATH="$WPATH" "$ADE" web $a > "$T/out" 2> "$T/err"; assert_eq "$?" 2 "ade web $a is a usage error"
    assert_contains "$T/err" "usage: ade web" "ade web $a prints the usage"; done
  PATH="$WPATH" "$ADE" help > "$T/out"; assert_contains "$T/out" "ade web [--port N] [--tailnet] | --print-link" "help lists ade web"
}

t_token() {
  fixture; start
  get "/"; assert_eq "$CODE" 403 "no token"; assert_not_contains "$T/body" "acme" "403 carries no data"
  get "/?k=wrong"; assert_eq "$CODE" 403 "a wrong token"
  get "/?k=${K}x"; assert_eq "$CODE" 403 "a longer token"
  get "/?k="; assert_eq "$CODE" 403 "an empty token"
  get "/api/agents"; assert_eq "$CODE" 403 "the API without a cookie"; assert_not_contains "$T/body" "api" "403 carries no agent"
  get "/api/agents?k=$K"; assert_eq "$CODE" 403 "the link's token opens the page only, never the API"
  get "/api/chat" -H "Cookie: ade_web_$PORT=wrong"; assert_eq "$CODE" 403 "a wrong cookie"
  get "/api/chat" -H "Cookie: ade_web_$PORT=$K"; assert_eq "$CODE" 403 "the link's token is not the cookie"
  assert_not_contains "$T/body" "chat line one" "403 carries no log"
  login
  grep -i '^set-cookie:' "$T/head" > "$T/cookie" || fail "the first visit sets no cookie"
  assert_contains "$T/cookie" "ade_web_$PORT=" "the cookie is named for the port"
  grep -qi 'httponly' "$T/cookie" || fail "the cookie is not HttpOnly"
  grep -qi 'samesite=strict' "$T/cookie" || fail "the cookie is not SameSite=Strict"
  assert_not_contains "$T/cookie" "$K" "the cookie is not the link's token"
  api "/"; assert_eq "$CODE" 200 "the page with the cookie alone"
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
  fixture; start; login
  grep -qi '^content-type: text/html; charset=utf-8' "$T/head" || fail "the page is not HTML"
  assert_contains "$T/body" '<meta name="viewport"' "the page fits a phone"
  # one document: no address but its own API, no script or style from elsewhere
  if grep -Eqi 'https?://|//[a-z0-9.-]+\.[a-z]{2,}|<link|@import|src=|url\(' "$T/body"; then fail "the page names an outside address or file"; fi
  local s; for s in Agents Journal Chat; do assert_contains "$T/body" "$s" "the page has a $s section"; done
  api "/api/agents"; grep -qi '^content-type: application/json' "$T/head" || fail "the API is not JSON"
  assert_eq "$(json '[a["name"] for a in d["agents"]]')" "['api', 'infra', 'evil', 'link']" "the agents of bin/sessions"
  assert_eq "$(json 'd["agents"][0]["status"] + " " + d["agents"][0]["folder"] + " " + d["agents"][0]["role"] + " " + d["agents"][0]["engine"]')" "busy projects/api builder claude" "an agent's state"
  assert_eq "$(json 'd["agents"][1]["status"] + " " + d["agents"][1]["last"]')" "idle 2026-11-23T08:30:00Z" "the second agent"
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
  api "/api/agents"; assert_eq "$CODE" 200 "a failing bin/sessions"; assert_eq "$(json 'd["agents"]')" "[]" "no agent"
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
    for w in tg skd sku ghl ghs pat pw pwj bear glm run; do
      grep -Eq "${p##*:} $w before .*after" "$T/text" || fail "${p%:*}: the words around the $w secret are gone"; done
    grep -Eq "${p##*:} auth before Authorization: <hidden>" "$T/text" || fail "${p%:*}: the Authorization line"
    assert_contains "$T/text" "password=<hidden> after" "${p%:*}: password="; done
  api "/api/log?agent=api"; flat; assert_contains "$T/text" "event before <hidden" "an event's secret is hidden, its words kept"
  api "/api/agents"; assert_eq "$(json 'd["agents"][3]["role"]')" "<hidden key>" "a key in a bin/sessions column"
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
  fixture; echo "CANARY-ABS" > "$T/canary"; start; login
  local p; for p in "/api/agents" "/api/log?agent=api" "/api/journal" "/api/chat"; do api "$p"; assert_eq "$CODE" 200 "$p"; done
  assert_contains "$T/opened" "$H/projects/api/STATE.md" "the open trace works"
  cp "$T/opened" "$T/opened.before"
  for p in "/api/log?agent=nosuch" "/api/log?agent=../../canary" "/api/log?agent=..%2F..%2Fcanary" "/api/log?agent=%2e%2e/outside" \
           "/api/log?agent=$T/canary" "/api/log?agent=projects/api" "/api/log?agent=" "/api/log" "/api/log?agent=api&agent=infra" \
           "/api/log?agent=api%00" "/api/log?agent=API" "/api/log?path=$T/canary" "/api/file?path=$T/canary" "$T/canary" "/$T/canary" \
           "/../../../../etc/hosts" "/..%2f..%2fetc/hosts" "/etc/hosts" "//etc/hosts" "/journal/../hub.conf" "/hub.conf" "/api/journal/2001-01-01" \
           "/api/journal?date=2001-01-01.md&file=$T/canary" "/api/chat/../../canary" "/api" "/api/" "/index.html" "/favicon.ico"; do
    api "$p"
    case "$p" in "/api/journal?"*) assert_eq "$CODE" 200 "a parameter the server does not read: $p" ;; *) assert_eq "$CODE" 404 "$p" ;; esac
    if grep -Eq 'CANARY|localhost' "$T/body"; then fail "$p served a file it was not asked to choose"; fi
  done
  # the journal request above opened the two journal files again, as it does without any parameter, and nothing else
  grep -v "^$H/journal/" "$T/opened" > "$T/opened.after"; grep -v "^$H/journal/" "$T/opened.before" > "$T/opened.was"
  cmp -s "$T/opened.was" "$T/opened.after" || { diff "$T/opened.was" "$T/opened.after" >&2; fail "a refused request opened a file"; }
  assert_not_contains "$T/opened" "canary" "the canary was never opened"; assert_not_contains "$T/opened" "2001-01-01" "no journal by a date from the request"
  # a folder outside the hub in bin/sessions' own output, and a STATE.md that is a link out of the hub: listed, never read
  for p in evil link; do api "/api/log?agent=$p"; assert_eq "$CODE" 200 "$p is in the list"; assert_eq "$(json 'd["state"]')" "[]" "$p: no STATE.md is read"
    assert_not_contains "$T/body" "CANARY" "$p: a file outside the hub was served"; done
  assert_not_contains "$T/opened" "outside" "nothing outside the hub was opened"
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
  PATH="$WPATH" "$ADE" web --tailnet > "$T/out" 2> "$T/err" & SRV=$!
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
  assert_contains "$T/web.out" "anyone on your tailnet with the link can read these logs" "the plain warning"
  assert_contains "$T/web.out" "the link changes every start" "says the link changes"
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
  # Ctrl-C at a terminal: the same, exit 0
  python3 - "$ADE" "$WPATH" "$L" <<'PY' || fail "Ctrl-C did not stop ade web cleanly"
import os, pty, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.environ["PATH"] = sys.argv[2]; os.execv(sys.argv[1], [sys.argv[1], "web"])
buf = b""; end = time.time() + 15
while b"Ctrl-C" not in buf and time.time() < end:
    if select.select([fd], [], [], 0.2)[0]:
        try: buf += os.read(fd, 4096)
        except OSError: break
assert b"http://127.0.0.1:" in buf, buf
assert os.path.exists(sys.argv[3]), "no link file while running"
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
assert not os.path.exists(sys.argv[3]), "the link file is left after Ctrl-C"
assert b"Traceback" not in buf, buf
PY
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

t_local
t_token
t_host
t_readonly
t_page
t_redact
t_escapes
t_paths
t_tailnet
t_link
echo ok
