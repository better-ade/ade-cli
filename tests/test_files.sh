#!/bin/bash
# story A15: ade files, ade view, the link picker (ade ui prefix l), o/f/y, and the tools ade installs. Every outside
# tool is a fake that logs "name args" to $CALLS (bat, less, glow, yazi, pdftotext, pdftoppm, chafa, open, xdg-open,
# pbcopy, xclip, brew, apt-get, sudo, tmux, uname); ade runs with only those fakes and the system's own commands
# ($T/sys, without the tools above), so a host install never answers. Keys are typed on a pseudo-terminal (pty_run);
# the explorer is also captured from a real tmux pane where tmux is installed.
. "$(dirname "$0")/helpers.sh"

mkfake() { printf '#!/bin/bash\necho "%s $*" >> "$CALLS"\n%s\n' "$1" "${2:-}" > "$F/$1"; chmod +x "$F/$1"; }
farm() {   # $T/sys: the system's commands without the ones this story fakes; this test's own bash, python3 and git
  python3 - "$T/sys" "$(command -v python3)" "$(command -v git)" <<'PY'
import os, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
skip = set("bat batcat less glow yazi pdftotext pdftoppm pdfinfo chafa open xdg-open pbcopy wl-copy xclip xsel tmux gh "
           "brew apt-get apt sudo uname".split())
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
files_fixture() {
  H="$T/hub"; make_hub "$H" hub; echo "HUB_NAME=acme" > "$H/hub.conf"; A_DIR="$H/projects/api"
  mkdir -p "$A_DIR/src" "$A_DIR/docs" "$H/projects/web" "$T/outside" "$T/proj"
  for i in $(seq 1 60); do if [ "$i" = 3 ]; then echo "const three = 3"; else echo "line $i"; fi; done > "$A_DIR/src/a.ts"
  echo "# X doc" > "$A_DIR/docs/x.md"; echo "# Y doc" > "$A_DIR/docs/y.md"; printf '%%PDF-1.4 fixture\n' > "$A_DIR/docs/spec.pdf"
  printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000\000\000\002\000\000\000\001\010\002\000\000\000' > "$A_DIR/img.png"
  echo "plain words" > "$A_DIR/weird:5"; printf '#!/bin/sh\necho hi\n' > "$A_DIR/tool.sh"; chmod +x "$A_DIR/tool.sh"
  echo "TOP SECRET" > "$T/outside/secret.txt"; ln -s "$T/outside/secret.txt" "$A_DIR/leak.txt"; ln -s "$T/outside" "$A_DIR/outdir"
  echo "package main" > "$T/proj/main.go"
  printf '| Repo | Checkout | Branch |\n|---|---|---|\n| o/web | %s | main |\n' "$T/proj" > "$H/projects/web/ACCESS.md"
  export ADE_HUB="$H" CALLS="$T/calls"; : > "$CALLS"; F="$T/fakebin"; mkdir -p "$F"; farm
  printf '#!/bin/bash\nif [ $# -eq 0 ] || [ "$1" = -s ]; then echo "${FAKE_OS:-Darwin}"; else exec "%s" "$@"; fi\n' "$(command -v uname)" > "$F/uname"; chmod +x "$F/uname"
  unset SSH_CONNECTION SSH_CLIENT SSH_TTY TMUX TERM_PROGRAM LC_TERMINAL KITTY_WINDOW_ID WAYLAND_DISPLAY VTE_VERSION WT_SESSION
  export TERM=xterm-256color
}
A() { PATH="$F:$T/sys" "$BASH" "$ADE" "$@"; }   # ade with only the fakes and the system's own commands
P() { local i="$1"; shift; pty_run "$i" env PATH="$F:$T/sys" COLUMNS=250 LINES=40 "$BASH" "$ADE" "$@"; }   # on a terminal (250x40), keys typed ahead
plain() { python3 -c 'import re, sys; sys.stdout.write(re.sub(r"\x1b(\[[0-9;?]*[A-Za-z]|\][^\x07\x1b]*(\x07|\x1b\\)|_G[^\x1b]*\x1b\\)", "", sys.stdin.read()))'; }
pdf_fakes() {
  mkfake pdftotext 'printf "page one alpha\nmore of one\n\fpage two beta\n\f"'
  mkfake pdftoppm 'for a; do l="$a"; done; printf "\211PNG\r\n\032\nfake" > "$l-$2.png"'
}
tree_state() {   # every name, type, mode, size, mtime, link target and checksum under the fixture folders
  python3 - "$T/hub" "$T/proj" "$T/outside" <<'PY'
import hashlib, os, sys
for root in sys.argv[1:]:
    for dp, dns, fns in os.walk(root):
        dns.sort()
        for n in sorted(dns + fns) + ["."]:
            p = os.path.join(dp, n); st = os.lstat(p)
            extra = os.readlink(p) if os.path.islink(p) else (hashlib.sha256(open(p, "rb").read()).hexdigest() if os.path.isfile(p) else "")
            print(p, oct(st.st_mode), st.st_size, st.st_mtime_ns, extra)
PY
}

explorer_lists_searches_previews() {   # AC1
  fresh; files_fixture; mkfake bat
  P "/a.ts\r\rq" files "$A_DIR" > "$T/raw" 2>&1 || { cat "$T/raw"; fail "explorer exit"; }
  plain < "$T/raw" > "$T/screen"
  for s in "ade files · hub/projects/api" "docs/" "src/" "spec.pdf" "img.png" "src/a.ts" "const three = 3"; do assert_contains "$T/screen" "$s" "explorer shows: $s"; done
  assert_contains "$CALLS" "bat --style=numbers -- $A_DIR/src/a.ts" "Enter on a search result views it"
  assert_contains "$T/screen" "yazi is not installed" "the fallback says which tool is missing"
  assert_contains "$T/screen" "ade setup --tools installs it" "and how to get it"
  P "jjq" files "$A_DIR" > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_not_contains "$T/screen" "yazi is not installed" "the hint is shown once"
  assert_contains "$T/screen" "a.ts" "j moves the selection and the preview follows it (src/ lists a.ts)"
  P "q" files > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"; assert_contains "$T/screen" "ade files · hub" "no folder: the hub"
  A files "$A_DIR" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "the browser needs a terminal"
  A files "$A_DIR/src/a.ts" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "a file is not a folder"
  mkfake yazi; : > "$CALLS"; P "q" files "$A_DIR" > /dev/null 2>&1
  assert_eq "$(cat "$CALLS")" "yazi -- $A_DIR" "yazi when installed, after --"
}

explorer_in_real_tmux() {   # AC1 on a real terminal screen: a tmux pane at 100x30, captured
  command -v tmux > /dev/null 2>&1 || { echo "skip: no tmux"; return 0; }
  fresh; files_fixture; local real_tmux; real_tmux="$(command -v tmux)"; export TMUX_TMPDIR="$T"
  "$real_tmux" -L "ade-files-$$" -f /dev/null new-session -d -s f -x 100 -y 30 "env PATH='$F:$T/sys' '$BASH' '$ADE' files '$A_DIR'; sleep 30"
  local i; for i in $(seq 1 40); do "$real_tmux" -L "ade-files-$$" capture-pane -p -t f > "$T/screen"; grep -q "src/" "$T/screen" && break; sleep 0.25; done
  "$real_tmux" -L "ade-files-$$" send-keys -t f / a . t s Enter; sleep 1
  "$real_tmux" -L "ade-files-$$" capture-pane -p -t f > "$T/screen2"; "$real_tmux" -L "ade-files-$$" kill-server 2> /dev/null
  assert_contains "$T/screen" "ade files · hub/projects/api" "the title on a real screen: the folder as its root names it"
  assert_contains "$T/screen" "docs/" "the listing"
  assert_contains "$T/screen" "x.md" "the preview of the selected folder"
  assert_contains "$T/screen2" "src/a.ts" "the search result"; assert_contains "$T/screen2" "const three = 3" "and its preview"
  [ "$(wc -l < "$T/screen" | tr -d ' ')" -le 30 ] || fail "the frame fits the pane"
}

view_at_line() {   # AC2
  fresh; files_fixture; mkfake bat 'for a; do l="$a"; done; cat -- "$l" > "$CALLS.seen"'
  (cd "$A_DIR" && A view src/a.ts:42) > "$T/out" 2>&1 || { cat "$T/out"; fail "view exit"; }
  assert_contains "$CALLS" "bat --style=numbers --highlight-line 42 --pager less -RF +42g -- $A_DIR/src/a.ts" "bat opens at line 42"
  : > "$CALLS"; (cd "$A_DIR" && A view src/a.ts:42:7) > /dev/null 2>&1; assert_contains "$CALLS" "--highlight-line 42 " "path:line:col"
  : > "$CALLS"; (cd "$A_DIR" && A view weird:5) > /dev/null 2>&1; assert_contains "$CALLS" "bat --style=numbers -- $A_DIR/weird:5" "a name with a colon that exists is that file"
  printf 'safe \033]0;owned\007 text\n' > "$A_DIR/ctl.txt"; (cd "$A_DIR" && A view ctl.txt) > "$T/out" 2>&1
  grep -q "safe" "$CALLS.seen" && ! LC_ALL=C grep -q "$(printf '\033')" "$CALLS.seen" || fail "control characters never reach the viewer"
  assert_contains "$T/out" "control characters" "and it says so"
  rm "$F/bat"; mkfake less 'for a; do l="$a"; done; cat -- "$l" > "$CALLS.seen"'; : > "$CALLS"
  (cd "$A_DIR" && A view src/a.ts:42) > "$T/out" 2>&1 || fail "less exit"
  assert_contains "$CALLS" "less -N +42g -- $A_DIR/src/a.ts" "the less fallback opens at line 42"
  assert_contains "$T/out" "bat is not installed" "the fallback names bat"
  (cd "$A_DIR" && A view src/a.ts) > "$T/out" 2>&1; assert_not_contains "$T/out" "bat is not installed" "once"
  mkfake batcat; : > "$CALLS"; (cd "$A_DIR" && A view src/a.ts:7) > /dev/null 2>&1; assert_contains "$CALLS" "batcat --style=numbers --highlight-line 7" "Ubuntu's batcat is bat"
  rm "$F/batcat"; mkfake glow; : > "$CALLS"; A view "$A_DIR/docs/x.md" > /dev/null 2>&1; assert_eq "$(head -1 "$CALLS")" "glow -p -- $A_DIR/docs/x.md" "Markdown through glow"
  rm "$F/glow"; : > "$CALLS"; A view "$A_DIR/docs/x.md" > "$T/out" 2>&1; assert_eq "$(head -1 "$CALLS")" "less -- $A_DIR/docs/x.md" "else plain"
  assert_contains "$T/out" "glow is not installed" "naming glow"
  A view "$A_DIR/nope.ts:3" > "$T/out" 2>&1; assert_eq "$?" 2 "a missing file"; assert_contains "$T/out" "no such file" "says so"
  A view > /dev/null 2>&1; assert_eq "$?" 2 "usage"
  mkfifo "$A_DIR/pipe"; A view "$A_DIR/pipe" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 1 "a pipe is never opened (it would block)"
  assert_contains "$T/out" "cannot read" "says so"
}

pdf_pages() {   # AC3
  fresh; files_fixture; pdf_fakes; local pdf="$A_DIR/docs/spec.pdf"
  P "nq" view "$pdf" > "$T/raw" 2>&1 || { cat "$T/raw"; fail "pdf exit"; }; plain < "$T/raw" > "$T/screen"
  for s in "spec.pdf · page 1/2" "page one alpha" "spec.pdf · page 2/2" "page two beta"; do assert_contains "$T/screen" "$s" "text pages: $s"; done
  assert_not_contains "$CALLS" "pdftoppm" "no page images without graphics"
  assert_contains "$CALLS" "pdftotext -layout -- $pdf -" "pdftotext after --"
  P "g2\rq" view "$pdf" 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "page 2/2" "g goes to a page"
  P "/beta\rq" view "$pdf" 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "page 2/2" "/ searches"; assert_contains "$T/screen" "found on page 2" "and says where"
  P "/zebra\rq" view "$pdf" 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "not found: zebra" "a miss is said"
  A view "$pdf" < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "page one alpha" "no terminal: every page as text"; assert_contains "$T/out" "page two beta" "both pages"
  mkfake chafa 'echo CHAFA-DRAWN'; : > "$CALLS"
  TERM_PROGRAM=iTerm.app P "q" view "$pdf" > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_contains "$CALLS" "pdftoppm -f 1 -l 1 -png -r 110 -- $pdf " "graphics: the page as an image"
  grep -q "^chafa .* -- .*page-1.png$" "$CALLS" || { cat "$CALLS"; fail "drawn by chafa"; }
  assert_contains "$T/screen" "CHAFA-DRAWN" "on screen"; assert_not_contains "$T/screen" "page one alpha" "instead of the text"
  rm "$F/chafa"; TERM_PROGRAM=iTerm.app P "q" view "$pdf" > "$T/raw" 2>&1; assert_contains "$T/raw" "]1337;File=inline=1" "iTerm2's own protocol without chafa"
  TERM=xterm-kitty P "q" view "$pdf" > "$T/raw" 2>&1; assert_contains "$T/raw" "_Gf=100,a=T" "kitty's protocol"
  : > "$CALLS"; SSH_CONNECTION="1 2 3 4" TERM_PROGRAM=iTerm.app P "q" view "$pdf" 2>&1 | plain > "$T/screen"
  assert_contains "$T/screen" "page one alpha" "over SSH always text"; assert_not_contains "$CALLS" "pdftoppm" "no images over SSH"
  rm "$F/pdftoppm"; TERM_PROGRAM=iTerm.app P "q" view "$pdf" 2>&1 | plain > "$T/screen"
  assert_contains "$T/screen" "pdftoppm (poppler) is not installed" "graphics without pdftoppm: says so"; assert_contains "$T/screen" "page one alpha" "and shows text"
  rm "$F/pdftotext"; A view "$pdf" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "no pdftotext"
  assert_contains "$T/out" "pdftotext is not installed (poppler)" "names the tool"; assert_contains "$T/out" "ade setup --tools" "and how to get it"
}

pdf_real_tools() {   # AC3 with the real pdftotext, where poppler is installed
  command -v pdftotext > /dev/null 2>&1 || { echo "skip: no pdftotext"; return 0; }
  fresh; files_fixture; python3 - "$A_DIR/real.pdf" <<'PY'
import sys
pages = ["first page alpha", "second page beta"]; n = len(pages)
objs = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [%s] /Count %d >>" % (" ".join("%d 0 R" % (3 + 2 * i) for i in range(n)), n)]
for i, t in enumerate(pages):
    s = "BT /F1 18 Tf 50 700 Td (%s) Tj ET" % t
    objs.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %d 0 R /Resources << /Font << /F1 %d 0 R >> >> >>" % (4 + 2 * i, 3 + 2 * n))
    objs.append("<< /Length %d >>\nstream\n%s\nendstream" % (len(s), s))
objs.append("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
out, offs = b"%PDF-1.4\n", []
for i, o in enumerate(objs):
    offs.append(len(out)); out += ("%d 0 obj\n%s\nendobj\n" % (i + 1, o)).encode()
x = len(out); out += ("xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)).encode() + b"".join(("%010d 00000 n \n" % o).encode() for o in offs)
out += ("trailer << /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, x)).encode()
open(sys.argv[1], "wb").write(out)
PY
  bash "$ADE" view "$A_DIR/real.pdf" < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "real pdf"; }
  assert_contains "$T/out" "page 1/2" "real pages"; assert_contains "$T/out" "first page alpha" "real text"; assert_contains "$T/out" "second page beta" "page two"
}

open_reveal_copy() {   # AC4
  fresh; files_fixture; mkfake open; mkfake pbcopy 'cat > "$CALLS.clip"'; mkfake xdg-open; mkfake xclip 'cat > "$CALLS.clip"'; local img="$A_DIR/img.png"
  FAKE_OS=Darwin P "ofyq" view "$img" > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_contains "$T/screen" "image: 2x1" "no graphics: the size"; assert_contains "$T/screen" "(o to open)" "and o"
  assert_contains "$CALLS" "open -- $img" "o: open"; assert_contains "$CALLS" "open -R -- $img" "f: open -R"; assert_contains "$CALLS" "pbcopy" "y: the clipboard"
  assert_eq "$(cat "$CALLS.clip")" "$img" "the path on the clipboard (stdin)"
  : > "$CALLS"; FAKE_OS=Linux P "ofyq" view "$img" > /dev/null 2>&1
  assert_contains "$CALLS" "xdg-open $img" "Linux o"; assert_contains "$CALLS" "xdg-open $A_DIR" "Linux f: the folder"
  assert_contains "$CALLS" "xclip -selection clipboard" "Linux y"; assert_eq "$(cat "$CALLS.clip")" "$img" "the path"
  : > "$CALLS"; FAKE_OS=Darwin P "/img\rfq" files "$A_DIR" > /dev/null 2>&1; assert_contains "$CALLS" "open -R -- $img" "f in the explorer"
  : > "$CALLS"; FAKE_OS=Darwin P "/tool\roq" files "$A_DIR" > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_not_contains "$CALLS" "open -- $A_DIR/tool.sh" "o never runs a program"; assert_contains "$T/screen" "is a program" "and says why"
  : > "$CALLS"; SSH_CONNECTION="1 2 3 4" FAKE_OS=Darwin P "ofyq" view "$img" > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_not_contains "$CALLS" "open " "over SSH nothing opens here"; assert_not_contains "$CALLS" "pbcopy" "nor copies"
  assert_contains "$T/screen" "over SSH: $img" "the path instead"; assert_contains "$T/screen" "scp " "and a copy command"
  rm "$F/xclip"; FAKE_OS=Linux A files --act copy "$img" > "$T/out" 2>&1
  assert_contains "$T/out" "no clipboard tool" "no clipboard: says so"; assert_contains "$T/out" "$img" "and shows the path"
  rm "$F/xdg-open"; FAKE_OS=Linux A files --act open "$img" > "$T/out" 2>&1; assert_eq "$?" 2 "no xdg-open"; assert_contains "$T/out" "xdg-open is not installed" "named"
  A files --act open relative.png > /dev/null 2>&1; assert_eq "$?" 2 "only an absolute path"
  TERM_PROGRAM=vscode P "q" view "$img" > "$T/raw" 2>&1; assert_contains "$T/raw" "]8;;file://" "a terminal hyperlink (OSC 8) where supported"
}

link_picker() {   # AC5
  fresh; files_fixture; mkfake bat; mkfake glow; mkfake open; export PANE_TEXT="$T/pane.txt" PANE_CWD="$A_DIR"
  cat > "$F/tmux" <<'X'
#!/bin/bash
[ "$1" = -L ] && shift 2
echo "tmux $*" >> "$CALLS"
case "$1" in capture-pane) cat "$PANE_TEXT" ;; display-message) echo "$PANE_CWD" ;; esac
exit 0
X
  chmod +x "$F/tmux"
  printf '%s\n' "Edited src/a.ts:3 and see ./docs/x.md for details." "Spec in [t](docs/y.md); PR https://example.com/pr/1." \
    "not-a-file.ts:9 and /nonexistent/path.md, $(printf '\033[31m')red" > "$PANE_TEXT"
  A ui --menu links %3 > "$T/out" 2>&1 || { cat "$T/out"; fail "menu links"; }
  assert_contains "$CALLS" "capture-pane -p -J -S -2000 -t %3" "the pane and 2000 lines of its scroll-back"
  local d; d="$(sed -n "s/.*ui --links '\([^']*\)'.*/\1/p" "$CALLS" | tail -1)"; [ -f "$d/pane" ] || { cat "$CALLS"; fail "the capture"; }
  assert_contains "$CALLS" "display-popup -E" "in a popup"
  : > "$CALLS"; FAKE_OS=Darwin P "1\r2\r3\r4\r" ui --links "$d" > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  for s in "   1  src/a.ts:3" "   2  ./docs/x.md" "   3  docs/y.md" "   4  https://example.com/pr/1"; do assert_contains "$T/screen" "$s" "listed: $s"; done
  assert_not_contains "$T/screen" "not-a-file" "only files that exist"; assert_not_contains "$T/screen" "nonexistent" "nor missing paths"
  assert_contains "$CALLS" "bat --style=numbers --highlight-line 3 --pager less -RF +3g -- $A_DIR/src/a.ts" "path:line at the line, against the agent's folder"
  assert_contains "$CALLS" "glow -p -- $A_DIR/docs/x.md" "./path"; assert_contains "$CALLS" "glow -p -- $A_DIR/docs/y.md" "a Markdown link"
  assert_contains "$CALLS" "open https://example.com/pr/1" "a URL in the browser"
  [ ! -e "$d" ] || fail "the capture is removed afterwards"
  A ui --links /etc > /dev/null 2>&1; assert_eq "$?" 2 "only ade's own capture folder"
  A ui --menu links 'x;y' > /dev/null 2>&1; assert_eq "$?" 2 "only a pane id"
  : > "$PANE_TEXT"; A ui --menu links %3 > /dev/null 2>&1; d="$(sed -n "s/.*ui --links '\([^']*\)'.*/\1/p" "$CALLS" | tail -1)"
  P "" ui --links "$d" 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "no file paths or links in this pane" "an empty pane says so"
}

