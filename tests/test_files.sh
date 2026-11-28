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
skip = set("code bat batcat less glow yazi pdftotext pdftoppm pdfinfo chafa open xdg-open pbcopy wl-copy xclip xsel tmux gh gitleaks bun "
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
  assert_contains "$CALLS" "bat --style=numbers --pager less -RF -- $A_DIR/src/a.ts" "Enter on a search result views it"
  assert_not_contains "$T/screen" "yazi" "the built-in browser is the default; yazi is not even mentioned"
  P "jjq" files "$A_DIR" > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_contains "$T/screen" "a.ts" "j moves the selection and the preview follows it (src/ lists a.ts)"
  P "q" files > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"; assert_contains "$T/screen" "ade files · hub" "no folder: the hub"
  A files "$A_DIR" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "the browser needs a terminal"
  A files "$A_DIR/src/a.ts" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "a file is not a folder"
  ADE_FILES=yazi P "q" files "$A_DIR" 2>&1 | plain > "$T/screen"
  assert_contains "$T/screen" "ADE_FILES=yazi, but yazi is not installed" "asked for and missing: said"; assert_contains "$T/screen" "ade files · hub/projects/api" "then the built-in browser"
  mkfake yazi; : > "$CALLS"; P "q" files "$A_DIR" 2>&1 | plain > "$T/screen"
  assert_not_contains "$CALLS" "yazi" "yazi installed but not asked for: never used (it is not read-only)"; assert_contains "$T/screen" "ade files · hub/projects/api" "the built-in browser"
  : > "$CALLS"; ADE_FILES=yazi P "q" files "$A_DIR" 2>&1 | plain > "$T/screen"
  assert_eq "$(cat "$CALLS")" "yazi -- $A_DIR" "ADE_FILES=yazi: yazi, after --"; assert_contains "$T/screen" "not read-only" "with the warning"
}

