#!/bin/bash
# story A20: `ade shot`, screenshots as proof. Fakes for Playwright's Chromium (it speaks the DevTools pipe and records
# what it is asked), screencapture, import, xwd, tmux and the hub's bin/chat. Never a real browser, screen or Telegram.
. "$(dirname "$0")/helpers.sh"

DAY=2026-11-23; HMS=104507
shot_fixture() {
  fresh; F="$T/fakebin"; mkdir -p "$F" "$T/log"; export FAKE_LOG="$T/log" ADE_NOW="${DAY}T10:45:07Z"
  unset FAKE_CHROME FAKE_OS FAKE_UNSHARE_RC FAKE_SCREEN_FAIL FAKE_SEND_RC DISPLAY TMUX ADE_UI_SESSION
  P="$T/proj"; mkdir -p "$P/docs"; git init -q "$P"; echo "<h1>report</h1>" > "$P/docs/report.html"
  make_hub "$T/hub" hub; printf 'HUB_NAME=acme\n' > "$T/hub/hub.conf"; export ADE_HUB="$T/hub"
  # Playwright's Chromium, where the hub looks for it: a stand-in that answers the DevTools pipe (fd 3 in, fd 4 out)
  export PLAYWRIGHT_BROWSERS_PATH="$T/pw"; mkdir -p "$T/pw/chromium-1/chrome-linux"
  cat > "$T/pw/chromium-1/chrome-linux/chrome" <<'PY'
#!/usr/bin/env python3
import base64, json, os, shutil, struct, sys, zlib
log = os.environ["FAKE_LOG"]; mode = os.environ.get("FAKE_CHROME", "")
open(log + "/chrome.argv", "a").write("\n".join(sys.argv[1:]) + "\n--\n")
# sandboxfail: Ubuntu 23.10+ (AppArmor): its sandbox cannot start, so it exits at once unless --no-sandbox; dies: always
if mode == "dies" or (mode == "sandboxfail" and "--no-sandbox" not in sys.argv):
    sys.stderr.write("".join("[1:1:ERROR:gpu_init.cc(1)] early line %d\n" % i for i in range(30)) + "[2:2:FATAL:zygote_host_impl_linux.cc(127)] No usable sandbox!\n"
                     "[2:2:FATAL:x.cc(9)] last line, token=s3cr3tvalue99\n"); sys.exit(1)
def png(w, h):
    def ch(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + ch(b"IDAT", zlib.compress(b"\0" * ((1 + 3 * w) * h))) + ch(b"IEND", b""))
def out(m): os.write(4, json.dumps(m).encode() + b"\0")
buf = b""; size = [1280, 800]
while True:
    b = os.read(3, 65536)
    if not b: break
    buf += b
    while b"\0" in buf:
        raw, buf = buf.split(b"\0", 1); m = json.loads(raw); open(log + "/chrome.cdp", "a").write(json.dumps(m) + "\n")
        me, p, sid = m["method"], m.get("params", {}), m.get("sessionId")
        def reply(r):
            d = {"id": m["id"], "result": r}
            if sid: d["sessionId"] = sid
            out(d)
        def event(method, params): out({"method": method, "params": params, "sessionId": sid})
        if mode == "silent": continue
        if me == "Target.createTarget": reply({"targetId": "T1"})
        elif me == "Target.attachToTarget": reply({"sessionId": "S1"})
        elif me == "Emulation.setDeviceMetricsOverride": size = [p["width"], p["height"]]; reply({})
        elif me == "Page.navigate":
            url = p["url"]; reqs = [url]
            if url.startswith("file://") and url.endswith("/pane.html"): shutil.copy(url[7:], log + "/page.html")
            if os.path.exists(log + "/requests"): reqs += open(log + "/requests").read().split()
            for i, u in enumerate(reqs): event("Fetch.requestPaused", {"requestId": "R%d" % i, "request": {"url": u}})
            if mode == "navfail": reply({"frameId": "F", "errorText": "net::ERR_NAME_NOT_RESOLVED"}); continue
            reply({"frameId": "F"})
            event("Network.responseReceived", {"type": "Document", "response": {"status": 200, "url": url}})
            if mode != "noload": event("Page.loadEventFired", {"timestamp": 1})
        elif me == "Page.getLayoutMetrics": reply({"cssContentSize": {"x": 0, "y": 0, "width": size[0], "height": 2400}})
        elif me == "Runtime.evaluate": reply({"result": {"type": "string", "value": "[642, 310]"}})
        elif me == "Page.captureScreenshot":
            c = p.get("clip"); w, h = (int(c["width"]), int(c["height"])) if c else size
            reply({"data": base64.b64encode(b"not a png" if mode == "badpng" else png(w, h)).decode()})
        elif me == "Browser.close": reply({}); sys.exit(0)
        else: reply({})
PY
  chmod +x "$T/pw/chromium-1/chrome-linux/chrome"
  # a 2x3 PNG the screen fakes hand over, and a 4x2 X window dump (32 bits, least significant byte first) for xwd
  python3 - "$T/log" <<'PY'
import struct, sys, zlib
d = sys.argv[1]
def ch(t, b): return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
open(d + "/tiny.png", "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", 2, 3, 8, 2, 0, 0, 0))
                                  + ch(b"IDAT", zlib.compress(b"\0" * 21)) + ch(b"IEND", b""))
name = b"root\0"; head = struct.pack(">25I", 100 + len(name), 7, 2, 24, 4, 2, 0, 0, 32, 0, 32, 32, 16, 4, 0xff0000, 0xff00, 0xff, 8, 256, 1, 4, 2, 0, 0, 0)
px = b"".join(bytes((b, g, r, 0)) for r, g, b in [(255, 0, 0), (0, 255, 0), (0, 0, 255), (1, 2, 3)] * 2)
open(d + "/screen.xwd", "wb").write(head + name + b"\0" * 12 + px)
PY
  cat > "$F/screencapture" <<'S'
#!/bin/bash
echo "screencapture $*" >> "$FAKE_LOG/screen"
[ -z "${FAKE_SCREEN_FAIL:-}" ] || { echo "could not create image from display" >&2; exit 1; }
for a in "$@"; do f="$a"; done; cp "$FAKE_LOG/tiny.png" "$f"
S
  printf '#!/bin/bash\necho "import $*" >> "$FAKE_LOG/screen"\nfor a in "$@"; do f="$a"; done; cp "$FAKE_LOG/tiny.png" "$f"\n' > "$F/import"
  printf '#!/bin/bash\necho "xwd $*" >> "$FAKE_LOG/screen"\ncat "$FAKE_LOG/screen.xwd"\n' > "$F/xwd"
  printf '#!/bin/bash\ncase "${1:-}" in ""|-s) echo "${FAKE_OS:-Darwin}" ;; *) exec "%s" "$@" ;; esac\n' "$(command -v uname)" > "$F/uname"
  printf '#!/bin/bash\necho "unshare $*" >> "$FAKE_LOG/unshare"\nexit "${FAKE_UNSHARE_RC:-0}"\n' > "$F/unshare"   # a user namespace can be made
  cat > "$F/tmux" <<'S'
