#!/bin/bash
# story A18: the guided first run. `ade` with no hub, `ade setup` (the guide) and `ade hub new`, driven on a
# pseudo-terminal (pty_run) with fakes for claude, gh, brew, xdg-open and the hub template; ade runs with only those
# fakes and the system's own commands ($T/sys), so a host install never answers. Never the network, never the real
# gh or Claude sign-in. UPDATE_GOLDEN=1 rewrites tests/golden/guide-80.txt (the happy path at 80 columns).
. "$(dirname "$0")/helpers.sh"

farm() {   # $T/sys: the system's commands without the ones faked here; this test's own python3 and git
  python3 - "$T/sys" "$(command -v python3)" "$(command -v git)" <<'PY'
import os, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
skip = set("claude gh brew apt-get apt sudo uname open xdg-open tmux yazi bat batcat glow pdftotext pdftoppm chafa "
           "security pass gpg pbcopy xclip xsel wl-copy".split())
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
# the fakes: each logs "name args" to $CALLS. Sign-in state is a file: $T/claude.in, $T/gh.in.
# gh auth login prints GitHub's one-time code lines, opens $GH_BROWSER when set, says whether it had the terminal,
# and fails when $T/gh.fail exists. claude with no auth arguments is the guided session: it makes projects/$MAKE_PROJECT.
fakes() {
  F="$T/fakebin"; mkdir -p "$F"; export CALLS="$T/calls" FT="$T"; : > "$CALLS"; farm
  cat > "$F/claude" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$CALLS"
case "${1:-} ${2:-}" in
  "auth status") [ -f "$FT/claude.in" ] ;;
  "auth login") [ -f "$FT/claude.fail" ] && exit 1; touch "$FT/claude.in" ;;
  *) echo "(the guided Claude Code session runs here)"; [ -z "${MAKE_PROJECT:-}" ] || mkdir -p "projects/$MAKE_PROJECT" ;;
esac
STUB
  cat > "$F/gh" <<'STUB'
#!/bin/bash
echo "gh $*" >> "$CALLS"; env | grep -E '^GH_(TOKEN|ENTERPRISE_TOKEN|BROWSER)=' | sed 's/^/gh env /' >> "$CALLS"
case "${1:-} ${2:-}" in
  "auth status") [ -f "$FT/gh.in" ] ;;
  "auth login") if [ -t 0 ] && [ -t 1 ]; then echo "gh had the terminal" >> "$CALLS"; fi
    echo "! First copy your one-time code: WDJB-MJHT"; echo "Open this URL to continue in your web browser: https://github.com/login/device"
    [ -z "${GH_BROWSER:-}" ] || "$GH_BROWSER" https://github.com/login/device
    if [ -f "$FT/gh.fail" ]; then echo "error: authentication timed out" >&2; exit 1; fi
    touch "$FT/gh.in"; echo "Logged in as tester" ;;
  "api user") [ -f "$FT/gh.in" ] && printf '%s\n' "$(cat "$FT/gh.login" 2> /dev/null || echo tester)" ;;
  "repo create") git clone -q "$FT/template" "$3" ;;
