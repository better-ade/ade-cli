#!/bin/bash
# story U6: ade docs, the plans and specs as they are written: the list, --follow, --web, prefix v, and the words.
# Every outside tool is a fake that logs "name args" to $CALLS (less, fzf, open, xdg-open); ade runs with only those
# fakes and the system's own commands ($T/sys), so a host install never answers. Never the network.
. "$(dirname "$0")/helpers.sh"

mkfake() { printf '#!/bin/bash\necho "%s $*" >> "$CALLS"\n%s\n' "$1" "${2:-}" > "$F/$1"; chmod +x "$F/$1"; }
farm() {   # $T/sys: the system's commands without the ones faked here; this test's own python3 and git
  python3 - "$T/sys" "$(command -v python3)" "$(command -v git)" <<'PY'
import os, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
skip = set("code bat batcat less glow yazi fzf open xdg-open tmux gh gitleaks bun brew apt-get apt sudo".split())
for name, target in (("python3", sys.argv[2]), ("git", sys.argv[3])):
    os.symlink(target, os.path.join(d, name))
for src in ("/usr/bin", "/bin", "/usr/sbin", "/sbin"):
    try: names = os.listdir(src)
    except OSError: continue
    for n in names:
        p = os.path.join(d, n)
        if n not in skip and not os.path.lexists(p) and os.access(os.path.join(src, n), os.X_OK):
            os.symlink(os.path.join(src, n), p)
PY
}
ago() { python3 -c 'import os, sys, time; t = time.time() - float(sys.argv[2]) * 60; os.utime(sys.argv[1], (t, t))' "$1" "$2"; }   # <file> <minutes ago>
docs_fixture() {
  fresh; H="$T/hub"; make_hub "$H" hub; echo "HUB_NAME=acme" > "$H/hub.conf"
  mkdir -p "$H/_bmad-output/stories" "$H/docs" "$H/projects/api/docs" "$H/projects/web" "$H/ops/infra" "$T/proj/docs" "$T/proj/_bmad-output" \
    "$T/outside" "$H/docs/node_modules" "$H/docs/.git" "$H/projects/api/src"
  printf '# Product plan\nThe why.\n' > "$H/_bmad-output/prd.md"; ago "$H/_bmad-output/prd.md" 30
  printf 'intro line\n# Login story\n' > "$H/_bmad-output/stories/S1-login.md"; ago "$H/_bmad-output/stories/S1-login.md" 5
  printf '# The architecture\n' > "$H/docs/architecture.md"; ago "$H/docs/architecture.md" 120
  printf '# Plan for api\n' > "$H/projects/api/PLAN.md"; ago "$H/projects/api/PLAN.md" 2
  printf '# STATE\n- busy\n' > "$H/projects/api/STATE.md"; ago "$H/projects/api/STATE.md" 1
  printf '# API spec\n' > "$H/projects/api/docs/api-spec.md"; ago "$H/projects/api/docs/api-spec.md" 60
  printf '# UX flows\n' > "$T/proj/docs/ux-flows.md"; ago "$T/proj/docs/ux-flows.md" 10
  printf 'no heading here\n' > "$T/proj/_bmad-output/notes.md"; ago "$T/proj/_bmad-output/notes.md" 3000
  printf '# Infra plan\n' > "$H/ops/infra/PLAN.md"; ago "$H/ops/infra/PLAN.md" 400
  printf '# not a doc\n' > "$H/projects/api/src/readme.md"   # outside _bmad-output and docs
  echo "# CANARY-OUTSIDE" > "$T/outside/secret.md"; ln -s "$T/outside/secret.md" "$H/docs/linked.md"
  ln -s "$T/outside" "$H/docs/outdir"; echo "# CANARY-MODULE" > "$H/docs/node_modules/m.md"; echo "# CANARY-GIT" > "$H/docs/.git/g.md"
  printf '| Repo | Checkout | Branch |\n|---|---|---|\n| o/web | %s | main |\n' "$T/proj" > "$H/projects/web/ACCESS.md"
  export ADE_HUB="$H" CALLS="$T/calls"; : > "$CALLS"; F="$T/fakebin"; mkdir -p "$F"; farm
  mkfake less; unset SSH_CONNECTION SSH_CLIENT SSH_TTY TMUX WAYLAND_DISPLAY; export TERM=xterm-256color
}
A() { PATH="$F:$T/sys" "$BASH" "$ADE" "$@"; }
P() { local i="$1"; shift; pty_run "$i" env PATH="$F:$T/sys" COLUMNS=200 LINES=40 "$BASH" "$ADE" "$@"; }