pagers_are_secure() {   # review finding 4: less, bat's pager and glow's pager run with LESSSECURE=1 and no LESSOPEN
  fresh; files_fixture; local c; for c in bat glow less; do mkfake "$c" 'echo "'"$c"' env LESSSECURE=${LESSSECURE-unset} LESSOPEN=${LESSOPEN-unset} PAGER=${PAGER-unset}" >> "$CALLS"'; done
  export LESSOPEN='|touch /tmp/ade-lessopen-ran %s' PAGER=most
  A view "$A_DIR/src/a.ts:3" > /dev/null 2>&1; A view "$A_DIR/src/a.ts" > /dev/null 2>&1; A view "$A_DIR/docs/x.md" > /dev/null 2>&1
  assert_eq "$(grep -c '^bat env LESSSECURE=1 LESSOPEN= ' "$CALLS")" 2 "bat: secure less, no LESSOPEN"
  assert_contains "$CALLS" "glow env LESSSECURE=1 LESSOPEN= PAGER=less -r" "glow -p: secure less as its pager"
  assert_contains "$CALLS" "bat --style=numbers --pager less -RF -- $A_DIR/src/a.ts" "bat's pager is always less"
  rm "$F/bat" "$F/glow"; : > "$CALLS"; A view "$A_DIR/src/a.ts" > /dev/null 2>&1; A view "$A_DIR/docs/x.md" > /dev/null 2>&1
  assert_eq "$(grep -c '^less env LESSSECURE=1 LESSOPEN= ' "$CALLS")" 2 "less itself: secure, no LESSOPEN"
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
  : > "$CALLS"; (cd "$A_DIR" && A view weird:5) > /dev/null 2>&1; assert_contains "$CALLS" "bat --style=numbers --pager less -RF -- $A_DIR/weird:5" "a name with a colon that exists is that file"
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
  assert_not_contains "$CALLS" "open -- $A_DIR/tool.sh" "o never runs a program"; assert_contains "$T/screen" "o opens documents only" "and says why"
  mkdir -p "$A_DIR/X.app/Contents/MacOS" "$A_DIR/X.app/Contents/Resources"; echo x > "$A_DIR/X.app/Contents/MacOS/X"; echo x > "$A_DIR/X.app/Contents/Resources/readme.txt"
  ln -s X.app "$A_DIR/report.pdf"; echo x > "$A_DIR/runme"; chmod +x "$A_DIR/runme"; echo x > "$A_DIR/Notes.TXT"; local e f
  for e in fileloc webloc WebLoc inetloc url prefPane mobileconfig dmg zip saver kext scptd ps1 vbs; do echo x > "$A_DIR/f.$e"; done
  echo x > "$A_DIR/X.app/Contents/Resources/readme.pdf"; ln -s X.app/Contents/Resources/readme.pdf "$A_DIR/inner.pdf"; ln -s f.webloc "$A_DIR/safe.pdf"
  for f in report.pdf inner.pdf safe.pdf X.app X.app/Contents/Resources/readme.txt runme f.fileloc f.webloc f.WebLoc f.inetloc f.url f.prefPane f.mobileconfig f.dmg f.zip f.saver f.kext f.scptd f.ps1 f.vbs; do
    : > "$CALLS"; FAKE_OS=Darwin A files --act open "$A_DIR/$f" > "$T/out" 2>&1; assert_eq "$?" 2 "o refuses $f"
    assert_eq "$(cat "$CALLS")" "" "no open call for $f"; assert_contains "$T/out" "f shows it in its folder" "points at f for $f"; done
  : > "$CALLS"; FAKE_OS=Linux A files --act open "$A_DIR/report.pdf" > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "" "no xdg-open through a link to a bundle"
  : > "$CALLS"; FAKE_OS=Darwin A files --act open "$A_DIR/Notes.TXT" > /dev/null 2>&1; assert_contains "$CALLS" "open -- $A_DIR/Notes.TXT" "a document opens (extension case-insensitive)"
  : > "$CALLS"; FAKE_OS=Darwin A files --act reveal "$A_DIR/report.pdf" > /dev/null 2>&1; assert_contains "$CALLS" "open -R -- $A_DIR/report.pdf" "f still reveals it"
  : > "$CALLS"; SSH_CONNECTION="1 2 3 4" FAKE_OS=Darwin P "ofyq" view "$img" > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_not_contains "$CALLS" "open " "over SSH nothing opens here"; assert_not_contains "$CALLS" "pbcopy" "nor copies"
  assert_contains "$T/screen" "over SSH: $img" "the path instead"; SSH_CONNECTION="1 2 3 4" A files --act open "$img" > "$T/out" 2>&1
  assert_contains "$T/out" "scp -s '$(uname -n):$img' ." "and an scp -s line, quoted"
  ln -s img.png "$A_DIR/pic link.png"; SSH_CONNECTION="1 2 3 4" A files --act copy "$A_DIR/pic link.png" > "$T/out" 2>&1
  assert_contains "$T/out" "scp -s '$(uname -n):$img' ." "the scp line names the real path"
  : > "$CALLS"; FAKE_OS=Darwin A files --act copy "$A_DIR/pic link.png" > /dev/null 2>&1
  assert_eq "$(cat "$CALLS.clip")" "'$A_DIR/pic link.png'" "y: a name with a space is copied shell-quoted"
  rm "$F/xclip"; FAKE_OS=Linux A files --act copy "$img" > "$T/out" 2>&1
  assert_contains "$T/out" "no clipboard tool" "no clipboard: says so"; assert_contains "$T/out" "$img" "and shows the path"
  rm "$F/xdg-open"; FAKE_OS=Linux A files --act open "$img" > "$T/out" 2>&1; assert_eq "$?" 2 "no xdg-open"; assert_contains "$T/out" "xdg-open is not installed" "named"
  A files --act open relative.png > /dev/null 2>&1; assert_eq "$?" 2 "only an absolute path"
  TERM_PROGRAM=vscode P "q" view "$img" > "$T/raw" 2>&1; assert_contains "$T/raw" "]8;;file://" "a terminal hyperlink (OSC 8) where supported"
  printf 'MZ\000\000binary' > "$A_DIR/blob.bin"; TERM_PROGRAM=vscode P "q" view "$A_DIR/blob.bin" > "$T/raw" 2>&1
  assert_not_contains "$T/raw" "]8;;file://" "no hyperlink for a binary file"
  printf '\211PNG\r\n\032\n' > "$A_DIR/X.app/Contents/Resources/icon.png"; TERM_PROGRAM=vscode P "q" view "$A_DIR/X.app/Contents/Resources/icon.png" > "$T/raw" 2>&1
  assert_not_contains "$T/raw" "]8;;file://" "nor for a file inside a program"
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
  P "y\r" view "$s" > /dev/null 2>&1; assert_contains "$CALLS" "bat --style=numbers --pager less -RF -- $s" "yes: shown"
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
  assert_not_contains "$T/screen" "ade files · $A_DIR/outdir" "no: not entered"
  P "/outdir\r\ryq" files "$A_DIR" 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "ade files · $A_DIR/outdir" "yes: entered"
  assert_contains "$T/screen" "secret.txt" "and listed"; assert_not_contains "$T/screen" "TOP SECRET" "but a folder allowed by a yes is never previewed"
  assert_contains "$T/screen" "no preview outside the hub and its projects" "and says so"
  echo "HOME SECRET" > "$HOME/notes.txt"; P "hyk\rnq" files "$H" 2>&1 | plain > "$T/screen"
  assert_eq "$(grep -o 'Open it anyway?' "$T/screen" | wc -l | tr -d ' ')" 2 "a yes to a parent of the home folder never allows what is under it: home asks again"
  assert_not_contains "$T/screen" "notes.txt" "and nothing under home is previewed"
  P "hnq" files "$H" 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "outside the hub and its projects" "up from the hub asks"
  printf '| Repo | Checkout | Branch |\n|---|---|---|\n| o/x | / | main |\n| o/y | ~/ | main |\n| o/z | %s | main |\n' "$(dirname "$HOME")" > "$H/projects/api/ACCESS.md"
  A view "$s" < /dev/null > /dev/null 2>&1; assert_eq "$?" 2 "a checkout row of /, the home folder or a parent of it never makes everything inside"
  : > "$CALLS"; A view "$HOME/notes.txt" < /dev/null > /dev/null 2>&1; assert_eq "$?" 2 "a file under home with a row for home's parent: asks"
  assert_not_contains "$CALLS" "bat" "nothing shown"
}

