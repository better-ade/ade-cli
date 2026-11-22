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
skip = set("gitleaks claude gh brew apt-get apt sudo uname open xdg-open tmux yazi bat batcat glow pdftotext pdftoppm chafa code "
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
# A18b: a fake fails once per line of $T/<name> (fails <name>: that line on stderr, then gone): install.fail, claude.fail,
# brew.fail, gh.failn, repo.fail (with repo.half: after leaving a half-made clone), init.failn, session.fail; agent.fail
# is the live test's message for as long as the file is there, and the sign-in removes it when login.fixes exists.
fakes() {
  F="$T/fakebin"; mkdir -p "$F"; export CALLS="$T/calls" FT="$T"; : > "$CALLS"; farm
  printf 'fails() { [ -s "$FT/$1" ] || return 1; head -1 "$FT/$1" >&2; sed 1d "$FT/$1" > "$FT/$1.n"; mv "$FT/$1.n" "$FT/$1"; }\n' > "$T/fails.sh"
  cat > "$F/claude" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$CALLS"; . "$FT/fails.sh"
case "${1:-} ${2:-}" in
  "auth status") [ -f "$FT/claude.in" ] ;;
  "auth login") fails claude.fail && exit 1; if [ -t 0 ] && [ -t 1 ]; then echo "claude had the terminal" >> "$CALLS"; fi
    [ ! -f "$FT/login.fixes" ] || rm -f "$FT/agent.fail"; touch "$FT/claude.in" ;;
  *) echo "(the guided Claude Code session runs here)"; [ -z "${SESSION_EXIT:-}" ] || exit "$SESSION_EXIT"; fails session.fail && exit 1
    [ -z "${MAKE_PROJECT:-}" ] || mkdir -p "projects/$MAKE_PROJECT" ;;
esac
STUB
  cat > "$F/gh" <<'STUB'
#!/bin/bash
. "$FT/fails.sh"; echo "gh $*" >> "$CALLS"; env | grep -E '^GH_(TOKEN|ENTERPRISE_TOKEN|BROWSER)=' | sed 's/^/gh env /' >> "$CALLS"
case "${1:-} ${2:-}" in
  "auth status") [ -f "$FT/gh.in" ] ;;
  "auth login") if [ -t 0 ] && [ -t 1 ]; then echo "gh had the terminal" >> "$CALLS"; fi
    echo "! First copy your one-time code: WDJB-MJHT"; echo "Open this URL to continue in your web browser: https://github.com/login/device"
    [ -z "${GH_BROWSER:-}" ] || "$GH_BROWSER" https://github.com/login/device
    if [ -f "$FT/gh.fail" ] || fails gh.failn; then echo "error: authentication timed out" >&2; exit 1; fi
    touch "$FT/gh.in"; echo "Logged in as tester" ;;
  "api user") [ -f "$FT/gh.in" ] && printf '%s\n' "$(cat "$FT/gh.login" 2> /dev/null || echo tester)" ;;
  "repo create") if fails repo.fail; then [ ! -f "$FT/repo.half" ] || mkdir -p "$3/.git"; exit 1; fi; git clone -q "$FT/template" "$3" ;;