#!/bin/bash
[ "$1" = -L ] && shift 2
echo "tmux $*" >> "$FAKE_LOG/tmux"
case "$1" in
  list-windows) [ ! -f "$FAKE_LOG/nosession" ] || exit 1; printf '0\torchestrator\n1\tprojects/api:1.2\n2\tops/db\n3\tprojects/web:rev\n4\tops/api\n' ;;
  capture-pane) cat "$FAKE_LOG/pane.raw" ;;
esac
S
  # the hub's bin/chat: status says locked (or not: $FAKE_LOG/unlocked), send records the file and the caption on stdin
  cat > "$T/hub/bin/chat" <<'S'
#!/bin/bash
echo "chat $*" >> "$FAKE_LOG/chat"
case "${1:-}" in
  status) echo "acme: stopped"
    if [ -f "$FAKE_LOG/unlocked" ]; then echo "telegram: policy pairing, groups: 0, not locked"; echo "mode: manual (not locked: telegram: the policy is pairing)"
    else echo "telegram: policy allowlist, groups: 0, locked to you"; echo "mode: auto (telegram is locked to you)"; fi ;;
  send) [ ! -f "$FAKE_LOG/oldhub" ] || { echo "usage: bin/chat start | stop | status" >&2; exit 2; }
    cat > "$FAKE_LOG/caption"; [ -z "${FAKE_SEND_RC:-}" ] || { echo "chat: the file was not sent (HTTP 400: Bad Request)" >&2; exit "$FAKE_SEND_RC"; }
    echo "sent $(basename "$2") to the paired owner" ;;
  *) echo "usage: bin/chat" >&2; exit 2 ;;