spoofed_names() {   # review finding 7: bidi, zero-width and stray C1 bytes never reach the screen or a link
  fresh; files_fixture; mkfake open; local rlo zw; rlo="$(printf '\342\200\256')"; zw="$(printf '\342\200\213')"
  echo x > "$A_DIR/abc${rlo}gnp.txt"; ln -s "$T/outside/secret.txt" "$A_DIR/x${rlo}y"
  P "q" files "$A_DIR" > "$T/raw" 2>&1; grep -q "abc" "$T/raw" || fail "the spoofed name is listed"
  ! LC_ALL=C grep -q "$rlo" "$T/raw" || fail "no right-to-left override drawn in the explorer"
  A view "$A_DIR/x${rlo}y" < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "x?y is a link to" "the question shows the name with a ?"
  ! LC_ALL=C grep -q "$rlo" "$T/out" || fail "no override in the question"
  A view "$(printf 'no\233such')" < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "no such file" "a missing name"
  ! LC_ALL=C grep -q "$(printf '\233')" "$T/out" || fail "no stray C1 byte in the message"
  A files --act url "https://exa${zw}mple.com" > "$T/out" 2>&1; assert_eq "$?" 2 "a link with a zero-width space is refused"
  A files --act url "https://ex${rlo}moc.com" > /dev/null 2>&1; assert_eq "$?" 2 "and with an override"
  assert_eq "$(cat "$CALLS")" "" "nothing opened"; ! LC_ALL=C grep -q "$zw" "$T/out" || fail "nor drawn"
}

killed_window_cleans_up() {   # review finding 9: closing the window (SIGHUP to the terminal's processes) leaves no copy
  fresh; files_fixture; pdf_fakes; mkfake chafa; mkfake bat 'sleep 30'; export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
  printf 'safe \033]0;x\007 text\n' > "$A_DIR/ctl.txt"
  hup() { python3 -c '
import glob, os, pty, signal, sys, time
pid, fd = pty.fork()
if pid == 0: os.execvp(sys.argv[1], sys.argv[1:])
t = time.time(); had = False
while time.time() - t < 10 and not had:
    try: os.read(fd, 65536)
    except OSError: break
    had = bool(glob.glob(os.path.join(os.environ["TMPDIR"], "ade.*")))
    time.sleep(0.1)
time.sleep(0.5); os.killpg(pid, signal.SIGHUP); os.close(fd); os.waitpid(pid, 0); time.sleep(1)
print("had-tmp" if had else "no-tmp", len(glob.glob(os.path.join(os.environ["TMPDIR"], "ade.*"))))' "$@"
  }
  assert_eq "$(hup env PATH="$F:$T/sys" "$BASH" "$ADE" view "$A_DIR/ctl.txt")" "had-tmp 0" "view_text: the cleaned copy is removed when the window closes"
  assert_eq "$(TERM_PROGRAM=iTerm.app hup env PATH="$F:$T/sys" "$BASH" "$ADE" view "$A_DIR/docs/spec.pdf")" "had-tmp 0" "the PDF page folder too"
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
  for s in "git      installed" "python3  installed" "tmux     missing (required" "gh       missing (required" "gitleaks missing (required" "bun      missing (required" "yazi     missing (extra" \
    "bat      installed" "glow     missing (extra" "poppler  missing (extra" "chafa    missing (extra" "code     missing (extra: Visual Studio Code" "ade setup --tools installs what is missing" "hub doctor x"; do
    assert_contains "$T/out" "$s" "doctor: $s"; done
}