docs_list() {   # AC1
  docs_fixture
  A docs > "$T/out" 2> "$T/err" || { cat "$T/err"; fail "ade docs"; }
  # newest first: title (the first # line, else the file name), folder, kind, age
  sed 's/  */ /g' "$T/out" > "$T/flat"
  local want="1m doc projects/api STATE
2m plan projects/api Plan for api
5m story hub Login story
10m ux projects/web UX flows
30m prd hub Product plan
1h spec projects/api API spec
2h architecture hub The architecture
6h plan ops/infra Infra plan
2d doc projects/web notes.md"
  local l n=0; while IFS= read -r l; do n=$((n + 1))
    case "$(sed -n "${n}p" "$T/flat")" in "$l "*) ;; *) fail "row $n, newest first: got [$(sed -n "${n}p" "$T/flat")] want [$l ...]" ;; esac
  done <<< "$want"
  assert_eq "$(wc -l < "$T/out" | tr -d ' ')" 9 "nine docs, nothing else"
  for l in CANARY linked.md node_modules .git readme.md outdir; do assert_not_contains "$T/out" "$l" "never a doc: $l"; done
  assert_contains "$T/out" "_bmad-output/stories/S1-login.md" "the path, from its root"
  # a folder: only its docs (its checkouts' too)
  A docs projects/web > "$T/out"; assert_eq "$(grep -c . "$T/out")" 2 "projects/web has two docs (its checkout's)"
  A docs web > "$T/out"; assert_eq "$(grep -c . "$T/out")" 2 "a folder's last part names it"
  A docs nope > "$T/out" 2> "$T/err"; assert_eq "$?" 1 "an unknown folder"; assert_contains "$T/err" "no docs in nope" "says so"
  A docs a b > /dev/null 2> "$T/err"; assert_eq "$?" 2 "two folders"; assert_contains "$T/err" "usage: ade docs" "the usage"
  # the numbered picker (no fzf): Enter on a number views it with ade view
  P "3\n" docs > "$T/out" || fail "the picker"
  assert_contains "$T/out" "3) " "numbered"; grep -q "less .*_bmad-output/stories/S1-login.md" "$CALLS" || { cat "$CALLS"; fail "3 opens the third doc in ade view"; }
  : > "$CALLS"; P "x\n\n" docs > "$T/out"; assert_not_contains "$CALLS" "less" "Enter alone views nothing"
  # fzf: typing filters there; Enter views what it prints
  mkfake fzf 'cat > "$CALLS.in"; printf "\n"; sed -n 2p "$CALLS.in"'
  : > "$CALLS"; P "" docs > "$T/out" || fail "the fzf picker"
  grep -q "^fzf " "$CALLS" || fail "fzf picks"; assert_contains "$CALLS.in" "Plan for api" "fzf is given the titles"
  grep -q "less .*projects/api/PLAN.md" "$CALLS" || { cat "$CALLS"; fail "Enter in fzf views the doc"; }
  # ade ui: prefix v is the docs popup, in the U5 table; prefix d stays detach
  A ui --keys < /dev/null > "$T/out"
  grep -q "^  prefix v   docs" "$T/out" || fail "the keys popup lists v"; grep -q "^  prefix d   detach" "$T/out" || fail "d is still detach"
  grep -q "^ui_actions()" "$ADE" || fail "the U5 table"
  sed -n '/^ui_actions()/,/^}/p' "$ADE" > "$T/table"
  grep -q '^ *v - "docs" "display-popup -E -w 90% -h 90% \\"$run docs\\""' "$T/table" || fail "v is in the menu table: $(grep docs "$T/table")"
  grep -q '^ *d - "detach (agents keep running)" "detach-client"' "$T/table" || fail "d stays detach"
}