outside_asks_first() {   # AC6
  fresh; files_fixture; mkfake bat; local s="$T/outside/secret.txt"
  A view "$s" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "outside, no terminal: refused"
  assert_contains "$T/out" "outside the hub and its projects" "says why"; assert_not_contains "$CALLS" "bat" "nothing shown"
  P "n\r" view "$s" > /dev/null 2>&1; assert_not_contains "$CALLS" "bat" "no: nothing shown"
  P "y\r" view "$s" > /dev/null 2>&1; assert_contains "$CALLS" "bat --style=numbers -- $s" "yes: shown"
  : > "$CALLS"; CLAUDECODE=1 P "y\r" view "$s" 2>&1 | plain > "$T/screen"; assert_not_contains "$CALLS" "bat" "an agent session cannot answer"
  assert_contains "$T/screen" "refused inside" "and says so"
  A view "$A_DIR/leak.txt" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "an escaping link: refused"
  assert_contains "$T/out" "is a link to $s" "names the target"
  A view "$T/proj/main.go" < /dev/null > /dev/null 2>&1 || fail "a checkout ACCESS.md lists is inside"
  assert_contains "$CALLS" "-- $T/proj/main.go" "shown without a question"
  P "/leak\rq" files "$A_DIR" 2>&1 | plain > "$T/screen"
  assert_contains "$T/screen" "leak.txt (outside: not followed) -> " "the link is shown"; assert_contains "$T/screen" "not followed; Enter asks first" "in the preview"
  assert_contains "$T/screen" "│ $s" "with its target"
  assert_not_contains "$T/screen" "TOP SECRET" "never followed"
  P "/outdir\r\rnq" files "$A_DIR" 2>&1 | plain > "$T/screen"
  assert_contains "$T/screen" "outdir is a link to $T/outside, outside the hub and its projects. Open it anyway? [y/N]" "entering an escaping folder asks"
  assert_not_contains "$T/screen" "ade files · outside" "no: not entered"
  P "/outdir\r\ryq" files "$A_DIR" 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "ade files · outside" "yes: entered"
  assert_contains "$T/screen" "secret.txt" "and listed"
  P "hnq" files "$H" 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "outside the hub and its projects" "up from the hub asks"
  printf '| Repo | Checkout | Branch |\n|---|---|---|\n| o/x | / | main |\n| o/y | ~/ | main |\n' > "$H/projects/api/ACCESS.md"
  A view "$s" < /dev/null > /dev/null 2>&1; assert_eq "$?" 2 "a checkout row of / or the home folder never makes everything inside"
}