esac
STUB
  printf '#!/bin/bash\necho "xdg-open $*" >> "$CALLS"\n' > "$F/xdg-open"
  printf '#!/bin/bash\necho "brew $*" >> "$CALLS"\n[ "$1 $2" = "install gh" ] && cp "$FT/gh.real" "$FT/fakebin/gh"\nexit 0\n' > "$F/brew"
  printf '#!/bin/bash\nif [ $# -eq 0 ] || [ "$1" = -s ]; then echo Darwin; else exec "%s" "$@"; fi\n' "$(command -v uname)" > "$F/uname"
  local c; for c in tmux yazi bat glow pdftotext pdftoppm chafa; do printf '#!/bin/bash\nexit 0\n' > "$F/$c"; done   # the other tools: there
  chmod +x "$F"/*; cp "$F/gh" "$T/gh.real"
  make_template; export ADE_HUB_TEMPLATE_URL="$T/template"; unset DISPLAY ADE_COMPUTER_MARKER
  mkdir -p "$T/cwd"
}
# the hub template: bin/init lists four personas and writes hub.conf (or fails while $T/init.fail exists); bin/agent
# passes the live test; bin/keys and bin/chat are quiet
make_template() {
  local d="$T/template"; mkdir -p "$d/bin"; git init -q "$d"; : > "$d/bin/lib.sh"
  cat > "$d/bin/init" <<'STUB'
#!/bin/bash
if [ "${1:-}" = --list ]; then printf '%-28s %s\n' devops-sre "DevOps / Site Reliability Engineer" staff-software-engineer "Staff Software Engineer" \
  tech-lead "Tech Lead" technical-product-manager "Technical Product Manager"; exit 0; fi
printf 'init' >> "$FT/init.log"; printf ' [%s]' "$@" >> "$FT/init.log"; echo >> "$FT/init.log"
[ -t 0 ] && echo "init had a terminal" >> "$FT/init.log"
if [ -f "$FT/init.fail" ]; then echo "init: the persona files are missing" >&2; exit 1; fi
n=""; while [ $# -gt 0 ]; do [ "$1" = --name ] && n="$2"; shift; done; printf 'HUB_NAME=%s\n' "$n" > hub.conf
STUB
  printf '#!/bin/bash\ncat > /dev/null; echo READY\n' > "$d/bin/agent"
  printf '#!/bin/bash\n[ "${1:-}" = set ] && cat > /dev/null; exit 0\n' > "$d/bin/keys"
  printf '#!/bin/bash\nexit 0\n' > "$d/bin/chat"; printf '#!/bin/bash\necho "NAME FOLDER"\n' > "$d/bin/sessions"
  chmod +x "$d/bin/"*; commit_tag "$d" template
}
# G <keys> [args]: ade on an 80-column terminal from $T/cwd, the keys typed ahead (\n = Enter); the screen in $T/out
G() { local k="$1"; shift; (cd "$T/cwd" && pty_run "$k" env PATH="$F:$T/sys" COLUMNS=80 LINES=24 "$BASH" "$ADE" "$@") > "$T/out" 2>&1; }
A() { (cd "$T/cwd" && PATH="$F:$T/sys" "$BASH" "$ADE" "$@") > "$T/out" 2>&1; }   # without a terminal
# talk <keys> [args]: as G, but typed as a person types, with the terminal's echo on: each line of <keys> is typed
# when ade waits at a prompt (the screen ends in a space and is quiet for 0.2 s), then end of input; for the transcript
talk() {
  local k="$1"; shift
  (cd "$T/cwd" && python3 -c '
import os, pty, select, sys, time
keys = sys.argv[1].encode().decode("unicode_escape").split("\n")[:-1]
pid, fd = pty.fork()
if pid == 0: os.execvp(sys.argv[2], sys.argv[2:])
out, last, sent, end = b"", time.time(), -1, time.time() + 60
while time.time() < end:
    if select.select([fd], [], [], 0.05)[0]:
        try: d = os.read(fd, 4096)
        except OSError: break
        if not d: break
        out += d; last = time.time(); continue
    if out.endswith(b" ") and time.time() - last > 0.2 and sent != len(out):
        sent = len(out); os.write(fd, (keys.pop(0) + "\n").encode() if keys else b"\x04")
sys.stdout.write(out.decode("utf-8", "replace").replace("\r", ""))
_, st = os.waitpid(pid, 0); sys.exit(os.WEXITSTATUS(st) if os.WIFEXITED(st) else 1)' "$k" env PATH="$F:$T/sys" COLUMNS=80 LINES=24 "$BASH" "$ADE" "$@") > "$T/out" 2>&1
}
signed_in() { local w; for w in "$@"; do touch "$T/$w.in"; done; }
last_line() { grep -v '^[[:space:]]*$' "$T/out" | tail -1; }

guide_offers() {   # AC1
  fresh; fakes
  G "\n"; rc=$?
  for s in "Claude Code" "Sign in to Claude" "Sign in to GitHub" "Your hub" "Your first project" "Telegram (optional)"; do
    assert_contains "$T/out" "$s" "the list names: $s"; done
  grep -E '\[x\] 1\. Claude Code +installed' "$T/out" > /dev/null || { cat "$T/out"; fail "a done step shows its state"; }
  grep -E '\[ \] 2\. Sign in to Claude +not signed in' "$T/out" > /dev/null || fail "a step to do shows its state"
  grep -E '\[ \] 4\. Your hub +none yet' "$T/out" > /dev/null || fail "no hub yet"
  assert_contains "$T/out" "Set up now? [Y/n]" "asks"
  assert_contains "$T/out" "Step 2 of 6: Sign in to Claude" "Enter starts the guide"
  assert_eq "$rc" 1 "then the end of input stops it"
  A < /dev/null; rc=$?; assert_eq "$rc" 0 "no terminal: exit 0"
  assert_contains "$T/out" "Sign in to GitHub" "the same list"; assert_contains "$T/out" "ade setup" "and the command"
  assert_not_contains "$T/out" "Set up now?" "asks nothing"; assert_not_contains "$T/out" "Step 2" "starts nothing"
  (export CLAUDECODE=1; G "\n"); assert_not_contains "$T/out" "Set up now?" "an agent session is never asked"
  assert_contains "$T/out" "ade setup" "it is told the command"; assert_not_contains "$CALLS" "auth login" "and nothing ran"
  G "n\n"; assert_eq "$?" 0 "no: exit 0"; assert_contains "$T/out" "ade setup" "says how to start later"; assert_not_contains "$T/out" "Step 2" "no guide"
}

guide_resumes() {   # AC2
  fresh; fakes; signed_in claude
  G "" setup; rc=$?
  assert_not_contains "$T/out" "Step 1 of" "a done step is skipped"; assert_not_contains "$T/out" "Step 2 of" "so is the second"
  assert_contains "$T/out" "Step 3 of 6: Sign in to GitHub" "starts at the first step not done"
  assert_contains "$T/out" "This runs GitHub's own sign-in" "says what the step does before it"
  assert_contains "$T/out" "checked: signed in to GitHub as tester" "and that it checked, after it"
  assert_contains "$T/out" "Step 4 of 6: Your hub" "then the next step"
  assert_eq "$rc" 1 "the end of input stops"; assert_contains "$T/out" "to come back, run ade setup" "and says how to come back"
  G "" setup; assert_contains "$T/out" "Step 4 of 6: Your hub" "run again, it resumes there"
  assert_not_contains "$T/out" "Step 3 of" "the GitHub step is not run again"
  assert_eq "$(grep -c '^gh auth login' "$CALLS")" 1 "one sign-in"
}

guide_choices_forgive() {   # AC3
  fresh; fakes; signed_in claude gh; local a n=0
  for a in 2 staff-software-engineer "staff software engineer" "Staff Software Engineer" STAFF_SOFTWARE_ENGINEER " staff" "st"; do
    n=$((n + 1)); rm -f "$T/init.log"
    G "$a\nAcme\nSam\n" hub new "h$n"; [ "$?" = 0 ] || { cat "$T/out"; fail "[$a]: hub new"; }
    grep -qF "[--persona] [staff-software-engineer]" "$T/init.log" || { cat "$T/out"; fail "[$a] is staff-software-engineer"; }
  done
  assert_contains "$T/out" "  2) staff-software-engineer" "the choices are numbered"
  G "engineer\ntech\n9\ntech-l\nAcme\nSam\n" hub new other || { cat "$T/out"; fail "re-asked, then accepted"; }
  assert_eq "$(grep -c 'accepted: a number from 1 to 4' "$T/out")" 3 "each wrong answer is asked again with one line"
  grep -qF "[--persona] [tech-lead]" "$T/init.log" || fail "a prefix only one name has"
  rm -f "$T/claude.in"; G "\n" setup; assert_contains "$CALLS" "claude auth login" "Enter takes the default in brackets"
  assert_contains "$T/out" "How do you use Claude? [account]" "the default is shown"
  G "devops\n" hub new third; rc=$?; assert_eq "$rc" 1 "the end of input stops"
  assert_eq "$(last_line)" "ade: stopped (no answer); to come back, run ade hub new third" "and says how to come back"
}

guide_github_sign_in() {   # AC4
  fresh; fakes; signed_in claude; rm "$F/gh"
  G "n\ny\n" setup
  assert_contains "$CALLS" "brew install gh" "offers to install gh, and a yes installs it"
  assert_contains "$T/out" "a private repository" "says why a hub needs GitHub"; assert_contains "$T/out" "restore" "line two"
  assert_contains "$CALLS" "gh auth login --hostname github.com --git-protocol https --web" "GitHub's own browser sign-in"
  assert_contains "$CALLS" "gh had the terminal" "on the person's terminal"
  assert_contains "$T/out" "one-time code: WDJB-MJHT" "GitHub's code reaches the person"
  assert_contains "$T/out" "checked: signed in to GitHub as tester" "says who is signed in"
  ! grep -qE "gh auth token|--show-token|--with-token|^gh env GH_(TOKEN|ENTERPRISE_TOKEN)" "$CALLS" || fail "never a token"
  ! grep -qiE '(password|token)[^.]*: *$' "$T/out" || fail "never a password or token question"
  fresh; fakes; signed_in claude; touch "$T/gh.fail"
  G "" setup; rc=$?; assert_eq "$rc" 1 "a sign-in that does not finish stops"
  assert_eq "$(last_line)" "ade: the GitHub sign-in did not finish; to try again, run ade setup" "one line, never GitHub's error text last"
  assert_not_contains "$T/out" "Step 4" "and never a hub without GitHub"; assert_not_contains "$T/out" "no-github" "nor the way around it"
  rm "$T/gh.fail"; A setup < /dev/null; assert_eq "$?" 2 "no terminal: the sign-in is refused"
  [ "$(grep -c '^gh auth login' "$CALLS")" = 1 ] || fail "not run without a terminal"
  assert_contains "$T/out" "at a terminal" "says why"
  fresh; fakes; signed_in claude gh; printf 'te\033[31mster\001\n' > "$T/gh.login"
  G "" setup; grep -E 'Sign in to GitHub +signed in as te' "$T/out" > /dev/null || { cat "$T/out"; fail "the name"; }
  ! grep -q $'[\001\033]' "$T/out" || fail "control characters removed"
}

hub_new_forgives_and_resumes() {   # AC5
  fresh; fakes
  G "staff software engineer\nAcme\nSam\n" hub new acme; [ "$?" = 0 ] || { cat "$T/out"; fail "hub new"; }
  assert_contains "$CALLS" "gh auth login --hostname github.com --git-protocol https --web" "the GitHub sign-in step, when needed"
  [ "$(grep -n '^gh auth login' "$CALLS" | cut -d: -f1)" -lt "$(grep -n '^gh repo create' "$CALLS" | cut -d: -f1)" ] || fail "before the repository"
  grep -qF "init [--persona] [staff-software-engineer] [--client] [Acme] [--owner] [Sam] [--name] [acme]" "$T/init.log" || { cat "$T/init.log"; fail "validated answers as flags"; }
  assert_not_contains "$T/init.log" "init had a terminal" "bin/init asks nothing"
  touch "$T/init.fail"; G "tech-lead\nAcme\nSam\n" hub new beta; rc=$?; assert_eq "$rc" 1 "bin/init failed"
  assert_eq "$(last_line)" "ade: the hub's own set-up did not finish; run ade hub new beta again to pick up where it stopped" "one line, no placeholders"
  [ ! -e "$HOME/.config/ade/hubs" ] || ! grep -q beta "$HOME/.config/ade/hubs" || fail "a half-made hub is not saved"
  rm "$T/init.fail"; G "tech-lead\nAcme\nSam\n" hub new beta || { cat "$T/out"; fail "run again: it picks up"; }
  assert_eq "$(grep -c 'repo create beta' "$CALLS")" 1 "the repository is made once"; [ -f "$HOME/hubs/beta/hub.conf" ] || fail "the hub is made"
  assert_eq "$(cat "$HOME/.config/ade/hub")" "$HOME/hubs/beta" "and saved"
  G "" hub new beta; assert_eq "$?" 2 "a finished hub is not made again"
  A help; assert_not_contains "$T/out" "no-github" "the help text"
  rm "$F/gh"; A hub new gamma < /dev/null; assert_eq "$?" 2 "gh missing without a terminal"; assert_not_contains "$T/out" "no-github" "no message offers it"
  ! grep -E '(echo|die|say|printf).*no-github' "$ADE" > /dev/null || fail "no message in ade offers --no-github"
  cp "$T/gh.real" "$F/gh"; A hub new local1 --no-github --persona tech-lead --client c --owner o < /dev/null || { cat "$T/out"; fail "--no-github stays for tests"; }
}

notice_one_line() {   # AC6
  fresh; fakes; unset ADE_NO_UPDATE_CHECK; export ADE_NO_AUTO_UPDATE=1
  sed 's/^ADE_VERSION=""/ADE_VERSION="1.2.3"/' "$ADE" > "$T/ade"; local U="$HOME/.config/ade/updates" long l
  long="$(printf 'a long summary of everything in this release %.0s' 1 2 3 4 5)"
  mkdir -p "$U"; date +%s > "$U/checked"
  printf '1.3.0\tnormal\t-\t%s\n' "$long" > "$U/ade-cli.latest"
  PATH="$F:$T/sys" "$BASH" "$T/ade" hub list > /dev/null 2> "$T/err"
  assert_eq "$(wc -l < "$T/err" | tr -d ' ')" 1 "one line"; l="$(cat "$T/err")"
  [ "${#l}" -le 80 ] || fail "fits 80 columns: [$l] is ${#l}"
  for s in 1.3.0 1.2.3 "ade update"; do assert_contains "$T/err" "$s" "names $s"; done
  assert_not_contains "$T/err" "summary" "never the changelog text"
  printf '1.3.1\tsecurity\t-\t%s\n' "$long" > "$U/ade-cli.latest"; PATH="$F:$T/sys" "$BASH" "$T/ade" hub list > /dev/null 2> "$T/err"
  l="$(cat "$T/err")"; [ "${#l}" -le 80 ] && [ "$(wc -l < "$T/err" | tr -d ' ')" = 1 ] || fail "a security notice too: [$l]"
  unset ADE_NO_AUTO_UPDATE; printf '2.0.0\tnormal\t-\t%s\n' "$long" > "$U/ade-cli.latest"
  (cd "$T/cwd" && pty_run "" env PATH="$F:$T/sys" COLUMNS=80 "$BASH" "$T/ade" hub list) > "$T/err" 2>&1
  grep "2.0.0" "$T/err" | while IFS= read -r l; do [ "${#l}" -le 80 ] || fail "the major-update notice fits: [$l]"; done || exit 1
  grep -q "2.0.0" "$T/err" || fail "the major-update notice is shown"
}

guide_in_computer() {   # AC7
  fresh; fakes; signed_in claude; touch "$T/ade-computer"; export ADE_COMPUTER_MARKER="$T/ade-computer" DISPLAY=:0
  G "\n\n"; head -1 "$T/out" > "$T/first"; assert_contains "$T/first" "ADE Computer" "the first line says where"
  assert_contains "$T/first" "ade setup" "and names the guide"
  assert_contains "$T/out" "stays in this computer's home" "the sign-in stays here"
  assert_contains "$T/out" "Open the GitHub address in this computer's browser? [Y/n]" "offers the computer's own browser"
  assert_contains "$CALLS" "xdg-open https://github.com/login/device" "and opens it with a yes"
  assert_contains "$T/out" "Your one-time code, large:" "the code is shown large"
  [ "$(grep -cE '^ +#.*#' "$T/out")" -ge 5 ] || { cat "$T/out"; fail "in block letters"; }
  assert_contains "$T/out" "W D J B - M J H T" "and spelled out"
  assert_contains "$T/out" "checked: signed in to GitHub as tester" "then checked"
  fresh; fakes; signed_in claude; touch "$T/ade-computer"; export ADE_COMPUTER_MARKER="$T/ade-computer"; unset DISPLAY
  G "" setup; assert_not_contains "$T/out" "browser? [Y/n]" "no display: no browser offer"; assert_not_contains "$CALLS" "xdg-open" "nothing opened"
  fresh; fakes; signed_in claude; G "n\n"; head -1 "$T/out" > "$T/first"; assert_not_contains "$T/first" "ADE Computer" "outside one, never said"
}

guide_happy_path() {   # AC8
  fresh; fakes; export MAKE_PROJECT=web
  talk "\n\nacme\nstaff software engineer\nAcme\nSam\n1\n\nn\n"; rc=$?
  sed -e "s#$T#<T>#g" -e 's/ready ([0-9]*s)/ready (Ns)/' "$T/out" > "$T/screen"
  if [ "${UPDATE_GOLDEN:-}" = 1 ]; then cp "$T/screen" "$REPO/tests/golden/guide-80.txt"; echo "golden guide-80 updated" >&2; fi
  diff -u "$REPO/tests/golden/guide-80.txt" "$T/screen" || fail "the first run matches tests/golden/guide-80.txt"
  assert_eq "$rc" 0 "a working hub"
  local l; while IFS= read -r l; do [ "${#l}" -le 80 ] || fail "wider than 80 columns: [$l]"; done < "$T/screen"
  [ -f "$HOME/hubs/acme/hub.conf" ] && [ -d "$HOME/hubs/acme/projects/web" ] || fail "the hub and its first project"
  G "" setup; assert_contains "$T/out" "All set" "run again, nothing is left"
}

guide_hostile() {   # AC9
  fresh; fakes; signed_in claude gh; local long x; long="$(printf 'b%.0s' $(seq 1 300))"
  for x in '\x01ctl' '\x1b[31mred' 'bell\x07' "$long" "-rf" "--persona=x"; do   # refused by each kind of question
    rm -f "$T/init.log"
    G "$x\ntech-lead\n$x\nAcme\n$x\nSam\n" hub new "h$RANDOM" || { cat "$T/out"; fail "[$x]: refused, then the good answers"; }
    grep -qF "[--persona] [tech-lead] [--client] [Acme] [--owner] [Sam]" "$T/init.log" || { cat "$T/out"; fail "[$x] never reached bin/init"; }
    assert_eq "$(grep -c '; type it again' "$T/out")" 3 "[$x]: refused and asked again, at each question"
  done
  rm -f "$T/init.log"; G "tech-lead\n\$(touch $T/pwned)\nSam\n" hub new "h$RANDOM" || fail "text that only looks like code is data"
  grep -qF "[--client] [\$(touch $T/pwned)]" "$T/init.log" || { cat "$T/init.log"; fail "passed intact"; }
  [ ! -e "$T/pwned" ] || fail "an answer ran"
  fresh; fakes; signed_in claude gh
  G "\x1b[31m\n$long\n-x\nacme\n" setup; assert_eq "$(grep -c '; type it again' "$T/out")" 3 "the hub name too"
  assert_contains "$T/out" "control characters" "says why"; assert_contains "$CALLS" "repo create acme" "then the good one"
}

ALL="guide_offers guide_resumes guide_choices_forgive guide_github_sign_in hub_new_forgives_and_resumes notice_one_line guide_in_computer guide_happy_path guide_hostile"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