# follow <keys...>: ade docs --follow on a 24x80 terminal; each argument is typed, then the driver waits (a number:
# that many seconds; "edit": the doc changes as a save would). The screen bytes in $T/screen, the trace in $T/trace.
follow() {
  ADE_TEST_DOCS_TRACE="$T/trace" python3 - "$T" "$1" "$F:$T/sys" "$BASH" "$ADE" "${@:2}" <<'PY'
import fcntl, os, pty, select, struct, sys, termios, time
T, doc, path, bash, ade = sys.argv[1:6]; steps = sys.argv[6:]
pid, fd = pty.fork()
if pid == 0:
    os.environ["PATH"] = path; os.execv(bash, [bash, ade, "docs", "--follow", doc])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
out = open(os.path.join(T, "screen"), "wb")
def pump(s):
    end = time.time() + s
    while time.time() < end:
        if select.select([fd], [], [], 0.05)[0]:
            try: b = os.read(fd, 65536)
            except OSError: return
            if not b: return
            out.write(b); out.flush()
pump(1.5)
for s in steps:
    if s == "edit":
        with open(doc, "a") as f: f.write("appended after the save\n")
    elif s.replace(".", "").isdigit(): pump(float(s))
    else: os.write(fd, s.encode()); pump(0.3)
end = time.time() + 5; rc = None
while time.time() < end:
    p, st = os.waitpid(pid, os.WNOHANG)
    if p: rc = os.WEXITSTATUS(st) if os.WIFEXITED(st) else 99; break
    pump(0.1)
if rc is None: os.kill(pid, 9); rc = "running"
open(os.path.join(T, "rc"), "w").write(str(rc))
PY
}
docs_follow() {   # AC2
  docs_fixture; local d="$H/_bmad-output/long-plan.md" before
  { echo "# Long plan"; for i in $(seq 1 120); do echo "row $i of the plan"; done; } > "$d"
  before="$(cksum < "$d")"
  follow "$d" jjjjjjjjjj 1 edit 3.2 q
  assert_eq "$(cat "$T/rc")" 0 "q stops it"
  assert_contains "$T/screen" "Long plan" "the doc is shown"; assert_contains "$T/screen" "updated " "the status line says it was updated"
  python3 - "$T/trace" <<'PY' || fail "the follow trace"
import re, sys
lines = open(sys.argv[1]).read().split("\n")
checks = [float(l.split()[1]) for l in lines if l.startswith("check ")]
assert len(checks) >= 3, "the mtime was checked %d times" % len(checks)
gaps = [b - a for a, b in zip(checks, checks[1:])]
assert min(gaps) >= 0.95, "two checks %.3f s apart (at most once a second)" % min(gaps)
reloads = [l for l in lines if l.startswith("reload ")]
assert len(reloads) == 1, "one reload for one save: %r" % reloads
assert re.search(r"\btop=10\b", reloads[0]), "the place is kept: %r" % reloads[0]
PY
  # after the save the screen still starts at row 10 of the plan, and the new line was read
  [ "$(tail -1 "$d")" = "appended after the save" ] || fail "the test's own save"
  [ "$(sed '$d' "$d" | cksum)" = "$before" ] || fail "--follow changed the doc (read-only)"
  # a diagram: its code, then the line that says w draws it
  printf '# Flow\n```mermaid\ngraph TD; A-->B\n```\nafter\n' > "$H/docs/flow.md"
  follow "$H/docs/flow.md" 0.5 q; assert_contains "$T/screen" "diagram: w draws it in the browser" "the terminal note under a diagram"
  assert_contains "$T/screen" "graph TD; A-->B" "the diagram's code"
  # ade view too
  : > "$CALLS"; mkfake less 'cat "${@: -1}" > "$CALLS.view"'; A view "$H/docs/flow.md" > /dev/null 2>&1
  assert_contains "$CALLS.view" "diagram: w draws it in the browser" "ade view: the note under a diagram"
  assert_contains "$CALLS.view" "graph TD; A-->B" "ade view: the code"
  # refused: not a doc
  A docs --follow "$T/outside/secret.md" > /dev/null 2> "$T/err"; assert_eq "$?" 1 "a file outside the docs"; assert_contains "$T/err" "not a doc" "says so"
  A docs --follow "$H/docs/linked.md" > /dev/null 2> "$T/err"; assert_eq "$?" 1 "a symlink"
  A docs --follow > /dev/null 2> "$T/err"; assert_eq "$?" 2 "--follow needs a doc"
}