read_only() {   # AC7
  fresh; files_fixture; pdf_fakes; local c; for c in bat glow chafa open pbcopy; do mkfake "$c"; done
  before="$(tree_state)"
  { P "/a.ts\r\rjjkhlq" files "$A_DIR"; P "/img\rofyq" files "$A_DIR"; P "nng\rq" view "$A_DIR/docs/spec.pdf"
    TERM_PROGRAM=iTerm.app P "nq" view "$A_DIR/docs/spec.pdf"; P "ofyq" view "$A_DIR/img.png"; A view "$A_DIR/src/a.ts:3"
    A view "$A_DIR/docs/x.md"; P "y\r" view "$A_DIR/leak.txt"; P "/outdir\r\ryq" files "$A_DIR"; A view "$A_DIR/weird:5"
    local r="${TMPDIR:-/tmp}" d; d="$(mktemp -d "${r%/}/ade.XXXXXX")"; printf 'see src/a.ts:3 and https://example.com\n' > "$d/pane"
    echo "$A_DIR" > "$d/cwd"; P "1\r2\r" ui --links "$d"; } > /dev/null 2>&1
  assert_eq "$(tree_state)" "$before" "nothing under the hub, the checkout or the outside folder changed"
}

tools_doctor() {   # AC8: ade doctor lists every tool
  fresh; files_fixture; mkfake bat; printf '#!/bin/bash\necho "hub doctor $*"\n' > "$H/bin/doctor"; chmod +x "$H/bin/doctor"
  A doctor x > "$T/out" 2>&1 || { cat "$T/out"; fail "doctor exit"; }
  for s in "git      installed" "python3  installed" "tmux     missing (required" "gh       missing (required" "yazi     missing (extra" \
    "bat      installed" "glow     missing (extra" "poppler  missing (extra" "chafa    missing (extra" "ade setup --tools installs what is missing" "hub doctor x"; do
    assert_contains "$T/out" "$s" "doctor: $s"; done
}