tools_setup_installs_missing() {   # AC8: ade setup --tools, after a yes at a terminal, only what is missing
  fresh; files_fixture; mkfake bat; mkfake brew; mkfake bun   # bun: there (its own install is test_bun.sh)
  FAKE_OS=Darwin P "y\r" setup --tools > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_eq "$(cat "$CALLS")" "brew install tmux gh gitleaks yazi glow poppler chafa visual-studio-code" "brew, only the missing ones (bat is here); Visual Studio Code as its cask"
  assert_contains "$T/screen" "This runs: brew install tmux gh gitleaks yazi glow poppler chafa visual-studio-code" "the question shows the command"
  assert_contains "$T/screen" "yazi only with ADE_FILES=yazi: yazi is neither read-only nor held to the hub" "and what yazi is"
  : > "$CALLS"; FAKE_OS=Darwin P "n\r" setup --tools > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "" "no: nothing installed"
  A setup --tools < /dev/null > "$T/out" 2>&1; assert_eq "$(cat "$CALLS")" "" "no terminal: nothing installed"; assert_contains "$T/out" "run at a terminal: brew install" "says how"
  CLAUDECODE=1 FAKE_OS=Darwin P "y\r" setup --tools > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "" "an agent session: nothing installed"
  mkfake apt-get; mkfake sudo '"$@"'; local pre="sudo apt-get"; [ "$(id -u)" = 0 ] && pre="apt-get"
  FAKE_OS=Linux P "y\r" setup --tools extras > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_contains "$CALLS" "$pre install -y poppler-utils chafa" "apt with Ubuntu's package names, extras only"
  assert_not_contains "$CALLS" "brew" "apt on Linux"; assert_contains "$T/screen" "yazi: not in apt" "yazi named"; assert_contains "$T/screen" "glow: not in apt" "glow named"
  assert_contains "$T/screen" "code: Visual Studio Code is not in apt; get it from https://code.visualstudio.com/download (ade adds no repository" "Visual Studio Code: Microsoft's page, no repository added"
  assert_not_contains "$CALLS" "packages.microsoft.com" "no repository"
  mkfake brew 'exit 1'; FAKE_OS=Darwin P "y\r" setup --tools 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "brew install tmux gh gitleaks" "a failed install"
  assert_contains "$T/screen" "failed (exit 1)" "is said"
  rm "$F/brew"; : > "$CALLS"; FAKE_OS=Darwin P "y\r" setup --tools 2>&1 | plain > "$T/screen"
  assert_contains "$T/screen" "Homebrew is not installed (https://brew.sh)" "no Homebrew: says so"; assert_eq "$(cat "$CALLS")" "" "and runs nothing"
  for c in tmux gh gitleaks yazi glow pdftotext pdftoppm chafa code; do mkfake "$c"; done; : > "$CALLS"
  A setup --tools > "$T/out" 2>&1; assert_contains "$T/out" "everything ade uses is installed" "nothing missing"; assert_eq "$(cat "$CALLS")" "" "nothing run"
  A setup --tools bogus > /dev/null 2>&1; assert_eq "$?" 2 "usage"
}

tools_in_setup_and_installer() {   # AC8: ade setup's first steps and the one-line installer
  fresh; files_fixture; mkfake bat; mkfake brew; mkfake bun   # bun: there (its own install is test_bun.sh)
  FAKE_OS=Darwin P "y\ry\r" setup > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_eq "$(sed -n 1p "$CALLS")" "brew install tmux gh gitleaks" "setup: the required tools, after a yes"
  assert_eq "$(sed -n 2p "$CALLS")" "brew install yazi glow poppler chafa visual-studio-code" "then the extras, as one step"
  assert_contains "$T/screen" "viewer extras" "the extras step is named"
  assert_contains "$T/screen" "yazi is neither read-only nor held to the hub and its projects" "and it says what yazi is"
  : > "$CALLS"; FAKE_OS=Darwin pty_run "y\r" env PATH="$F:$T/sys" "$BASH" "$REPO/install.sh" "$T/prefix" > "$T/raw" 2>&1
  assert_contains "$T/raw" "installed ade" "the installer ran"; assert_eq "$(cat "$CALLS")" "brew install tmux gh gitleaks" "the installer: required tools after a yes"
  : > "$CALLS"; PATH="$F:$T/sys" "$BASH" "$REPO/install.sh" "$T/prefix" > "$T/out" 2>&1 < /dev/null
  assert_eq "$(cat "$CALLS")" "" "piped, no terminal: nothing installed"; assert_contains "$T/out" "missing tools ade needs: tmux gh gitleaks" "but named"
}