# a pseudo-terminal that stays open until $T/done exists, so an ade web the command started keeps its terminal
held() {
  cat > "$T/held.py" <<'PY'
import fcntl, os, select, subprocess, sys, termios, time
d = sys.argv[1]; m, s = os.openpty()
def ctty(): fcntl.ioctl(s, termios.TIOCSCTTY, 0)
# a shell leads the session, as at a terminal: the command ends, its rc is written, the shell stays until $T/done
lead = 'D="$1"; shift; "$@"; echo $? > "$D/rc.new"; mv "$D/rc.new" "$D/rc"; while [ ! -f "$D/done" ]; do sleep 0.1; done'
p = subprocess.Popen(["sh", "-c", lead, "sh", d] + sys.argv[2:], stdin=subprocess.DEVNULL, start_new_session=True, preexec_fn=ctty)
out = open(os.path.join(d, "tty.out"), "ab", buffering=0)
while not os.path.exists(os.path.join(d, "done")) or p.poll() is None:
    if select.select([m], [], [], 0.05)[0]:
        try: out.write(os.read(m, 4096))
        except OSError: time.sleep(0.05)
PY
  rm -f "$T/done" "$T/rc"; : > "$T/tty.out"
  python3 -I "$T/held.py" "$T" env PATH="$F:$T/sys" TMPDIR="$T/tmp" "$BASH" "$ADE" "$@" > "$T/out" 2> "$T/err" &
  HELD=$!; local i=0; until [ -f "$T/rc" ]; do i=$((i + 1)); [ "$i" -lt 150 ] || fail "ade $* did not end in 15 s"; sleep 0.1; done
}
unhold() { A web --stop > /dev/null 2>&1; touch "$T/done"; wait "$HELD" 2> /dev/null; }
docs_web_link() {   # AC7
  docs_fixture; mkdir -p "$T/tmp"; trap 'unhold; drop_t' EXIT
  local o; for o in open xdg-open; do mkfake "$o" "cp \"\$1\" \"$T/opened.html\""; done; export DISPLAY=:99
  local id; id="$(A docs --id "$H/_bmad-output/prd.md")"; [[ "$id" =~ ^[0-9a-f]{16}$ ]] || fail "a doc's id: $id"
  ADE_WEB_PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')" held docs --web "$H/_bmad-output/prd.md"
  assert_eq "$(cat "$T/rc")" 0 "docs --web"
  assert_contains "$T/out" "started ade web" "says it started ade web"
  local i=0; until grep -q "the code for the page" "$T/tty.out"; do i=$((i + 1)); [ "$i" -lt 100 ] || fail "no code on the terminal"; sleep 0.1; done
  assert_contains "$T/out" "the code for the page is on this terminal" "prints where the code is"
  [ -s "$T/opened.html" ] || fail "the browser was not opened"
  grep -Eo 'url=[^"]*' "$T/opened.html" | head -1 > "$T/link"
  grep -Eq "^url=http://127\.0\.0\.1:[0-9]+/\?k=[A-Za-z0-9_-]{30,}&amp;doc=$id\$|^url=http://127\.0\.0\.1:[0-9]+/\?k=[A-Za-z0-9_-]{30,}&doc=$id\$" "$T/link" || fail "the link carries the token and the doc id only: $(cat "$T/link")"
  assert_not_contains "$CALLS" "k=" "the token is never on a command line"
  grep -q "^open .*/open.html\|^xdg-open .*/open.html" "$CALLS" || fail "opened through a file"
  A web --print-link > "$T/pl"; grep -q '^http://127\.0\.0\.1:' "$T/pl" || fail "the server is on 127.0.0.1"
  # running already: no second server; the link again
  : > "$T/opened.html"; A docs --web "$id" > "$T/out2" 2>&1 || { cat "$T/out2"; fail "docs --web with ade web running"; }
  assert_not_contains "$T/out2" "started" "no second ade web"; grep -q "doc=$id" "$T/opened.html" || fail "opened again"
  # over SSH: the link is printed, never opened
  : > "$T/opened.html"; SSH_CONNECTION="1 2 3 4" A docs --web "$id" > "$T/out2" 2>&1
  grep -Eq "^http://127\.0\.0\.1:[0-9]+/\?k=[A-Za-z0-9_-]+&doc=$id\$" "$T/out2" || fail "over SSH the link is printed: $(cat "$T/out2")"
  [ ! -s "$T/opened.html" ] || fail "over SSH nothing is opened"
  A docs --web "$T/outside/secret.md" > /dev/null 2> "$T/err"; assert_eq "$?" 1 "not a doc"; assert_contains "$T/err" "not a doc" "says so"
  A docs --web 0123456789abcdef > /dev/null 2> "$T/err"; assert_eq "$?" 1 "an id not in the list"
  case "$(sed -n '/^docs_web()/,/^}/p' "$ADE")" in *tailnet*) fail "docs --web never starts --tailnet" ;; esac
  unhold; trap drop_t EXIT
}