tools_setup_installs_missing() {   # AC8: ade setup --tools, after a yes at a terminal, only what is missing
  fresh; files_fixture; mkfake bat; mkfake brew
  FAKE_OS=Darwin P "y\r" setup --tools > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_eq "$(cat "$CALLS")" "brew install tmux gh yazi glow poppler chafa" "brew, only the missing ones (bat is here)"
  assert_contains "$T/screen" "This runs: brew install tmux gh yazi glow poppler chafa" "the question shows the command"
  : > "$CALLS"; FAKE_OS=Darwin P "n\r" setup --tools > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "" "no: nothing installed"
  A setup --tools < /dev/null > "$T/out" 2>&1; assert_eq "$(cat "$CALLS")" "" "no terminal: nothing installed"; assert_contains "$T/out" "run at a terminal: brew install" "says how"
  CLAUDECODE=1 FAKE_OS=Darwin P "y\r" setup --tools > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "" "an agent session: nothing installed"
  mkfake apt-get; mkfake sudo '"$@"'; local pre="sudo apt-get"; [ "$(id -u)" = 0 ] && pre="apt-get"
  FAKE_OS=Linux P "y\r" setup --tools extras > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_contains "$CALLS" "$pre install -y poppler-utils chafa" "apt with Ubuntu's package names, extras only"
  assert_not_contains "$CALLS" "brew" "apt on Linux"; assert_contains "$T/screen" "yazi: not in apt" "yazi named"; assert_contains "$T/screen" "glow: not in apt" "glow named"
  mkfake brew 'exit 1'; FAKE_OS=Darwin P "y\r" setup --tools 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "brew install tmux gh" "a failed install"
  assert_contains "$T/screen" "failed (exit 1)" "is said"
  rm "$F/brew"; : > "$CALLS"; FAKE_OS=Darwin P "y\r" setup --tools 2>&1 | plain > "$T/screen"
  assert_contains "$T/screen" "Homebrew is not installed (https://brew.sh)" "no Homebrew: says so"; assert_eq "$(cat "$CALLS")" "" "and runs nothing"
  for c in tmux gh yazi glow pdftotext pdftoppm chafa; do mkfake "$c"; done; : > "$CALLS"
  A setup --tools > "$T/out" 2>&1; assert_contains "$T/out" "everything ade uses is installed" "nothing missing"; assert_eq "$(cat "$CALLS")" "" "nothing run"
  A setup --tools bogus > /dev/null 2>&1; assert_eq "$?" 2 "usage"
}