# Visual Studio Code: c in the explorer, the viewer and the link picker, ade view --code, ADE_VIEWER=code. The fake
# code logs each argument in brackets, so one argument is seen as one.
code_fake() { printf '#!/bin/bash\n{ printf "code"; printf " [%%s]" "$@"; echo; } >> "$CALLS"\n' > "${1:-$F}/code"; chmod +x "${1:-$F}/code"; }
code_opens_at_line() {   # --code and the keys: the right --goto argument; a folder opens as a folder
  fresh; files_fixture; mkfake bat; code_fake; local a="$A_DIR/src/a.ts"
  A view --code "$a:3:7" < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "--code"; }
  assert_eq "$(cat "$CALLS")" "code [--goto] [$a:3:7]" "the file at its line and column, one argument after the option; no pager"
  : > "$CALLS"; A view --code "$a:3" < /dev/null > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "code [--goto] [$a:3:1]" "a line: column 1"
  : > "$CALLS"; (cd "$A_DIR" && A view --code src/a.ts < /dev/null) > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "code [--goto] [$a:1:1]" "no line: 1:1, the path absolute"
  : > "$CALLS"; A view --code "$A_DIR/weird:5" < /dev/null > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "code [--goto] [$A_DIR/weird:5:1:1]" "a name that ends in :5 stays the name"
  : > "$CALLS"; A view --code "$A_DIR/src" < /dev/null > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "code [$A_DIR/src]" "a folder opens as a folder"
  : > "$CALLS"; P "/a.ts\rcq" files "$A_DIR" > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_contains "$CALLS" "code [--goto] [$a:1:1]" "c in the explorer"; assert_contains "$T/screen" "opened in Visual Studio Code: $a" "and says so"
  assert_contains "$T/screen" "o app · c code · f reveal" "the explorer's key line lists c"
  : > "$CALLS"; P "cq" files "$A_DIR" > /dev/null 2>&1; assert_contains "$CALLS" "code [$A_DIR/docs]" "c on a folder"
  : > "$CALLS"; P "cq" view "$A_DIR/img.png" > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_contains "$CALLS" "code [--goto] [$A_DIR/img.png:1:1]" "c in the viewer"; assert_contains "$T/screen" "o open · c code · f reveal" "the viewer's key line lists c"
  A help > "$T/out" 2>&1; assert_contains "$T/out" "ade view [--code] <path[:line[:col]]>" "the help: --code"
  assert_contains "$T/out" "ADE_VIEWER=code: code and text files open in" "the help: ADE_VIEWER"; assert_contains "$T/out" "images, PDFs and Markdown keep the built-in viewer" "and what stays"
  A ui --keys 2> /dev/null | grep -q "in files and links, c: open in your editor" || fail "the help popup lists c"
  A files --act code "$a" x > /dev/null 2>&1; assert_eq "$?" 2 "a line is a number"; A files --act open "$a" 3 > /dev/null 2>&1; assert_eq "$?" 2 "only code takes a line"
  : > "$CALLS"; A files --act code "$a" 9 2 > "$T/out" 2>&1; assert_eq "$(cat "$CALLS")" "code [--goto] [$a:9:2]" "the action the keys run, with a line and column"
}
code_names_are_data() {   # spaces, a leading -, shell characters: one argument, as it is; a line break is refused
  fresh; files_fixture; mkfake bat; code_fake; local n
  for n in "my file.ts" "-dash.ts" "--goto.ts" 'a;b $(touch pwned) `id` "q'"'"'.ts' "sp ace:2"; do
    echo x > "$A_DIR/$n"; : > "$CALLS"; A view --cwd "$A_DIR" --code -- "$n" < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "[$n]"; }
    assert_eq "$(cat "$CALLS")" "code [--goto] [$A_DIR/$n:1:1]" "[$n] is one argument, after the option, never an option itself"
  done
  [ ! -e pwned ] && [ ! -e "$A_DIR/pwned" ] || fail "nothing in a name ran"
  : > "$CALLS"; A view --cwd "$A_DIR" --code -- "my file.ts:4:2" < /dev/null > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "code [--goto] [$A_DIR/my file.ts:4:2]" "with a line and column"
  n="$(printf 'two\nlines.ts')"; echo x > "$A_DIR/$n"; : > "$CALLS"; A view --code "$A_DIR/$n" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "a name with a line break is refused"
  assert_eq "$(cat "$CALLS")" "" "and nothing opens"
}
code_asks_outside() {   # a path outside the roots asks first, as o does
  fresh; files_fixture; mkfake bat; code_fake; local s="$T/outside/secret.txt"
  A view --code "$s" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "outside, no terminal: refused"; assert_contains "$T/out" "outside the hub and its projects" "says why"
  A files --act code "$s" < /dev/null > /dev/null 2>&1; assert_eq "$?" 2 "the key's action too"; A view --code "$A_DIR/leak.txt" < /dev/null > /dev/null 2>&1; assert_eq "$?" 2 "and an escaping link"
  P "n\r" view --code "$s" > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "" "no: nothing opens"
  CLAUDECODE=1 P "y\r" view --code "$s" > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "" "an agent session cannot answer"
  P "y\r" view --code "$s" > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "code [--goto] [$s:1:1]" "yes: opened"
  : > "$CALLS"; A view --code "$T/proj/main.go:2" < /dev/null > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "code [--goto] [$T/proj/main.go:2:1]" "a checkout is inside: no question"
}
code_missing_or_local() {   # no code: one line, the built-in viewer; a code inside the project is never run; over SSH the path
  fresh; files_fixture; mkfake bat; local a="$A_DIR/src/a.ts"
  A view --code "$a:3" < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "never an error"; }
  assert_eq "$(cat "$T/out")" "ade: Visual Studio Code (the code command) is not installed; ade setup --tools installs it; the built-in viewer instead" "one line"
  assert_contains "$CALLS" "bat --style=numbers --highlight-line 3 --pager less -RF +3g -- $a" "then the built-in viewer, at the line"
  P "/a.ts\rcq" files "$A_DIR" 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "is not installed; ade setup --tools installs it; the path: $a" "c says so and offers the path"
  mkdir -p "$A_DIR/bin"; code_fake "$A_DIR/bin"; : > "$CALLS"
  PATH="$A_DIR/bin:$F:$T/sys" "$BASH" "$ADE" view --code "$a" < /dev/null > "$T/out" 2>&1 || fail "a local code is not an error either"
  assert_contains "$T/out" "the code command on PATH is inside the hub or project being viewed, so ade does not run it" "a code in the project is refused"
  assert_not_contains "$CALLS" "code [" "and never run"; assert_contains "$CALLS" "bat " "the built-in viewer instead"
  ln -s "$A_DIR/bin/code" "$F/code"; : > "$CALLS"; A view --code "$a" < /dev/null > "$T/out" 2>&1
  assert_contains "$T/out" "inside the hub or project being viewed" "a link into the project is refused too"; assert_not_contains "$CALLS" "code [" "not run"
  rm "$F/code"; code_fake; : > "$CALLS"; unset DISPLAY
  SSH_CONNECTION="1 2 3 4" A files --act code "$a" > "$T/out" 2>&1; assert_eq "$(cat "$CALLS")" "" "over SSH with no display: nothing opens"
  assert_contains "$T/out" "over SSH with no display, Visual Studio Code cannot open here; the path: $a" "it says so and offers the path"
  SSH_CONNECTION="1 2 3 4" TERM_PROGRAM=vscode A files --act code "$a" > /dev/null 2>&1; assert_contains "$CALLS" "code [--goto] [$a:1:1]" "in Visual Studio Code's own terminal it opens"
  : > "$CALLS"; SSH_CONNECTION="1 2 3 4" DISPLAY=:0 A files --act code "$a" > /dev/null 2>&1; assert_contains "$CALLS" "code [--goto]" "and with a display"
  printf '#!/bin/bash\nexit 1\n' > "$F/code"; A files --act code "$a" > "$T/out" 2>&1; assert_contains "$T/out" "Visual Studio Code did not open it (code failed); the path: $a" "a code that fails is said"
}
code_by_default() {   # ADE_VIEWER=code: code and text files, at a terminal; images, PDFs and Markdown keep the built-in viewer
  fresh; files_fixture; mkfake bat; mkfake glow; code_fake; export ADE_VIEWER=code; local a="$A_DIR/src/a.ts"
  P "" view "$a:3" > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "code [--goto] [$a:3:1]" "a code file opens in Visual Studio Code"
  : > "$CALLS"; P "" view "$A_DIR/docs/x.md" > /dev/null 2>&1; assert_contains "$CALLS" "glow -p -- $A_DIR/docs/x.md" "Markdown keeps the built-in viewer"; assert_not_contains "$CALLS" "code [" "not code"
  : > "$CALLS"; P "q" view "$A_DIR/img.png" 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "image: 2x1" "an image too"; assert_not_contains "$CALLS" "code [" "not code"
  : > "$CALLS"; A view "$a" < /dev/null > /dev/null 2>&1; assert_contains "$CALLS" "bat " "not at a terminal: the built-in viewer"; assert_not_contains "$CALLS" "code [" "never a window from a script"
  rm "$F/code"; : > "$CALLS"; P "" view "$a" 2>&1 | plain > "$T/screen"; assert_contains "$T/screen" "is not installed; ade setup --tools installs it; the built-in viewer instead" "no code: said in one line"
  assert_contains "$CALLS" "bat " "and the built-in viewer is used"
}
code_in_link_picker() {   # a number then c: the file in Visual Studio Code at its line and column
  fresh; files_fixture; mkfake bat; code_fake; local d
  d="${TMPDIR:-/tmp}"; d="$(mktemp -d "${d%/}/ade.XXXXXX")"; printf 'see src/a.ts:3:7 and docs/x.md\n' > "$d/pane"; printf '%s\n' "$A_DIR" > "$d/cwd"
  P "1c\r" ui --links "$d" > "$T/raw" 2>&1; plain < "$T/raw" > "$T/screen"
  assert_contains "$T/screen" "a number then c: in your editor" "the question says how"
  assert_eq "$(cat "$CALLS")" "code [--goto] [$A_DIR/src/a.ts:3:7]" "the pick, at its line and column"; rm -rf "$d"
}