u6_docs() {   # AC9: the words
  docs_fixture; local f="$REPO/README.md" s
  sed -n '/^## Read the plan as it is written/,/^## /p' "$f" > "$T/readme"; [ -s "$T/readme" ] || fail "README: the section"
  for s in "ade docs" "prefix v" "--follow" "--web" "Docs" "diagram" "ade setup --diagrams"; do assert_contains "$T/readme" "$s" "README: $s"; done
  A help > "$T/help"; for s in "docs        ade docs [<folder>] | --follow <doc> | --web <doc>" "--follow" "--web"; do assert_contains "$T/help" "$s" "help: $s"; done
  A ui --keys < /dev/null > "$T/keys"; assert_contains "$T/keys" "prefix v   docs" "the keys popup"
  awk '/^## / { on = 0; next } /^- / { on = /\(U6\)/ } on' "$REPO/CHANGELOG.md" > "$T/cl"; [ -s "$T/cl" ] || fail "CHANGELOG: the U6 entry"   # any section: a release renames Unreleased
  for s in "ade docs" "prefix v" "--follow" "--web" "Docs page" "diagram"; do assert_contains "$T/cl" "$s" "CHANGELOG: $s"; done
  A doctor > "$T/doc" 2>&1; grep -q "^  mermaid  missing (extra: " "$T/doc" || fail "ade doctor lists the diagram drawer"
}