esac
STUB
  printf '#!/bin/bash\necho "xdg-open $*" >> "$CALLS"\n' > "$F/xdg-open"
  printf '#!/bin/bash\n. "$FT/fails.sh"; echo "brew $*" >> "$CALLS"; fails brew.fail && exit 1\n[ "$1 $2" = "install gh" ] && cp "$FT/gh.real" "$FT/fakebin/gh"\nexit 0\n' > "$F/brew"
  printf '#!/bin/bash\nif [ $# -eq 0 ] || [ "$1" = -s ]; then echo Darwin; else exec "%s" "$@"; fi\n' "$(command -v uname)" > "$F/uname"
  local c; for c in tmux yazi bat glow pdftotext pdftoppm chafa code gitleaks; do printf '#!/bin/bash\nexit 0\n' > "$F/$c"; done   # the other tools: there
  chmod +x "$F"/*; cp "$F/gh" "$T/gh.real"; cp "$F/claude" "$T/claude.fake"
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
. "$FT/fails.sh"; fails init.failn && exit 1
n=""; while [ $# -gt 0 ]; do [ "$1" = --name ] && n="$2"; shift; done; printf 'HUB_NAME=%s\n' "$n" > hub.conf
printf '# %s: the hub\n' "$n" > README.md; mkdir -p projects journal; echo first > journal/day.md; git config core.hooksPath .githooks   # rendered
STUB
  echo "# ade-brain, the template" > "$d/README.md"
  printf '#!/bin/bash\ncat > /dev/null; if [ -f "$FT/agent.fail" ]; then cat "$FT/agent.fail" >&2; exit 1; fi; echo READY\n' > "$d/bin/agent"
  # bin/sync --yes as the hub's does it: commit what changed (the pre-commit hook path is the hub's), then push when
  # there is a remote; $FT/sync.fail: one failure per line, before the commit; $FT/push.fail: the same, after it
  cat > "$d/bin/sync" <<'STUB'
#!/bin/bash
. "$FT/fails.sh"; echo "sync $* gitleaks=$(command -v gitleaks > /dev/null && echo yes)" >> "$CALLS"
fails sync.fail && exit 1
git add -A; if git diff --cached --quiet; then echo "nothing to sync"; exit 0; fi
git commit -qm "sync 2026-11-22" || exit 1
if git remote get-url origin > /dev/null 2>&1; then if fails push.fail; then exit 1; fi; git push -q || { echo "push failed" >&2; exit 1; }; fi
echo "synced: $(git log -1 --pretty='%h %s')"
STUB
  git -C "$d" config receive.denyCurrentBranch ignore   # the fake GitHub: pushes to it are taken
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
fakes_claude_to() { cp "$T/claude.fake" "$1"; chmod +x "$1"; }   # the fake claude, where an installer puts it
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
  assert_contains "$T/out" "The GitHub sign-in did not finish; your hub needs GitHub" "one plain line (A18b)"
  assert_eq "$(last_line)" "ade: stopped (no answer); to come back, run ade setup" "never GitHub's error text last"
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
  assert_contains "$T/out" "The hub's set-up (bin/init) did not finish: init: the persona files are missing" "one plain line (A18b)"
  assert_eq "$(last_line)" "ade: stopped (no answer); to come back, run ade hub new beta" "and how to come back, no placeholders"
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
  sed -e "s#$T#<T>#g" -e 's/ready ([0-9]*s)/ready (Ns)/' -e 's/^synced: [0-9a-f]* /synced: <commit> /' "$T/out" > "$T/screen"
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

guide_empty_hint() {   # review 3: the second empty answer to a question that cannot be skipped says how to leave
  fresh; fakes; signed_in claude gh
  G "\n\n" hub new x1; assert_eq "$(grep -c 'to leave, press Ctrl-C; ade hub new x1 picks up where you stopped' "$T/out")" 1 "once, on a choice"
  [ "$(grep -n 'Ctrl-C' "$T/out" | cut -d: -f1)" -gt "$(grep -n 'accepted:' "$T/out" | head -1 | cut -d: -f1)" ] || fail "not at the first refusal"
  G "tech-lead\n\n" hub new x2; assert_not_contains "$T/out" "Ctrl-C" "one empty answer: no hint"
  G "tech-lead\n\n\n\n" hub new x3; assert_eq "$(grep -c 'Ctrl-C' "$T/out")" 1 "once, on free text"
  fresh; fakes; signed_in gh; G "\n\n" setup; assert_contains "$CALLS" "claude auth login" "Enter took the default"
  assert_not_contains "$T/out" "Ctrl-C" "a default is never a refusal; one empty name is not a second"
}

guide_session_fails() {   # review 4: a guided session that exits non-zero is said, then the guide ends as not finished
  fresh; fakes; signed_in claude gh
  A hub new acme --persona tech-lead --client Acme --owner Sam < /dev/null || { cat "$T/out"; fail "hub"; }
  echo "HUB_ROOT_PROVIDER=anthropic" >> "$HOME/hubs/acme/hub.conf"
  SESSION_EXIT=1 G "\nn\n" setup; rc=$?   # A18b: Enter = go on, the step stays not done
  assert_contains "$T/out" "Claude Code stopped early (exit 1)" "said in one line"; assert_contains "$T/out" "What now? [go-on]:" "asked"
  for s in "  1) again  start it again" "  2) go-on  go on (this step stays not done)" "  3) stop   stop here"; do assert_contains "$T/out" "$s" "$s"; done
  assert_contains "$T/out" "Going on; this step is not done: ade setup comes back to it." "go on"
  assert_contains "$T/out" "checked: no project yet" "then checked"
  assert_contains "$T/out" "Not finished: step 5 (Your first project); run ade setup to pick up there." "and the ending"
  assert_eq "$rc" 0 "the guide ran to its end"
  G "n\n" setup; assert_not_contains "$T/out" "stopped early" "a session that exits 0 is not"
  echo "claude: crashed" > "$T/session.fail"; MAKE_PROJECT=web G "again\nn\n" setup; assert_eq "$?" 0 "start it again"
  assert_eq "$(grep -c '^claude --' "$CALLS")" 4 "a second session"; assert_contains "$T/out" "checked: your first project is web" "which finished the step"
  rm -rf "$HOME/hubs/acme/projects"; SESSION_EXIT=1 G "stop\n" setup; assert_eq "$?" 1 "stop"
  assert_eq "$(last_line)" "What now? [go-on]: ade: stopped; to come back, run ade setup" "how to come back"
}

hub_new_resume_flags() {   # review 6: the resume line names --dir and --public, and running it again picks up
  fresh; fakes; signed_in claude gh; touch "$T/init.fail"; mkdir -p "$T/elsewhere"
  G "tech-lead\nAcme\nSam\n" hub new pub --public --dir "$T/elsewhere"; assert_eq "$?" 1 "bin/init failed"
  assert_eq "$(last_line)" "ade: stopped (no answer); to come back, run ade hub new pub --dir $T/elsewhere --public" "the whole command"
  assert_contains "$CALLS" "repo create pub --template better-ade/ade-brain --public --clone" "public"
  rm "$T/init.fail"; G "tech-lead\nAcme\nSam\n" hub new pub --public --dir "$T/elsewhere" || { cat "$T/out"; fail "picks up"; }
  assert_contains "$T/out" "Picking up the hub pub where its set-up stopped" "says so"; assert_eq "$(grep -c 'repo create pub' "$CALLS")" 1 "one repository"
  [ ! -e "$T/elsewhere/pub/.git/ade-hub-new" ] && [ -f "$T/elsewhere/pub/hub.conf" ] || fail "finished, marker gone"
  touch "$T/init.fail"; G "tech-lead\nAcme\nSam\n" hub new home1 --dir "$HOME/work"
  assert_contains "$T/out" "run ade hub new home1 --dir ~/work" "a folder in the home is written with ~"
  rm "$T/init.fail"; mkdir -p "$T/cwd/hubs"; G "tech-lead\nAcme\nSam\n" hub new rel1 --dir hubs; [ -f "$T/cwd/hubs/rel1/hub.conf" ] || fail "a relative --dir"
  G "" hub new rel1 --dir hubs; assert_eq "$?" 2 "a finished hub is not picked up"
  A hub new rel2 --bogus; assert_eq "$?" 2 "an unknown flag"; assert_contains "$T/out" "usage: ade hub new <name>" "is answered with the usage"
  A setup --bogus; assert_eq "$?" 2 "an unknown setup flag"; assert_contains "$T/out" "usage: ade setup [--check" "is answered with the usage"
}

guide_computer_relay() {   # review 6: the relay passes gh's exit code and output, and opens nothing without a yes
  fresh; fakes; signed_in claude; touch "$T/ade-computer" "$T/gh.fail"; export ADE_COMPUTER_MARKER="$T/ade-computer" DISPLAY=:0
  G "n\n" setup; rc=$?; assert_eq "$rc" 1 "gh's failure comes through the relay"
  assert_contains "$T/out" "error: authentication timed out" "gh's own output passes through"
  assert_contains "$T/out" "Your one-time code, large:" "the code is still shown large"
  assert_eq "$(last_line)" "ade: stopped (no answer); to come back, run ade setup" "ade's line last"
  assert_contains "$CALLS" "gh env GH_BROWSER=true" "no: the browser stays closed"; assert_not_contains "$CALLS" "xdg-open" "nothing opened"
  rm "$T/gh.fail"; unset ADE_COMPUTER_MARKER; G "" setup; assert_not_contains "$CALLS" "GH_BROWSER=xdg" "outside a computer ade sets no browser"
  [ "$(grep -c '^gh env GH_BROWSER' "$CALLS")" = 1 ] || fail "and none at all outside one"
  assert_not_contains "$T/out" "large:" "nor the large code"
}

guide_installs_claude() {   # review 6: step 1 with Claude Code missing, through the fake installer
  fresh; fakes; local real; rm "$F/claude"; real="$T/claude.real"; mkdir -p "$T/inst"
  printf '#!/bin/bash\necho installer-ran >> "$CALLS"; mkdir -p "$HOME/.local/bin"; cp "%s" "$HOME/.local/bin/claude"\n' "$real" > "$T/inst/install.sh"
  fakes_claude_to "$real"; export ADE_CLAUDE_INSTALLER="file://$T/inst/install.sh" ADE_TEST_ALLOW_FILE_URLS=1
  G "n\n" setup; assert_eq "$?" 1 "no: stops"; assert_contains "$T/out" "Step 1 of 6: Claude Code" "the first step"
  assert_contains "$T/out" "curl -fsSL https://claude.ai/install.sh | bash" "names the manual command"; assert_not_contains "$CALLS" installer-ran "nothing ran"
  G "y\n" setup; assert_contains "$CALLS" installer-ran "a yes runs the installer"
  assert_contains "$T/out" "checked: Claude Code is installed" "then checked"; assert_contains "$T/out" "Step 2 of 6" "and on to the next"
  export ADE_CLAUDE_INSTALLER="http://example.invalid/install.sh"; rm -rf "$HOME/.local/bin"
  G "y\n" setup; assert_eq "$?" 1 "a non-https installer"; assert_contains "$T/out" "must be an https URL" "is refused"
}

# A18b: each step's failure is one plain line, where the details are, and a numbered question (the table FAILS in ade)
wide() {   # the failure exchange (the line said, the details, the choices, the question) fits 80 columns
  local l; grep -q '^details: ' "$T/out" || fail "no failure exchange in $T/out"
  while IFS= read -r l; do l="${l%%]: *}"; [ "${#l}" -le 80 ] || fail "wider than 80 columns: [$l]"; done < <(grep -A6 '^details: ' "$T/out")
}   # (pty_run types ahead with the echo off, so the next line of the screen follows a question on its own line)
stopped() { assert_eq "$1" 1 "stop: exit 1"; assert_eq "$(last_line | sed 's/^What now? [^:]*: //')" "ade: stopped; to come back, run ${2:-ade setup}" "and how to come back"; }
guide_install_fails() {   # step 1: try again; the manual command; stop
  fresh; fakes; rm "$F/claude"; mkdir -p "$T/inst"; fakes_claude_to "$T/claude.real"
  printf '. "$FT/fails.sh"; fails install.fail && exit 3\nmkdir -p "$HOME/.local/bin"; cp "%s" "$HOME/.local/bin/claude"\n' "$T/claude.real" > "$T/inst/install.sh"
  export ADE_CLAUDE_INSTALLER="file://$T/inst/install.sh" ADE_TEST_ALLOW_FILE_URLS=1
  echo "curl: (6) could not resolve host" > "$T/install.fail"; G "y\n\n" setup
  assert_contains "$T/out" "The Claude Code installer did not finish (exit 3)" "one plain line"; assert_contains "$T/out" "details: in the lines above, from the tool itself" "where"
  for s in "  1) retry   try again" "  2) manual  show the command to install it yourself" "  3) stop    stop here" "What now? [retry]:"; do assert_contains "$T/out" "$s" "$s"; done
  assert_contains "$T/out" "checked: Claude Code is installed" "Enter tried again, and it installed"; wide
  rm -rf "$HOME/.local"; echo x > "$T/install.fail"; G "y\nmanual\n" setup; assert_eq "$?" 1 "manual: stops"
  assert_contains "$T/out" "  curl -fsSL https://claude.ai/install.sh | bash" "the command"; assert_eq "$(last_line)" "ade: then run ade setup again (in a new terminal, so claude is found)" "and what next"
  echo x > "$T/install.fail"; G "y\nstop\n" setup; stopped $?
  printf '#!/bin/bash\nexit 0\n' > "$T/inst/install.sh"; G "y\nstop\n" setup; stopped $?
  assert_contains "$T/out" "The installer ran, but claude is not on PATH yet" "an installer that installs nothing"
}
guide_claude_sign_in_fails() {   # step 2: sign in again; an API key instead; stop
  fresh; fakes; printf 'Login cancelled\nLogin cancelled\n' > "$T/claude.fail"; G "\n\n\n" setup
  assert_contains "$T/out" "The Claude sign-in did not finish" "one plain line"
  for s in "  1) sign-in  sign in again" "  2) key      use an API key instead" "  3) stop     stop here" "What now? [sign-in]:"; do assert_contains "$T/out" "$s" "$s"; done
  assert_eq "$(grep -c '^claude auth login' "$CALLS")" 3 "Enter signs in again, each time"; assert_contains "$T/out" "checked: signed in to Claude (account)" "until it works"; wide
  fresh; fakes; echo x > "$T/claude.fail"; G "\nkey\n" setup; assert_contains "$T/out" "checked: your key is asked at step 4, once your hub is made" "a key instead"
  assert_contains "$T/out" "Step 3 of 6" "and on"
  fresh; fakes; echo x > "$T/claude.fail"; G "\nstop\n" setup; stopped $?; assert_not_contains "$T/out" "Step 3 of 6" "no further"
}
guide_gh_fails() {   # step 3: gh does not install (try again; manual; stop); its sign-in does not finish (again; stop)
  fresh; fakes; signed_in claude; rm "$F/gh"; printf 'Error: no bottle\nError: no bottle\n' > "$T/brew.fail"
  G "y\ny\n\ny\n" setup; assert_contains "$T/out" "The GitHub CLI (gh) is not installed yet; your hub needs it" "one plain line"
  for s in "  1) retry   try again" "  2) manual  show the command to install it yourself" "  3) stop    stop here"; do assert_contains "$T/out" "$s" "$s"; done
  assert_eq "$(grep -c '^brew install gh' "$CALLS")" 3 "Enter tried again"; assert_contains "$T/out" "checked: signed in to GitHub as tester" "then signed in"; wide
  assert_not_contains "$T/out" "no-github" "GitHub stays required"; assert_not_contains "$T/out" "go-on" "no going on without it"
  fresh; fakes; signed_in claude; rm "$F/gh"; printf 'x\nx\n' > "$T/brew.fail"; G "y\ny\nmanual\n" setup; assert_eq "$?" 1 "manual: stops"
  assert_contains "$T/out" "  brew install gh" "the command"; assert_eq "$(last_line)" "ade: then run ade setup" "and what next"
  fresh; fakes; signed_in claude; rm "$F/gh"; printf 'x\nx\n' > "$T/brew.fail"; G "y\ny\nstop\n" setup; stopped $?
  fresh; fakes; signed_in claude; echo x > "$T/gh.failn"; G "\n" setup
  for s in "The GitHub sign-in did not finish; your hub needs GitHub" "  1) sign-in  sign in again" "  2) stop     stop here" "What now? [sign-in]:"; do assert_contains "$T/out" "$s" "$s"; done
  assert_eq "$(grep -c '^gh auth login' "$CALLS")" 2 "Enter signs in again"; assert_contains "$T/out" "checked: signed in to GitHub as tester" "and it worked"
  fresh; fakes; signed_in claude; echo x > "$T/gh.failn"; G "stop\n" setup; stopped $?; assert_not_contains "$T/out" "Step 4" "never a hub without GitHub"
}
guide_repo_fails() {   # step 4: the name is taken; not signed in or no permission; another error; never a half-made hub
  fresh; fakes; signed_in claude gh; echo "GraphQL: Name already exists on this account (createRepository)" > "$T/repo.fail"
  G "acme\n\nacme2\ntech-lead\nAcme\nSam\n" setup
  assert_contains "$T/out" "GitHub already has a repository named acme on your account" "one plain line"; assert_contains "$T/out" "details: ~/.config/ade/last-failure" "where"
  for s in "  1) name   pick another name" "  2) retry  try again" "  3) stop   stop here" "What now? [name]:"; do assert_contains "$T/out" "$s" "$s"; done
  grep -q "Name already exists" "$HOME/.config/ade/last-failure" || fail "gh's own text is kept there"; assert_not_contains "$T/out" "GraphQL" "not on the screen"
  [ -f "$HOME/hubs/acme2/hub.conf" ] && [ ! -e "$HOME/hubs/acme" ] || fail "the other name is the hub"; wide
  echo "error: not logged in to github.com; run gh auth login" > "$T/repo.fail"; G "\ntech-lead\nAcme\nSam\n" hub new b1 || { cat "$T/out"; fail "sign in again"; }
  assert_contains "$T/out" "GitHub refused: not signed in, or no permission to make b1" "said"; assert_contains "$T/out" "What now? [sign-in]:" "the default"
  assert_contains "$T/out" "  1) sign-in  sign in to GitHub again" "choice 1"; assert_eq "$(grep -c '^gh auth login' "$CALLS")" 1 "GitHub's own sign-in"
  [ -f "$HOME/hubs/b1/hub.conf" ] || fail "then the repository"
  echo "fatal: unable to access the network" > "$T/repo.fail"; touch "$T/repo.half"; G "\ntech-lead\nAcme\nSam\n" hub new c1 || { cat "$T/out"; fail "try again"; }
  assert_contains "$T/out" "GitHub did not make the repository c1: fatal: unable to access the network" "the reason"; assert_contains "$T/out" "What now? [retry]:" "the default"
  [ -f "$HOME/hubs/c1/hub.conf" ] || fail "the half-made clone was cleared and the second try made it"
  echo x > "$T/repo.fail"; G "stop\n" hub new d1; stopped $? "ade hub new d1"; [ ! -e "$HOME/hubs/d1" ] || fail "no half-made hub is left"
  echo "name already exists" > "$T/repo.fail"; G "\nb1\ne2\n" hub new e1; assert_contains "$T/out" "~/hubs/b1 is taken; type another name" "a taken folder is asked again"
  assert_eq "$(last_line)" "ade: stopped (no answer); to come back, run ade hub new e2" "the command names the new name"
}
guide_init_fails() {   # step 4: the hub's own set-up: try again from where it stopped; stop
  fresh; fakes; signed_in claude gh; echo "init: the disk is full" > "$T/init.failn"
  G "tech-lead\nAcme\nSam\n\n" hub new i1 || { cat "$T/out"; fail "try again"; }
  assert_contains "$T/out" "The hub's set-up (bin/init) did not finish: init: the disk is full" "one plain line"
  for s in "details: ~/.config/ade/last-failure" "  1) retry  try again from where it stopped" "  2) stop   stop here" "What now? [retry]:"; do assert_contains "$T/out" "$s" "$s"; done
  assert_eq "$(grep -c '^init \[--persona\] \[tech-lead\]' "$T/init.log")" 2 "the same answers, not asked again"; assert_eq "$(grep -c 'repo create i1' "$CALLS")" 1 "one repository"
  assert_eq "$(cat "$HOME/.config/ade/hub")" "$HOME/hubs/i1" "then saved"; wide
  echo x > "$T/init.failn"; G "tech-lead\nAcme\nSam\nstop\n" hub new i2; stopped $? "ade hub new i2"
  ! grep -q i2 "$HOME/.config/ade/hubs" || fail "a half-made hub is not saved"; [ -f "$HOME/hubs/i2/.git/ade-hub-new" ] || fail "it is marked, to pick up"
}
guide_live_test_fails() {   # the owner's case: the Claude account is at its limit when the everything agent is picked
  fresh; fakes; signed_in claude gh; mkdir -p "$HOME/.local/agent-out"; : > "$HOME/.local/agent-out/live.err"
  printf "agent: live test of anthropic:haiku failed: the engine exited with 1: You've hit your weekly limit · resets Nov 25 at 2am (Asia/Manila); details: %s\n" "$HOME/.local/agent-out/live.err" > "$T/agent.fail"
  talk "acme\ntech-lead\nAcme\nSam\n1\n\x03\n" setup; assert_eq "$?" 130 "Ctrl-C leaves"
  assert_eq "$(last_line)" "ade: stopped; to come back, run ade setup" "with the line on how to come back"
  touch "$T/login.fixes"; talk "1\n\n\n" setup; sed -e "s#$T#<T>#g" -e 's/ready ([0-9]*s)/ready (Ns)/' "$T/out" > "$T/screen"; cp "$T/screen" "$T/out"
  local l; while IFS= read -r l; do [ "${#l}" -le 80 ] || fail "wider than 80 columns: [$l]"; done < "$T/out"
  [ -z "${SHOW_EXCHANGE:-}" ] || cat "$T/screen" >&2
  assert_contains "$T/out" "This Claude account has reached its limit; it resets Nov 25 at 2am (Asia/Manila)" "one plain line"
  assert_contains "$T/out" "details: ~/.local/agent-out/live.err" "where the details are"; assert_not_contains "$T/out" "live test of" "no raw dump"
  assert_contains "$T/out" "What now? [sign-in]:" "asked, the default signs in"; assert_contains "$CALLS" "claude had the terminal" "Claude Code's own sign-in, on the terminal"
  assert_contains "$T/out" "anthropic: ready (Ns)" "then the test again"; assert_contains "$T/out" "everything agent: anthropic" "and on"
  fresh; fakes; signed_in claude gh; echo "agent: boom" > "$T/agent.fail"
  G "acme\ntech-lead\nAcme\nSam\n1\ngo-on\n\nn\n" setup; assert_contains "$T/out" "checked: your hub is acme (~/hubs/acme); anthropic not tested" "go on: said at the check"
  G "" setup; grep -E '\[x\] 4\. Your hub +acme \(~/hubs/acme\); anthropic not tested' "$T/out" > /dev/null || { cat "$T/out"; fail "and in the list"; }
}

guide_first_save() {   # A18b: the hub as bin/init rendered it is committed and pushed, the hub's own way (bin/sync --yes)
  fresh; fakes; signed_in claude gh; local h="$HOME/hubs/s1" tpl="$T/template" before b; b="$(git -C "$T/template" symbolic-ref --short HEAD)"
  G "tech-lead\nAcme\nSam\n" hub new s1 || { cat "$T/out"; fail "hub new"; }
  assert_contains "$T/out" "Saving the hub's first version to your private GitHub repository (bin/sync):" "said before it happens"
  assert_contains "$T/out" "synced: " "bin/sync's own line"; assert_contains "$CALLS" "sync --yes gitleaks=yes" "the hub's own way, with its secret scan"
  assert_eq "$(git -C "$tpl" show "$b:README.md")" "# s1: the hub" "GitHub shows the hub's README, not the template's"
  for f in hub.conf journal/day.md; do git -C "$tpl" cat-file -e "$b:$f" || fail "the first commit holds $f"; done
  assert_eq "$(git -C "$h" status --porcelain)" "" "nothing is left uncommitted"
  assert_eq "$(git -C "$h" log -1 --format='%an <%ae> / %cn <%ce>')" "t <t@t> / t <t@t>" "the person's own git identity"
  ! git -C "$h" log -1 --format=%B | grep -qiE "co-authored|generated|claude|anthropic" || fail "no AI attribution in the commit"
  ! grep -qE "push.*(-f|--force)" "$ADE" || fail "ade never force-pushes"
  before="$(git -C "$tpl" rev-parse "$b")"; A hub new local2 --no-github --persona tech-lead --client c --owner o < /dev/null || { cat "$T/out"; fail "--no-github"; }
  assert_contains "$T/out" "Saving the hub's first version (a commit here; no GitHub, so nothing is pushed):" "said"
  assert_eq "$(git -C "$HOME/hubs/local2" status --porcelain)" "" "committed"; assert_eq "$(git -C "$tpl" rev-parse "$b")" "$before" "nothing pushed with --no-github"
  echo "error: failed to push some refs" > "$T/push.fail"; G "tech-lead\nAcme\nSam\n\n" hub new s2 || { cat "$T/out"; fail "try again"; }
  assert_contains "$T/out" "The hub's first version was not saved: error: failed to push some refs" "a failed push, in one line"
  for s in "details: ~/.config/ade/last-failure" "  1) retry  try again" "  2) go-on  go on (save it later, with the command shown)" "  3) stop   stop here" "What now? [retry]:"; do assert_contains "$T/out" "$s" "$s"; done
  assert_eq "$(git -C "$tpl" show "$b:README.md")" "# s2: the hub" "try again pushed the commit that was made"; wide
  echo x > "$T/push.fail"; G "tech-lead\nAcme\nSam\ngo-on\n" hub new s3; assert_eq "$?" 0 "go on: the hub is made"
  assert_contains "$T/out" "Going on; to save it later: cd ~/hubs/s3 && bin/sync --yes && git push" "with the command for later"
  [ -n "$(git -C "$HOME/hubs/s3" rev-list '@{u}..HEAD')" ] || fail "the commit is kept, to push later"; assert_eq "$(cat "$HOME/.config/ade/hub")" "$HOME/hubs/s3" "the hub is saved in ade"
  echo "fatal: unable to auto-detect email address; Please tell me who you are" > "$T/sync.fail"; G "tech-lead\nAcme\nSam\nstop\n" hub new s4; stopped $? "ade hub new s4"
  assert_contains "$T/out" "git has no name and email yet: git config --global user.name and user.email" "no git identity: said plainly"
  rm "$F/gitleaks"; : > "$CALLS"; G "tech-lead\nAcme\nSam\n" hub new s5 || { cat "$T/out"; fail "no gitleaks is not an error"; }
  assert_contains "$T/out" "Not saved yet: the hub's secret scan (gitleaks) is not set up here, and ade" "no secret scan: said"
  assert_contains "$T/out" "does not commit without it. Later (install gitleaks first): cd ~/hubs/s5 && bin/sync --yes && git push" "with the command"
  assert_not_contains "$CALLS" "sync --yes" "and nothing is committed without it"; [ -n "$(git -C "$HOME/hubs/s5" status --porcelain)" ] || fail "left as it was"
}

ALL="guide_first_save guide_install_fails guide_claude_sign_in_fails guide_gh_fails guide_repo_fails guide_init_fails guide_live_test_fails guide_empty_hint guide_session_fails hub_new_resume_flags guide_computer_relay guide_installs_claude guide_offers guide_resumes guide_choices_forgive guide_github_sign_in hub_new_forgives_and_resumes notice_one_line guide_in_computer guide_happy_path guide_hostile"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