# story U1: ADE_EDITOR picks the editor c runs (code, a JetBrains launcher, or a {path} {line} {col} template); in a
# JetBrains terminal the IDE's launcher is found. Each fake logs its name and each argument in brackets.
ed_fake() { printf '#!/bin/bash\n{ printf "%s"; printf " [%%s]" "$@"; echo; } >> "$CALLS"\n' "$1" > "${2:-$F}/$1"; chmod +x "${2:-$F}/$1"; }
JB_LAUNCHERS="idea pycharm webstorm goland rider clion phpstorm rubymine fleet"
editor_choice() {   # AC1
  fresh; files_fixture; mkfake bat; code_fake; local a="$A_DIR/src/a.ts" l n v
  ADE_EDITOR=code A view --code "$a:3:7" < /dev/null > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "code [--goto] [$a:3:7]" "ADE_EDITOR=code: as today"
  for l in $JB_LAUNCHERS; do ed_fake "$l"; : > "$CALLS"
    ADE_EDITOR="$l" A view --code "$a:3:7" < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "$l"; }
    assert_eq "$(cat "$CALLS")" "$l [--line] [3] [--column] [7] [$a]" "ADE_EDITOR=$l: --line, --column, the path one argument"; done
  : > "$CALLS"; ADE_EDITOR=idea A files --act code "$a" 9 2 > "$T/out" 2>&1; assert_eq "$(cat "$CALLS")" "idea [--line] [9] [--column] [2] [$a]" "the key's action"
  assert_contains "$T/out" "opened in idea: $a" "and says where"
  : > "$CALLS"; ADE_EDITOR=idea A view --code "$A_DIR/src" < /dev/null > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "idea [$A_DIR/src]" "a folder opens as a folder"
  : > "$CALLS"; ADE_EDITOR="$F/idea" A view --code "$a:4" < /dev/null > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "idea [--line] [4] [--column] [1] [$a]" "a launcher's full path"
  ed_fake subl; ed_fake nvim
  : > "$CALLS"; ADE_EDITOR='subl {path}:{line}:{col}' A view --code "$a:3:7" < /dev/null > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "subl [$a:3:7]" "a template"
  : > "$CALLS"; ADE_EDITOR='nvim  +{line}   {path}' A view --code "$a:5" < /dev/null > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "nvim [+5] [$a]" "words split on spaces, no shell"
  for n in "my file.ts" 'a;b $(touch pwned) `id` "q'"'"'.ts' "-dash.ts"; do
    echo x > "$A_DIR/$n"; : > "$CALLS"; (cd "$T" && ADE_EDITOR='nvim {path}' A view --cwd "$A_DIR" --code -- "$n" < /dev/null > /dev/null 2>&1)
    assert_eq "$(cat "$CALLS")" "nvim [$A_DIR/$n]" "[$n] is one argument in a template"
    : > "$CALLS"; (cd "$T" && ADE_EDITOR=idea A view --cwd "$A_DIR" --code -- "$n" < /dev/null > /dev/null 2>&1)
    assert_eq "$(cat "$CALLS")" "idea [--line] [1] [--column] [1] [$A_DIR/$n]" "[$n] is one argument for a launcher"
  done
  for v in 'subl {path}; touch pwned' 'subl {path} | touch pwned' 'subl {path} & touch pwned' 'subl $HOME/{path}' 'subl `touch pwned` {path}' 'subl {path}>pwned'; do
    : > "$CALLS"; (cd "$T" && ADE_EDITOR="$v" A view --code "$a" < /dev/null > "$T/out" 2>&1)
    assert_eq "$(grep -c 'ADE_EDITOR' "$T/out")" 1 "[$v] refused in one line"; assert_contains "$T/out" "ADE_EDITOR is refused" "[$v] says so"
    assert_not_contains "$CALLS" "subl" "[$v] never run"; assert_contains "$CALLS" "bat " "[$v] the built-in viewer instead"
  done
  [ ! -e "$T/pwned" ] && [ ! -e pwned ] || fail "nothing in ADE_EDITOR ran"
  : > "$CALLS"; ADE_EDITOR=vim A files --act code "$a" > "$T/out" 2>&1; assert_contains "$T/out" "ADE_EDITOR is refused" "an unknown word"; assert_contains "$T/out" "the path: $a" "and the path is offered"
  : > "$CALLS"; ADE_EDITOR='subl {line}' A files --act code "$a" > "$T/out" 2>&1; assert_contains "$T/out" "ADE_EDITOR is refused" "a template needs {path}"
  : > "$CALLS"; ADE_EDITOR='nosuch {path}' A files --act code "$a" > "$T/out" 2>&1; assert_contains "$T/out" "nosuch is not installed" "a template's program not on PATH"
  mkdir -p "$A_DIR/bin"; ed_fake idea "$A_DIR/bin"; : > "$CALLS"
  ADE_EDITOR=idea PATH="$A_DIR/bin:$F:$T/sys" "$BASH" "$ADE" files --act code "$a" > "$T/out" 2>&1
  assert_contains "$T/out" "inside the hub or project being viewed" "a launcher inside the project is never run"; assert_eq "$(cat "$CALLS")" "" "not run"
}
editor_detected() {   # AC2
  fresh; files_fixture; mkfake bat; local a="$A_DIR/src/a.ts"
  ed_fake goland; ed_fake pycharm; code_fake; export TERMINAL_EMULATOR=JetBrains-JediTerm
  A files --act code "$a" 9 2 > "$T/out" 2>&1; assert_eq "$(cat "$CALLS")" "pycharm [--line] [9] [--column] [2] [$a]" "the first JetBrains launcher found"
  rm "$F/pycharm" "$F/goland"; : > "$CALLS"; A files --act code "$a" 9 2 > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "code [--goto] [$a:9:2]" "no launcher: code"
  rm "$F/code"; : > "$CALLS"; A files --act code "$a" 9 2 > "$T/out" 2>&1; assert_eq "$(cat "$CALLS")" "" "nothing: nothing runs"
  assert_contains "$T/out" "the path: $a:9:2" "it prints the path at its line"
  ed_fake idea; code_fake; unset TERMINAL_EMULATOR; : > "$CALLS"; A files --act code "$a" 9 2 > /dev/null 2>&1; assert_eq "$(cat "$CALLS")" "code [--goto] [$a:9:2]" "outside a JetBrains terminal: code, as today"
  A setup --check < /dev/null > "$T/out" 2>&1; assert_eq "$(grep '^editor:' "$T/out")" "editor: code (Visual Studio Code; c in ade files and ade view)" "setup --check: code"
  TERMINAL_EMULATOR=JetBrains-JediTerm A setup --check < /dev/null > "$T/out" 2>&1; assert_eq "$(grep '^editor:' "$T/out")" "editor: idea (JetBrains, found in this terminal; c in ade files and ade view)" "setup --check: the launcher"
  ADE_EDITOR='subl {path}' A setup --check < /dev/null > "$T/out" 2>&1; assert_eq "$(grep '^editor:' "$T/out")" "editor: subl (ADE_EDITOR; not installed)" "setup --check: ADE_EDITOR"
  ADE_EDITOR='x;y {path}' A setup --check < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "editor: refused (ADE_EDITOR is refused" "setup --check: refused"
  rm "$F/code" "$F/idea"; A setup --check < /dev/null > "$T/out" 2>&1; assert_eq "$(grep '^editor:' "$T/out")" "editor: none (c prints the path; set ADE_EDITOR or install code)" "setup --check: none"
}

ALL="editor_choice editor_detected code_opens_at_line code_names_are_data code_asks_outside code_missing_or_local code_by_default code_in_link_picker explorer_lists_searches_previews explorer_in_real_tmux view_at_line pagers_are_secure pdf_pages pdf_real_tools open_reveal_copy link_picker outside_asks_first spoofed_names killed_window_cleans_up read_only tools_doctor tools_setup_installs_missing tools_in_setup_and_installer"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