# the U6 review's findings: a long heading line, a hard link out, a folder label with control characters, the cap and
# the title cache
docs_limits() {
  docs_fixture; local esc s
  # a 64 KB heading line: listed quickly (a backtracking pattern took ~40 s), and the closing #s still go
  python3 -c 'import sys; open(sys.argv[1], "w").write("# a" + " " * 65000 + "x\n")' "$H/docs/wide.md"
  printf '# Closed title ##\n' > "$H/docs/closed.md"; printf '# Ends in a#\n' > "$H/docs/hash.md"
  s="$(python3 -c 'import time; print(time.time())')"; A docs > "$T/out" 2> "$T/err" || { cat "$T/err"; fail "ade docs"; }
  python3 -c 'import sys, time; d = time.time() - float(sys.argv[1]); assert d < 5, "ade docs took %.1f s" % d' "$s" || fail "a 64 KB heading line is listed quickly"
  assert_contains "$T/out" "docs/wide.md" "the wide doc is listed"
  grep -q "Closed title  .*docs/closed.md" "$T/out" || fail "the closing #s are not the title: $(grep closed.md "$T/out")"
  grep -q "Ends in a#  .*docs/hash.md" "$T/out" || fail "a # in the word stays: $(grep hash.md "$T/out")"
  # a hard link to a file outside the roots: never listed, never followed
  echo "# CANARY-HARD" > "$T/outside/hard.md"; ln "$T/outside/hard.md" "$H/docs/hard.md"
  A docs > "$T/out"; assert_not_contains "$T/out" "hard.md" "a hard link is not a doc"; assert_not_contains "$T/out" "CANARY" "nothing of it"
  A docs --follow "$H/docs/hard.md" > /dev/null 2> "$T/err"; assert_eq "$?" 1 "a hard link is refused"; assert_contains "$T/err" "not a doc" "says so"
  # a folder whose name holds ESC and BEL: its checkout's docs are listed, the label without them
  esc="$(printf 'w\033]0;pwn\007eb')"; mkdir -p "$H/projects/$esc" "$T/proj2/docs"; printf '# Proj two\n' > "$T/proj2/docs/two.md"
  printf '| Repo | Checkout | Branch |\n|---|---|---|\n| o/two | %s | main |\n' "$T/proj2" > "$H/projects/$esc/ACCESS.md"
  A docs > "$T/out"; assert_contains "$T/out" "Proj two" "the checkout's doc is listed"
  if LC_ALL=C grep -q "$(printf '[\033\007]')" "$T/out"; then fail "a control character reached the terminal"; fi
  P "x\n\n" docs > "$T/out"; assert_contains "$T/out" "Proj two" "the numbered picker lists it"
  if LC_ALL=C grep -q "$(printf '\007')" "$T/out"; then fail "the numbered picker printed a BEL"; fi
  # the cap stops the walk; a title is read again only when its file changes
  docs_fixture; mkdir -p "$H/_bmad-output/many" "$H/docs/after"
  python3 - "$H" <<'PY'
import os, sys
for i in range(2001): open(os.path.join(sys.argv[1], "_bmad-output/many/d%04d.md" % i), "w").write("# doc %d\n" % i)
for i in range(300): open(os.path.join(sys.argv[1], "docs/after/a%03d.md" % i), "w").write("# after %d\n" % i)
PY
  sed -n '/^docs_lib() { cat <<.PY.$/,/^PY$/p' "$ADE" | sed '1d;$d' > "$T/docs_lib.py"; [ -s "$T/docs_lib.py" ] || fail "docs_lib"
  s="$(cd "$H" && pwd -P)"; esc="$(printf 'hub\t%s' "$s")"
  ADE_DOC_ROOTS="$esc" python3 - "$T/docs_lib.py" "$s" <<'PY' || fail "the cap and the title cache"
import os, sys, time
g = {}; exec(open(sys.argv[1]).read(), g); hub = sys.argv[2]
seen = []; real_lstat = os.lstat; walked = []; real_walk = os.walk
def lstat(p, *a, **k): seen.append(str(p)); return real_lstat(p, *a, **k)
def walk(top, *a, **k): walked.append(top); return real_walk(top, *a, **k)
reads = []; real_read = g["doc_read"]
def doc_read(real, roots, cap=g["DOC_MAX"]): reads.append(real); return real_read(real, roots, cap)
g["doc_read"] = doc_read; os.lstat = lstat; os.walk = walk
docs = g["doc_list"](g["doc_roots"]())
os.lstat = real_lstat; os.walk = real_walk
assert len(docs) == 2000, "%d docs listed" % len(docs)
assert not [p for p in seen if "/docs/after/" in p], "the walk went on after the cap"
assert os.path.join(hub, "docs") not in walked, "a folder was walked after the cap: %r" % walked
assert len(reads) == 2000, "%d titles read" % len(reads)
del reads[:]; g["doc_list"](g["doc_roots"]())
assert len(reads) == 0, "the relist read %d titles again" % len(reads)
one = os.path.join(hub, "_bmad-output/many/d0001.md"); open(one, "w").write("# changed title\n"); t = time.time() + 5; os.utime(one, (t, t))
docs = g["doc_list"](g["doc_roots"]())
assert len(reads) == 1, "a changed doc's title is read again (%d reads)" % len(reads)
assert [d["title"] for d in docs if d["real"] == one] == ["changed title"], "the new title"
PY
}

ALL="docs_list docs_follow docs_web_link u6_docs docs_limits"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