tools_in_setup_and_installer() {   # AC8: ade setup's first steps and the one-line installer
  fresh; files_fixture; mkfake bat; mkfake brew
  FAKE_OS=Darwin P "y\ry\r" setup > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_eq "$(sed -n 1p "$CALLS")" "brew install tmux gh" "setup: the required tools, after a yes"
  assert_eq "$(sed -n 2p "$CALLS")" "brew install yazi glow poppler chafa" "then the extras, as one step"
  assert_contains "$T/screen" "viewer extras" "the extras step is named"
  : > "$CALLS"; FAKE_OS=Darwin pty_run "y\r" env PATH="$F:$T/sys" "$BASH" "$REPO/install.sh" "$T/prefix" > "$T/raw" 2>&1
  assert_contains "$T/raw" "installed ade" "the installer ran"; assert_eq "$(cat "$CALLS")" "brew install tmux gh" "the installer: required tools after a yes"
  : > "$CALLS"; PATH="$F:$T/sys" "$BASH" "$REPO/install.sh" "$T/prefix" > "$T/out" 2>&1 < /dev/null
  assert_eq "$(cat "$CALLS")" "" "piped, no terminal: nothing installed"; assert_contains "$T/out" "missing tools ade needs: tmux gh" "but named"
}

ALL="explorer_lists_searches_previews explorer_in_real_tmux view_at_line pdf_pages pdf_real_tools open_reveal_copy link_picker outside_asks_first read_only tools_doctor tools_setup_installs_missing tools_in_setup_and_installer"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