esac
S
  chmod +x "$F"/* "$T/hub/bin/chat"; printf 'plain text\n' > "$T/log/pane.raw"
  REALPATH="$PATH"; export PATH="$F:$PATH"; cd "$P" || fail "cd"
}
shot() { bash "$ADE" shot "$@" > "$T/out" 2> "$T/err"; RC=$?; }
ev() { echo "$P/.ade/evidence/$DAY"; }
pngsize() { python3 -c 'import struct, sys; d = open(sys.argv[1], "rb").read(24); assert d[:8] == b"\x89PNG\r\n\x1a\n"; print("%dx%d" % struct.unpack(">II", d[16:24]))' "$1"; }
fmode() { python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1"; }
# cdp <method>: the parameters ade sent for that DevTools method, one JSON object per line
cdp() { python3 -c 'import json, sys
for l in open(sys.argv[1]):
    m = json.loads(l)
    if m["method"] == sys.argv[2]: print(json.dumps(m.get("params", {}), sort_keys=True))' "$T/log/chrome.cdp" "$1"; }
no_capture() { [ ! -e "$T/log/chrome.argv" ] && [ ! -e "$T/log/screen" ] || fail "$1: something was captured"; [ ! -e "$P/.ade/evidence" ] || fail "$1: something was saved"; }
# minpath <extra fake>...: a PATH with only the tools ade needs and the named fakes (so a real import or xwd is never found)
minpath() {
  local c r; rm -rf "$T/min"; mkdir -p "$T/min"
  for c in python3 git bash sh awk sed tr cut head tail grep cat mktemp dirname basename rm mkdir chmod cp mv ls date env sort wc cksum readlink sleep id; do
    r="$(PATH="$REALPATH" command -v "$c")" || continue; printf '#!/bin/sh\nexec "%s" "$@"\n' "$r" > "$T/min/$c"; done
  for c in uname "$@"; do cp "$F/$c" "$T/min/$c"; done; chmod +x "$T/min"/*
}

# AC1: a page, through the headless Chromium the hub already has; no browser, one line on how to get it
url_shot() {
  shot_fixture; mkdir "$T/tmp"; TMPDIR="$T/tmp" shot url "https://example.test/pay?step=2" --name "checkout fixed"; assert_eq "$RC" 0 "a page shot [$(cat "$T/err")]"
  assert_eq "$(cat "$T/out")" "$(ev)/$HMS-checkout-fixed.png" "it prints the path"
  assert_eq "$(pngsize "$(ev)/$HMS-checkout-fixed.png")" "1280x800" "a PNG, 1280 wide by default"
  for a in --headless --remote-debugging-pipe about:blank; do grep -qxF -- "$a" "$T/log/chrome.argv" || fail "Chromium runs with $a"; done
  grep -q -- "^--user-data-dir=$T/tmp/ade\." "$T/log/chrome.argv" || fail "a throwaway profile, in ade's temp folder"
  grep -q 'example.test' "$T/log/chrome.argv" && fail "the address is never an argument of the browser"
  assert_eq "$(cdp Page.navigate)" '{"url": "https://example.test/pay?step=2"}' "it opens the address"
  [ -z "$(ls "$T/tmp")" ] || fail "the temp folder is removed"
  # story A25: on macOS the shot never waits on the login Keychain (the fake uname says Darwin unless FAKE_OS says else)
  for a in --use-mock-keychain --password-store=basic; do grep -qxF -- "$a" "$T/log/chrome.argv" || fail "macOS: Chromium runs with $a"; done
  # story A24 AC3: on macOS one start, its sandbox untouched
  assert_eq "$(grep -c '^--$' "$T/log/chrome.argv")" 1 "macOS: Chromium is started once"
  grep -qxF -- --no-sandbox "$T/log/chrome.argv" && fail "macOS: no --no-sandbox"
  [ ! -e "$T/log/unshare" ] || fail "macOS: no user namespace check"
  shot_fixture; FAKE_CHROME=sandboxfail shot url https://example.test/; assert_eq "$RC" 1 "macOS: a Chromium that exits is not started again"
  assert_eq "$(grep -c '^--$' "$T/log/chrome.argv")" 1 "macOS: no retry"; grep -qxF -- --no-sandbox "$T/log/chrome.argv" && fail "macOS: no --no-sandbox on failure"
  shot_fixture; export FAKE_OS=Linux; shot url https://example.test/; assert_eq "$RC" 0 "Linux shot"
  grep -qE -- '^(--use-mock-keychain|--password-store=basic)$' "$T/log/chrome.argv" && fail "not macOS: no Keychain flags"
  assert_eq "$(grep -c '^--$' "$T/log/chrome.argv")" 1 "Linux: a Chromium that works is started once"
  grep -qxF -- --no-sandbox "$T/log/chrome.argv" && fail "Linux with a user namespace: its sandbox stays on"
  shot_fixture; export FAKE_OS=Linux FAKE_UNSHARE_RC=1; shot url https://example.test/; assert_eq "$RC" 0 "Linux, no user namespace"
  grep -qxF -- --no-sandbox "$T/log/chrome.argv" || fail "Linux without a user namespace: --no-sandbox"; unset FAKE_OS FAKE_UNSHARE_RC
  # the default name is the host; --width and --full-page
  shot_fixture; shot url https://example.test/a --width 800; assert_eq "$RC" 0 "--width"
  assert_eq "$(pngsize "$(ev)/$HMS-example.test.png")" "800x800" "800 wide"
  shot_fixture; shot url https://example.test/a --full-page --name long; assert_eq "$RC" 0 "--full-page"
  assert_eq "$(pngsize "$(ev)/$HMS-long.png")" "1280x2400" "the whole page"; cdp Page.captureScreenshot | grep -q '"captureBeyondViewport": true' || fail "beyond the window"
  assert_contains "$(ev)/$HMS-long.txt" "full page: yes" "the sidecar says so"
  for w in 0 99 9999 abc 80x; do shot_fixture; shot url https://example.test/a --width "$w"; assert_eq "$RC" 2 "--width $w"; no_capture "--width $w"; done
  # a page that does not load, a browser that answers nonsense or nothing: exit 1, nothing saved, no browser left
  shot_fixture; FAKE_CHROME=navfail shot url https://nowhere.test/; assert_eq "$RC" 1 "a page that does not load"
  assert_contains "$T/err" "the page did not load (net::ERR_NAME_NOT_RESOLVED)" "it says why"; [ ! -e "$(ev)" ] || fail "nothing saved"
  shot_fixture; FAKE_CHROME=badpng shot url https://example.test/; assert_eq "$RC" 1 "not a PNG back"; [ ! -e "$(ev)" ] || fail "nothing saved"
  shot_fixture; FAKE_CHROME=silent ADE_SHOT_TIMEOUT=5 shot url https://example.test/; assert_eq "$RC" 1 "a browser that never answers"
  assert_contains "$T/err" "did not answer" "it says so"; ! pgrep -f "$T/pw/chromium-1" > /dev/null || fail "the browser was left running"
  shot_fixture; FAKE_CHROME=noload ADE_SHOT_TIMEOUT=5 shot url https://example.test/slow; assert_eq "$RC" 0 "a page still loading is shot as it is"
  assert_contains "$(ev)/$HMS-example.test.txt" "still loading" "the sidecar says so"
  # no Chromium: one plain line on how to get it; ade downloads nothing
  shot_fixture; PLAYWRIGHT_BROWSERS_PATH="$T/none" shot url https://example.test/; assert_eq "$RC" 1 "no Chromium"
  assert_eq "$(wc -l < "$T/err" | tr -d ' ')" 1 "one line"; assert_contains "$T/err" "npx -y @playwright/mcp install-browser chromium" "how to get it"
  [ ! -e "$(ev)" ] || fail "nothing saved without a browser"
  PLAYWRIGHT_BROWSERS_PATH="$T/none" bash "$ADE" doctor > "$T/out" 2>&1; grep -q '^  chromium missing (extra: ade shot' "$T/out" || fail "ade doctor names a missing Chromium [$(cat "$T/out")]"
  bash "$ADE" doctor > "$T/out" 2>&1; grep -q '^  chromium installed' "$T/out" || fail "ade doctor names Chromium"
}

# AC2: only http, https and file addresses; a file only inside the project; a page cannot pull in a file from outside it
url_addresses() {
  shot_fixture; echo secret > "$T/outside.html"; ln -s "$T/outside.html" "$P/docs/link.html"; mkdir "$P/docs/dir.html"; local a
  for a in "javascript:alert(1)" "chrome://settings" "ftp://example.test/x" "data:text/html,<h1>x</h1>" "view-source:https://example.test" \
           "--headless" "-x" "http://" "https://" "example.test" "https://exa mple.test/" "$(printf 'https://example.test/\nx')" \
           "$(printf 'https://example.test/\033[2J')" "https://user:pw@example.test/" "file:///etc/hosts" "file://$T/outside.html" \
           "file://$P/docs/link.html" "file://$P/docs/missing.html" "file://$P/docs/dir.html" "file://$P/docs/../../outside.html" \
           "file://example.test$P/docs/report.html" "FILE:///etc/hosts" ""; do
    shot url "$a"; assert_eq "$RC" 2 "refused: [$a]"; no_capture "[$a]"; done
  assert_eq "$(wc -l < "$T/err" | tr -d ' ')" 1 "one line"
  # a file inside the project, by its real path
  shot url "file://$P/docs/report.html"; assert_eq "$RC" 0 "a file in the project [$(cat "$T/err")]"
  assert_eq "$(cdp Page.navigate)" "{\"url\": \"file://$P/docs/report.html\"}" "the file's address"
  assert_eq "$(cat "$T/out")" "$(ev)/$HMS-report.html.png" "named after the file"
  # what the page asks for: every request is checked. From a file page: files inside the project and the web, never a file outside
  shot_fixture; printf '%s\n' "file://$P/docs/style.css" "file:///etc/passwd" "https://cdn.example.test/a.js" "file://$T/outside.html" "chrome://gpu" > "$T/log/requests"
  shot url "file://$P/docs/report.html"; assert_eq "$RC" 0 "a file page with requests"
  assert_eq "$(cdp Fetch.continueRequest | tr -d '\n')" '{"requestId": "R0"}{"requestId": "R1"}{"requestId": "R3"}' "the page, a project file and the web go on"
  assert_eq "$(cdp Fetch.failRequest | tr -d '\n')" '{"errorReason": "BlockedByClient", "requestId": "R2"}{"errorReason": "BlockedByClient", "requestId": "R4"}{"errorReason": "BlockedByClient", "requestId": "R5"}' "files outside it are stopped"
  assert_contains "$(ev)/$HMS-report.html.txt" "blocked requests: 3 (a file outside the project: 2; an address that is not http, https or file: 1)" "the sidecar says what was stopped"
  # files of the project that hold keys are not for a page either: .env, keys, .git; and no page reaches a link-local or metadata address
  shot_fixture; mkdir -p "$P/.git/x" "$P/conf"
  printf '%s\n' "file://$P/.env" "file://$P/conf/.env.local" "file://$P/conf/prod.env" "file://$P/conf/server.pem" "file://$P/conf/tls.key" "file://$P/conf/id_fake" \
    "file://$P/.git/config" "file://$P/docs/a.css" "http://169.254.169.254/latest/meta-data/" "http://[fd00:ec2::254]/" "http://metadata.google.internal/x" \
    "https://METADATA.google.internal./x" "http://[::ffff:169.254.1.1]/" "http://[fe80::1]/" "https://example.test/ok.js" > "$T/log/requests"
  shot url "file://$P/docs/report.html"; assert_eq "$RC" 0 "a file page asking for keys [$(cat "$T/err")]"
  assert_eq "$(cdp Fetch.continueRequest | tr -d '\n')" '{"requestId": "R0"}{"requestId": "R8"}{"requestId": "R15"}' "only the page, a plain project file and the web go on"
  assert_eq "$(cdp Fetch.failRequest | grep -c BlockedByClient)" 13 "the rest are stopped"
  assert_contains "$(ev)/$HMS-report.html.txt" "blocked requests: 13 (a key, .env or .git file of the project: 7; a link-local or metadata address: 6)" "the sidecar says what was stopped"
  shot_fixture; printf '%s\n' "http://169.254.169.254/latest/" "https://example.test/ok.js" > "$T/log/requests"; shot url https://example.test/
  assert_eq "$(cdp Fetch.failRequest)" '{"errorReason": "BlockedByClient", "requestId": "R1"}' "a web page reaches no metadata address either"
  # such an address, or such a file, as the page itself: refused before a browser starts
  shot_fixture; cp "$P/docs/report.html" "$P/.env"; cp "$P/docs/report.html" "$P/docs/site.key"; cp "$P/docs/report.html" "$P/.git/page.html"
  printf '%s\n' "http://169.254.169.254/" "http://[fd00:ec2::254]/" "http://metadata.google.internal/" "http://Metadata.Google.Internal./" "http://[fe80::1]/" \
    "http://[::ffff:169.254.169.254]/" "file://$P/.env" "file://$P/docs/site.key" "file://$P/.git/page.html" > "$T/addresses"
  while IFS= read -r a; do shot url "$a"; assert_eq "$RC" 2 "refused: [$a]"; no_capture "[$a]"; done < "$T/addresses"
  # from a web page: no file at all
  shot_fixture; printf '%s\n' "file://$P/docs/report.html" "https://example.test/b.css" > "$T/log/requests"
  shot url "https://example.test/"; assert_eq "$RC" 0 "a web page with requests"
  assert_eq "$(cdp Fetch.failRequest)" '{"errorReason": "BlockedByClient", "requestId": "R1"}' "a web page never reads a file"
}

# AC3: the whole screen, after a yes at a terminal; never without one
screen_asks() {
  shot_fixture; pty_run 'y\n' bash "$ADE" shot screen > "$T/out" 2>&1 || fail "a yes at a terminal [$(cat "$T/out")]"
  assert_contains "$T/out" "captures everything on your screen, including other apps" "it says what it captures, first"
  assert_contains "$T/out" "$(ev)/$HMS-screen.png" "it prints the path"
  assert_eq "$(cat "$T/log/screen")" "screencapture -x $(sed -n 's/^screencapture -x //p' "$T/log/screen")" "macOS: screencapture -x (no sound)"
  assert_eq "$(pngsize "$(ev)/$HMS-screen.png")" "2x3" "the capture is saved"
  assert_contains "$(ev)/$HMS-screen.txt" "redaction: none: a screen shot cannot be redacted" "the sidecar says it is not redacted"
  for a in 'n\n' '\n' 'maybe\n' ''; do shot_fixture; pty_run "$a" bash "$ADE" shot screen > "$T/out" 2>&1; assert_eq "$?" 2 "answer [$a]"
    assert_contains "$T/out" "nothing captured" "it says so"; no_capture "answer [$a]"; done
  # --yes-screen answers nothing at a terminal: the person is still asked; with no terminal there is nobody to ask, flag or not
  shot_fixture; pty_run '' bash "$ADE" shot screen --yes-screen > "$T/out" 2>&1; assert_eq "$?" 2 "--yes-screen at a terminal, no answer"; no_capture "--yes-screen, no answer"
  pty_run 'y\n' bash "$ADE" shot screen --yes-screen --name desk > "$T/out" 2>&1 || fail "--yes-screen and a yes"
  [ -f "$(ev)/$HMS-desk.png" ] || fail "saved"; assert_contains "$T/out" "Capture it now" "--yes-screen is still asked at a terminal"
  shot_fixture; shot screen < /dev/null; assert_eq "$RC" 2 "no terminal"; assert_contains "$T/err" "asks a person at a terminal" "it says why"; no_capture "no terminal"
  shot screen --yes-screen < /dev/null; assert_eq "$RC" 2 "no terminal, with the flag"; no_capture "no terminal, --yes-screen"
  echo y | bash "$ADE" shot screen > /dev/null 2>&1; assert_eq "$?" 2 "a piped yes"; no_capture "a piped yes"
}

# AC4: from an agent session: only with --yes-screen, only where the session's own settings put a permission prompt
# before this very command line, and never where any settings file lets the session skip permissions
ASK='{"permissions": {"ask": ["Bash(*ade shot screen*)"]}}'; BYPASS='{"permissions": {"defaultMode": "bypassPermissions"}}'
agent_fixture() { shot_fixture; export CLAUDECODE=1; mkdir -p "$P/.claude" "$HOME/.claude"; printf '%s\n' "$ASK" > "$P/.claude/settings.json"; }
refused() { shot screen --yes-screen "${@:2}"; assert_eq "$RC" 2 "$1"; assert_contains "$T/err" "nothing captured" "$1: it says so"; no_capture "$1"; }
screen_agent_session() {
  shot_fixture; export CLAUDECODE=1
  shot screen; assert_eq "$RC" 2 "an agent, no flag"; assert_contains "$T/err" "--yes-screen" "it names the flag"
  assert_contains "$T/err" "permission prompt" "it says what the approval is"; no_capture "an agent, no flag"
  pty_run 'y\n' bash "$ADE" shot screen > "$T/out" 2>&1; assert_eq "$?" 2 "an agent cannot answer the question"; no_capture "an agent at a terminal"
  # the flag alone is not an approval: the session's settings must ask the person before this command
  refused "the flag, no settings"; assert_contains "$T/err" "do not ask before" "it says why"
  mkdir -p "$P/.claude"; echo '{"permissions": {"allow": ["Bash(*ade shot screen*)"], "ask": ["Bash(*bin/chat send*)"]}}' > "$P/.claude/settings.json"
  refused "an allow rule is not an ask rule"
  echo 'not json' > "$P/.claude/settings.json"; refused "unreadable settings"
  # the rule and the flag: captured, from a folder below the project too; the sidecar says how it was approved
  agent_fixture; mkdir -p "$P/src/deep"; cd "$P/src/deep" || fail cd
  shot screen --yes-screen; assert_eq "$RC" 0 "the flag and an ask rule [$(cat "$T/err")]"; [ -f "$(ev)/$HMS-screen.png" ] || fail "saved"
  assert_contains "$(ev)/$HMS-screen.txt" "approved: the session's permission prompt" "the sidecar says how it was approved"
  agent_fixture; printf '%s\n' '{"permissions": {"ask": ["Bash(ade shot screen:*)"]}}' > "$P/.claude/settings.local.json"; echo '{}' > "$P/.claude/settings.json"
  shot screen --yes-screen --name desk; assert_eq "$RC" 0 "a prefix rule in settings.local.json [$(cat "$T/err")]"
  # a session that may skip permissions shows no prompt, so nothing approved it: wherever a settings file says so
  agent_fixture; printf '%s\n' '{"permissions": {"ask": ["Bash(*ade shot screen*)"], "defaultMode": "bypassPermissions"}}' > "$P/.claude/settings.json"; refused "bypass in the project's settings.json"
  agent_fixture; printf '%s\n' "$BYPASS" > "$P/.claude/settings.local.json"; refused "bypass in the project's settings.local.json"
  agent_fixture; printf '%s\n' "$BYPASS" > "$HOME/.claude/settings.json"; refused "bypass in ~/.claude/settings.json"
  agent_fixture; mkdir -p "$T/cfg"; printf '%s\n' "$BYPASS" > "$T/cfg/settings.json"; CLAUDE_CONFIG_DIR="$T/cfg" refused "bypass in \$CLAUDE_CONFIG_DIR/settings.json"
  agent_fixture; echo 'not json' > "$HOME/.claude/settings.json"; refused "user settings that cannot be read"
  agent_fixture; echo 'not json' > "$P/.claude/settings.local.json"; refused "local settings that cannot be read"
  # only the session's project counts: not a folder the agent made and entered, not a parent of the project
  agent_fixture; rm "$P/.claude/settings.json"; mkdir -p "$T/x/.claude"; printf '%s\n' '{"permissions": {"ask": ["Bash(*)"]}}' > "$T/x/.claude/settings.json"
  cd "$T/x" || fail cd; refused "a folder the agent made, with its own settings"
  cd "$P" || fail cd; mkdir -p "$T/.claude"; printf '%s\n' "$ASK" > "$T/.claude/settings.json"; refused "a rule only in a parent of the project"; rm -rf "$T/.claude"
  mkdir -p "$P/sub/.claude"; printf '%s\n' "$ASK" > "$P/sub/.claude/settings.json"; cd "$P/sub" || fail cd; refused "a rule only in a folder below the project's root"
  # CLAUDE_PROJECT_DIR, when the session sets it, is the project: its settings count and no other's
  agent_fixture; mkdir -p "$T/other/.claude"; echo '{}' > "$T/other/.claude/settings.json"; CLAUDE_PROJECT_DIR="$T/other" refused "the session's project has no rule"
  agent_fixture; rm "$P/.claude/settings.json"; printf '%s\n' "$ASK" > "$T/other/.claude/settings.json" 2>/dev/null || { mkdir -p "$T/other/.claude"; printf '%s\n' "$ASK" > "$T/other/.claude/settings.json"; }
  CLAUDE_PROJECT_DIR="$T/other" shot screen --yes-screen; assert_eq "$RC" 0 "the session's project has the rule [$(cat "$T/err")]"
  # the rule must match the command line as it is: an exact rule for fewer arguments does not
  agent_fixture; printf '%s\n' '{"permissions": {"ask": ["Bash(ade shot screen --yes-screen)"]}}' > "$P/.claude/settings.json"
  refused "an exact rule, a longer command" --name desk; refused "an exact rule, --tg added" --tg hello
  shot screen --yes-screen; assert_eq "$RC" 0 "an exact rule, the exact command [$(cat "$T/err")]"
  # every sign of an agent session counts, also with the usual three variables removed and a pseudo-terminal made
  local v
  for v in CLAUDE_PID CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_EXECPATH CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID; do
    shot_fixture; export "$v=1"; pty_run 'y\n' bash "$ADE" shot screen --yes-screen < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "$v set, a pseudo-terminal"
    assert_contains "$T/out" "do not ask before" "$v: an agent session"; no_capture "$v"; unset "$v"; done
  unset CLAUDECODE
}

# AC5: the capture tool of each system; a Mac without the Screen Recording permission; ade changes no setting
screen_capture_tools() {
  shot_fixture; FAKE_SCREEN_FAIL=1 pty_run 'y\n' bash "$ADE" shot screen > "$T/out" 2>&1; assert_eq "$?" 1 "macOS refused the capture"
  assert_contains "$T/out" "System Settings > Privacy & Security > Screen Recording" "where to grant it"
  assert_contains "$T/out" "ade changes no setting" "and that ade does not"; [ ! -e "$(ev)" ] || fail "nothing saved"
  # Linux and the ADE Computer: the X display, with import when it is there
  shot_fixture; export FAKE_OS=Linux DISPLAY=:1; minpath import xwd
  PATH="$T/min" pty_run 'y\n' bash "$ADE" shot screen > "$T/out" 2>&1 || fail "Linux, import [$(cat "$T/out")]"
  grep -q "^import -window root .*shot\.png$" "$T/log/screen" || fail "import -window root [$(cat "$T/log/screen")]"
  assert_eq "$(pngsize "$(ev)/$HMS-screen.png")" "2x3" "saved"
  # with xwd alone (the ADE Computer image): the dump becomes a PNG, pixel for pixel
  shot_fixture; export FAKE_OS=Linux DISPLAY=:1; minpath xwd
  PATH="$T/min" pty_run 'y\n' bash "$ADE" shot screen > "$T/out" 2>&1 || fail "Linux, xwd [$(cat "$T/out")]"
  assert_eq "$(cat "$T/log/screen")" "xwd -root -silent" "xwd -root"
  assert_eq "$(python3 - "$(ev)/$HMS-screen.png" <<'PY'
import struct, sys, zlib
d = open(sys.argv[1], "rb").read(); w, h, depth, kind = struct.unpack(">IIBB", d[16:26]); i = 8; idat = b""
while i < len(d):
    n, t = struct.unpack(">I4s", d[i:i + 8]); idat += d[i + 8:i + 8 + n] if t == b"IDAT" else b""; i += 12 + n
raw = zlib.decompress(idat); print(w, h, depth, kind, raw[0], list(raw[1:13]), raw[13], list(raw[14:26]))
PY
)" "4 2 8 2 0 [255, 0, 0, 0, 255, 0, 0, 0, 255, 1, 2, 3] 0 [255, 0, 0, 0, 255, 0, 0, 0, 255, 1, 2, 3]" "the dump's pixels, as a PNG"
  # neither tool, or no display: one plain line, nothing saved
  shot_fixture; export FAKE_OS=Linux DISPLAY=:1; minpath
  PATH="$T/min" pty_run 'y\n' bash "$ADE" shot screen > "$T/out" 2>&1; assert_eq "$?" 1 "no capture tool"
  assert_contains "$T/out" "x11-utils" "how to get one"; [ ! -e "$(ev)" ] || fail "nothing saved"
  shot_fixture; export FAKE_OS=Linux; unset DISPLAY; pty_run 'y\n' bash "$ADE" shot screen > "$T/out" 2>&1; assert_eq "$?" 1 "no display"
  assert_contains "$T/out" "DISPLAY is not set" "it says why"; no_capture "no display"; unset FAKE_OS
}

# AC6: an agent's tab in ade's tmux server, as a picture
agent_shot() {
  shot_fixture; local s; s="$(bash "$ADE" ui --session)"; printf 'building...\n\033[32m3 tests passed\033[0m\n' > "$T/log/pane.raw"
  shot agent 1.2; assert_eq "$RC" 0 "an agent's tab [$(cat "$T/err")]"; assert_eq "$(cat "$T/out")" "$(ev)/$HMS-agent-1.2.png" "the path"
  grep -qxF "tmux capture-pane -p -e -J -t =$s:1" "$T/log/tmux" || fail "capture-pane -p -e of that tab [$(cat "$T/log/tmux")]"
  assert_eq "$(pngsize "$(ev)/$HMS-agent-1.2.png")" "642x310" "a PNG the size of the text"
  assert_contains "$(ev)/$HMS-agent-1.2.txt" "agent: projects/api:1.2" "the sidecar names the tab"
  assert_contains "$T/log/page.html" '<span style="color:#0dbc79">3 tests passed</span>' "colours are kept"
  assert_contains "$T/log/page.html" "default-src 'none'" "the page may load and run nothing"
  # by folder, by the folder's name, by the tab's own name
  for a in projects/web:3 db:2 orchestrator:0 rev:3 ops/api:4; do rm -f "$T/log/tmux"; shot agent "${a%:*}" --name t; assert_eq "$RC" 0 "tab ${a%:*}"
    grep -qxF "tmux capture-pane -p -e -J -t =$s:${a#*:}" "$T/log/tmux" || fail "${a%:*} is tab ${a#*:}"; done
  shot_fixture; shot agent api; assert_eq "$RC" 2 "a name of two tabs"; assert_contains "$T/err" "more than one tab" "it says so"; no_capture "two tabs"
  shot agent billing; assert_eq "$RC" 2 "no such tab"; no_capture "no such tab"
  for a in 'x;id' '$(id)' '-t' 'a b' "$(printf 'a\nb')" '../x' ''; do shot agent "$a"; assert_eq "$RC" 2 "a hostile agent name [$a]"; done
  [ ! -e "$T/log/tmux" ] || ! grep -q capture-pane "$T/log/tmux" || fail "a refused name reached tmux"
  touch "$T/log/nosession"; shot agent 1.2; assert_eq "$RC" 2 "ade ui is not running"; assert_contains "$T/err" "ade ui" "it says how"
}

# AC7: what a terminal shot shows has its keys and tokens hidden first; escape sequences are colours or nothing
agent_redacted() {
  shot_fixture; local run bot sk long pw pk
  run="$(printf 'F%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36)"
  bot="$(printf '%s:%s' 900000001 "$run")"; sk="sk-$(printf 'fake%.0s' 1 2 3 4 5)"; long="$(printf 'Z9%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)"
  pw="hunter-$(printf 'x%.0s' 1 2 3 4)"; pk="$(printf 'TUlJ%.0s' 1 2 3 4 5 6)"
  { printf 'bot %s end\n' "$bot"; printf 'key %s end\n' "$sk"; printf 'run %s end\n' "$long"
    printf 'split sk-fake\033[31mfakefake\033[0mfakefake end\n'; printf 'export DB_PASSWORD=%s\n' "$pw"
    printf 'curl -H "Authorization: Bearer %s"\n' "tok-$pw"; printf 'see https://deploy:%s@example.test/x\n' "$pw"
    printf -- '-----BEGIN RSA PRIVATE KEY-----\n%s\n%s\n-----END RSA PRIVATE KEY-----\nafter the key\n' "$pk" "$pk"
    printf '<script>alert(1)</script> & <img src=x onerror=alert(2)>\n'
    printf '\033]0;title\007\033[2J\033[10;10Hmoved\033]8;;https://evil.example.test\033\\link\033]8;;\033\\\n'
    printf 'bell\007 and \033[1;38;5;196;48;2;1;2;3mloud\033[0m\n'
    # characters that draw nothing (a soft hyphen, a grapheme joiner, a zero-width space) inside a key; cookies
    printf 'soft sk-fake\302\255fake\315\217fakefake end\n'; printf 'zw %s\342\200\213%s end\n' "${long%????????????????????}" "$(printf 'Q7%.0s' 1 2 3 4 5 6 7 8 9 10)"
    printf 'Cookie: sid=%s; theme=dark\n' "c-$pw"; printf 'set-cookie: sid=%s; HttpOnly\n' "c-$pw"; } > "$T/log/pane.raw"
  shot agent db; assert_eq "$RC" 0 "a terminal shot [$(cat "$T/err")]"
  for a in "$bot" "$run" "$sk" "$long" "$pw" "$pk" "fakefakefakefake" "Q7Q7Q7Q7" "theme=dark" "HttpOnly"; do
    grep -qF -- "$a" "$T/log/page.html" && fail "a secret reached the picture: [$a]"; grep -rqF -- "$a" "$(ev)" && fail "a secret reached the evidence folder: [$a]"; done
  for a in "bot <hidden token> end" "key <hidden key> end" "run <hidden> end" "split <hidden key> end" "DB_PASSWORD=<hidden>" "Authorization: <hidden>" \
           "https://<hidden>@example.test/x" "<hidden private key>" "after the key" \
           "soft <hidden key> end" "zw <hidden> end" "Cookie: <hidden>" "set-cookie: <hidden>"; do
    python3 - "$T/log/page.html" "$a" <<'PY' || fail "the picture's text should read [$a]"
import html, re, sys
text = html.unescape(re.sub(r"<[^>]+>", "", open(sys.argv[1], encoding="utf-8").read().split("<pre", 1)[1]))
sys.exit(0 if sys.argv[2] in text else 1)
PY
  done
  # text is text: nothing in the pane becomes markup, and no escape sequence or control character reaches the page
  assert_contains "$T/log/page.html" "&lt;script&gt;alert(1)&lt;/script&gt; &amp; &lt;img src=x onerror=alert(2)&gt;" "markup in the pane is shown as text"
  assert_eq "$(grep -c '<script' "$T/log/page.html")" 0 "no script element"
  LC_ALL=C grep -q "$(printf '[\001-\010\013-\037\177]')" "$T/log/page.html" && fail "a control character reached the page"
  grep -q "evil.example.test\|title" "$T/log/page.html" && fail "a title or link sequence reached the page"
  assert_contains "$T/log/page.html" "moved" "the text after a cursor sequence stays"
  assert_contains "$T/log/page.html" 'color:#ff0000;background:#010203;font-weight:bold">loud</span>' "256 and true colours"
  assert_contains "$(ev)/$HMS-agent-db.txt" "redaction: keys and tokens hidden in the captured text before rendering (12 hidden)" "the sidecar says what was done"
}

# AC8: where shots go: the project's evidence folder, private, named, never overwritten, with a sidecar
evidence_layout() {
  shot_fixture; shot url "https://example.test/pay?token=$(printf 'q%.0s' 1 2 3 4 5 6 7 8 9 10)&step=2" --name "my shot!"; assert_eq "$RC" 0 "a shot"
  local d; d="$(ev)"; assert_eq "$(cat "$T/out")" "$d/$HMS-my-shot.png" "<project>/.ade/evidence/<date>/<time>-<name>.png"
  assert_eq "$(fmode "$P/.ade/evidence")" 700 "the evidence folder"; assert_eq "$(fmode "$d")" 700 "the day's folder"
  assert_eq "$(fmode "$d/$HMS-my-shot.png")" 600 "the PNG"; assert_eq "$(fmode "$d/$HMS-my-shot.txt")" 600 "the sidecar"
  assert_eq "$(cat "$d/$HMS-my-shot.txt")" "what: a page (ade shot url)
when: ${DAY}T10:45:07Z
command: ade shot url https://example.test/pay?token=<hidden>&step=2 --name my shot!
address: https://example.test/pay?token=<hidden>&step=2
http status: 200
size: 1280x800 px, $(wc -c < "$d/$HMS-my-shot.png" | tr -d ' ') bytes
redaction: none: a page shot cannot be redacted; look at it before you share it" "the sidecar"
  assert_eq "$(cat "$P/.ade/evidence/.gitignore")" "*" "shots are not committed by accident"
  assert_eq "$(git -C "$P" status --porcelain --untracked-files=all | grep -c evidence)" 0 "git does not see them"
  # never overwritten: the same second and name again gets its own file
  shot url https://example.test/ --name "my shot!"; assert_eq "$(cat "$T/out")" "$d/$HMS-my-shot-2.png" "a second shot"
  shot url https://example.test/ --name "my shot!"; assert_eq "$(cat "$T/out")" "$d/$HMS-my-shot-3.png" "a third"
  assert_contains "$d/$HMS-my-shot.txt" "token=<hidden>" "the first is untouched"
  # names: sanitised; a hostile one is refused before anything is captured
  shot_fixture; shot url https://example.test/ --name "Über größe 1.2_ok"; assert_eq "$(cat "$T/out")" "$(ev)/$HMS-ber-gr-e-1.2_ok.png" "a sanitised name"
  shot url https://example.test/ --name "$(printf 'n%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70)"
  assert_eq "$(basename "$(cat "$T/out")" | wc -c | tr -d ' ')" "$((7 + 60 + 4 + 1))" "a long name is cut to 60"
  for a in "../../x" "a/b" "..\\x" ".hidden" "-rf" "$(printf 'a\nb')" "$(printf 'a\033[2Jb')" "   " "!!!"; do
    shot_fixture; shot url https://example.test/ --name "$a"; assert_eq "$RC" 2 "a hostile name [$a]"; no_capture "name [$a]"; done
  shot url https://example.test/ --name; assert_eq "$RC" 2 "--name without a name"; shot url https://example.test/ --bogus; assert_eq "$RC" 2 "an unknown option"
  shot bogus; assert_eq "$RC" 2 "an unknown mode"; shot url; assert_eq "$RC" 2 "no address"; shot screen --full-page; assert_eq "$RC" 2 "--full-page is for pages"
  # a linked evidence folder (a checkout is data): refused, nothing written through it
  shot_fixture; mkdir -p "$P/.ade" "$T/elsewhere"; ln -s "$T/elsewhere" "$P/.ade/evidence"; shot url https://example.test/; assert_eq "$RC" 1 "a linked evidence folder"
  assert_contains "$T/err" "symbolic link" "it says why"; [ -z "$(ls "$T/elsewhere")" ] || fail "written through the link"
  shot_fixture; ln -s "$T/log" "$P/.ade"; shot url https://example.test/; assert_eq "$RC" 1 "a linked .ade"; [ ! -e "$T/log/evidence" ] || fail "written through the link"
  shot_fixture; mkdir -p "$P/.ade/evidence" "$T/elsewhere"; ln -s "$T/elsewhere" "$P/.ade/evidence/$DAY"; shot url https://example.test/; assert_eq "$RC" 1 "a linked day folder"
  assert_contains "$T/err" "symbolic link" "it says why"; [ -z "$(ls "$T/elsewhere")" ] || fail "written through the linked day folder"
  # a link planted where the shot or its sidecar would go: never written through; the shot takes the next free name
  shot_fixture; mkdir -p "$(ev)" "$T/elsewhere"; ln -s "$T/elsewhere/a.png" "$(ev)/$HMS-example.test.png"; ln -s "$T/elsewhere/b.txt" "$(ev)/$HMS-example.test-2.txt"
  shot url https://example.test/; assert_eq "$RC" 0 "planted file links"; assert_eq "$(cat "$T/out")" "$(ev)/$HMS-example.test-3.png" "the next free name"
  [ -z "$(ls "$T/elsewhere")" ] || fail "written through a planted file link"
  # inside the hub (no project): the hub's own evidence folder; nowhere: refused
  shot_fixture; cd "$T/hub" || fail cd; shot url https://example.test/; assert_eq "$RC" 0 "in the hub [$(cat "$T/err")]"
  assert_eq "$(cat "$T/out")" "$T/hub/.ade/evidence/$DAY/$HMS-example.test.png" "the hub's evidence folder"
  shot_fixture; unset ADE_HUB; mkdir "$T/nowhere"; cd "$T/nowhere" || fail cd; shot url https://example.test/; assert_eq "$RC" 2 "neither a project nor a hub"
  [ ! -e "$T/log/chrome.argv" ] || fail "captured with nowhere to save"
}

# AC9: --tg sends the saved image to the paired, locked owner through the hub's bin/chat send
tg_sends() {
  shot_fixture; shot url https://example.test/ --name done --tg "the checkout page, fixed"; assert_eq "$RC" 0 "--tg [$(cat "$T/err")]"
  assert_eq "$(sed -n 1p "$T/out")" "$(ev)/$HMS-done.png" "the path first"; assert_contains "$T/out" "sent to you on Telegram" "then that it was sent"
  assert_eq "$(grep '^chat send' "$T/log/chat")" "chat send $(ev)/$HMS-done.png" "bin/chat send with the saved file"
  assert_eq "$(cat "$T/log/caption")" "the checkout page, fixed" "the caption on its stdin"
  # no caption: the shot's own name; a caption is one clean line, keys hidden, cut to 200
  shot_fixture; shot url https://example.test/ --name done --tg; assert_eq "$RC" 0 "--tg alone"; assert_eq "$(cat "$T/log/caption")" "$HMS-done.png" "the default caption"
  shot_fixture; shot agent db --tg --name pane; assert_eq "$RC" 0 "--tg before another option"; [ -f "$(ev)/$HMS-pane.png" ] || fail "--name after --tg is not the caption"
  shot_fixture; shot url https://example.test/ --tg "$(printf 'one\ntwo\t\033[31mthree\007 sk-%s %s' "$(printf 'fake%.0s' 1 2 3 4)" "$(python3 -c 'print("w " * 300)')")"
  assert_eq "$RC" 0 "a caption to clean"; assert_eq "$(cut -c1-34 "$T/log/caption")" "one two three <hidden key> w w w w" "one line, no control characters, keys hidden"
  [ "$(wc -c < "$T/log/caption" | tr -d ' ')" -le 200 ] || fail "the caption is cut to 200"
  # not locked: refused, bin/chat send never runs; the shot is still saved
  shot_fixture; touch "$T/log/unlocked"; shot url https://example.test/ --tg hello; assert_eq "$RC" 2 "a bot that is not locked"
  assert_contains "$T/err" "not locked to you" "it says why"; grep -q '^chat send' "$T/log/chat" && fail "sent through a bot that is not locked"
  [ -f "$(ev)/$HMS-example.test.png" ] || fail "the shot is saved all the same"; assert_contains "$T/err" "the shot is saved" "and it says so"
  # the hub's answer: a refusal (2), a failed send (1), a hub without send yet
  shot_fixture; FAKE_SEND_RC=1 shot url https://example.test/ --tg hello; assert_eq "$RC" 1 "the send failed"; assert_contains "$T/err" "the file was not sent (HTTP 400: Bad Request)" "the hub's reason"
  shot_fixture; FAKE_SEND_RC=2 shot url https://example.test/ --tg hello; assert_eq "$RC" 2 "the hub refused"
  shot_fixture; touch "$T/log/oldhub"; shot url https://example.test/ --tg hello; assert_eq "$RC" 2 "a hub without bin/chat send"; assert_contains "$T/err" "ade update" "it says how to get it"
  shot_fixture; unset ADE_HUB; shot url https://example.test/ --tg hello; assert_eq "$RC" 2 "no hub"; [ -f "$(ev)/$HMS-example.test.png" ] || fail "saved without a hub"
}

# story A24: on Ubuntu 23.10+ AppArmor lets `unshare -U` succeed but the namespace has no rights, so Chromium's sandbox
# fails and it exits at once: it is started once more with --no-sandbox; a Chromium that still exits says why
url_sandbox_retry() {
  # AC1: Linux, unshare succeeds, a Chromium that works only with --no-sandbox: saved, started twice
  shot_fixture; export FAKE_OS=Linux; FAKE_CHROME=sandboxfail shot url https://example.test/ --name retried
  assert_eq "$RC" 0 "the shot is saved on the second start [$(cat "$T/err")]"; pngsize "$(ev)/$HMS-retried.png" > /dev/null || fail "a PNG saved"
  [ -s "$T/log/unshare" ] || fail "ade checked for a user namespace"
  assert_eq "$(grep -c '^--$' "$T/log/chrome.argv")" 2 "started twice"
  assert_eq "$(awk '/^--$/{n++; next} $0=="--no-sandbox"{print n}' "$T/log/chrome.argv")" 1 "--no-sandbox only the second time"
  [ ! -s "$T/err" ] || fail "nothing on stderr when the retry works [$(cat "$T/err")]"
  # AC2: a Chromium that always exits at once: the error names the last lines it wrote; nothing saved; the rest is kept
  shot_fixture; export FAKE_OS=Linux; FAKE_CHROME=dies shot url https://example.test/; assert_eq "$RC" 1 "a Chromium that always exits"
  assert_eq "$(grep -c '^--$' "$T/log/chrome.argv")" 2 "tried with and without its sandbox"
  assert_contains "$T/err" "the browser closed before it answered" "it says what happened"
  assert_contains "$T/err" "No usable sandbox!" "the next-to-last line it wrote"; assert_contains "$T/err" "last line" "its last line"
  grep -q "early line 0$\|early line 0 " "$T/err" && fail "only the last lines"
  grep -q "s3cr3tvalue99" "$T/err" && fail "a key in its output is hidden"
  [ ! -e "$(ev)" ] || fail "nothing saved"
  local log="$HOME/.local/share/ade/chromium.log"; assert_contains "$T/err" "$log" "it names the file with all it wrote"
  assert_contains "$log" "early line 0" "the file keeps the whole output"; assert_eq "$(fmode "$log")" 600 "only you can read it"
  # with no user namespace it already ran with --no-sandbox: one start, the same error
  shot_fixture; export FAKE_OS=Linux FAKE_UNSHARE_RC=1; FAKE_CHROME=dies shot url https://example.test/; assert_eq "$RC" 1 "no namespace, dies"
  assert_eq "$(grep -c '^--$' "$T/log/chrome.argv")" 1 "already without its sandbox: no retry"; assert_contains "$T/err" "No usable sandbox!" "it says why"
  unset FAKE_OS FAKE_UNSHARE_RC
}

# AC10: the help, the README and the changelog say what each mode captures and what cannot be redacted
help_and_docs() {
  shot_fixture; bash "$ADE" help > "$T/out"; grep -qE "^  shot( |$)" "$T/out" || fail "ade help lists shot"
  for a in "" help --help; do bash "$ADE" shot $a > "$T/out" 2>&1 || fail "ade shot $a"
    for s in "ade shot url <address>" "ade shot screen" "ade shot agent <name>" "--tg [caption]" "--yes-screen" ".ade/evidence/" \
             "A page or screen shot cannot be redacted" "everything on your screen"; do assert_contains "$T/out" "$s" "ade shot $a"; done; done
  for s in "ade shot url" "ade shot screen" "ade shot agent" ".ade/evidence/" "cannot be redacted" "--tg"; do assert_contains "$REPO/README.md" "$s" "the README"; done
  grep -q "ade shot" "$REPO/CHANGELOG.md" || fail "the changelog names ade shot"   # any section: a release renames Unreleased
  assert_contains "$REPO/docs/stories/A20-screenshots.md" "tests/test_shot.sh" "the story names its tests"
}

ALL="url_shot url_sandbox_retry url_addresses screen_asks screen_agent_session screen_capture_tools agent_shot agent_redacted evidence_layout tg_sends help_and_docs"
if [ $# -gt 0 ]; then "$1"; echo ok; exit 0; fi
for c in $ALL; do "$c"; done
echo ok
