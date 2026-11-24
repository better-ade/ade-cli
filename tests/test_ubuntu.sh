#!/bin/bash
# story A22: a raw Ubuntu machine installs and sets up ADE with no surprises. install.sh and ade run with only this
# test's fakes ($F: apt-get, sudo, curl, wget, uname, and the tools apt "installs") and the system's own commands
# without curl, wget, python3, apt and sudo ($T/sys), so a host install never answers. A file:// release; never the
# network, never the real apt. AC6 (the git name and email) is in test_guide.sh, with the guide's own fakes.
. "$(dirname "$0")/helpers.sh"
PY="$(command -v python3)"; GIT="$(command -v git)"

farm() {   # $T/sys: the system's commands without the ones this test fakes or takes away
  "$PY" - "$T/sys" <<'PY'
import os, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
skip = set("curl wget python3 apt-get apt sudo uname bun tmux gh gitleaks claude brew git security pass gpg pbcopy xclip xsel wl-copy".split())
for src in ("/usr/bin", "/bin", "/usr/sbin", "/sbin"):
    try: names = os.listdir(src)
    except OSError: continue
    for n in names:
        p = os.path.join(d, n)
        if n not in skip and not n.startswith("python3") and not os.path.lexists(p) and os.access(os.path.join(src, n), os.X_OK):
            os.symlink(os.path.join(src, n), p)
PY
}
# world: $F with a fake uname (Linux), apt-get and sudo that log to $CALLS; "apt-get install -y <tools>" makes each tool
# there (python3 and git: the real ones; curl: a file:// curl; anything else: a stub). $T/apt.fail: the apt-get
# subcommand (update or install) that fails. A release, ade 1.2.3, at file:// URLs (ADE_CLI_BASE, ADE_RELEASES_BASE).
world() {
  fresh; F="$T/fakebin"; CALLS="$T/calls"; mkdir -p "$F" "$T/cwd"; : > "$CALLS"; export F CALLS FT="$T" REAL_PY="$PY" REAL_GIT="$GIT"; farm
  export ADE_SKILLS_REPO="$T/no-ade-skills"   # A23: the guide's tools step never fetches recipes from the network here
  printf '#!/bin/bash\ncase "${1:-}" in ""|-s) echo "${FAKE_OS:-Linux}" ;; -m) echo x86_64 ;; *) exec "%s" "$@" ;; esac\n' "$(command -v uname)" > "$F/uname"
  cat > "$F/apt-get" <<'STUB'
#!/bin/bash
echo "apt-get $*" >> "$CALLS"
[ "$(cat "$FT/apt.fail" 2> /dev/null)" = "$1" ] && { echo "E: Some index files failed to download" >&2; exit 100; }
[ "$1" = install ] || exit 0
for t in "$@"; do case "$t" in install|-y) ;;
  python3) ln -sf "$REAL_PY" "$F/python3" ;; git) ln -sf "$REAL_GIT" "$F/git" ;; curl) cp "$FT/curl.later" "$F/curl"; chmod +x "$F/curl" ;;
  *) printf '#!/bin/bash\nexit 0\n' > "$F/$t"; chmod +x "$F/$t" ;; esac; done
STUB
  printf '#!/bin/bash\necho "sudo $*" >> "$CALLS"\nexec "$@"\n' > "$F/sudo"
  # curl and wget that serve file:// URLs and log each one ("curl <url>", "wget <url>")
  cat > "$T/curl.later" <<'STUB'
#!/bin/bash
out=-; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift ;; --max-time|--proto|--proto-redir|--connect-timeout) shift ;; *://*) url="$1" ;; esac; shift; done
echo "curl $url" >> "$CALLS"; f="${url#file://}"; [ -f "$f" ] || { echo "curl: (37) Couldn't open file $f" >&2; exit 37; }
if [ "$out" = - ]; then cat "$f"; else cp "$f" "$out"; fi
STUB
  sed 's/^echo "curl /echo "wget /; s/-o) out/-O) out/' "$T/curl.later" > "$T/wget.later"; chmod +x "$T/curl.later" "$T/wget.later"
  chmod +x "$F"/*
  export ADE_TEST_ALLOW_FILE_URLS=1 ADE_CLI_BASE="file://$T/raw" ADE_RELEASES_BASE="file://$T/gh"
  local d="$T/gh/better-ade/ade-cli/releases/download/v1.2.3" sha
  mkdir -p "$T/raw/main" "$T/raw/v1.2.3" "$d"; echo 1.2.3 > "$T/raw/main/VERSION"; cp "$REPO/ade" "$T/raw/v1.2.3/ade"
  sha="$( (shasum -a 256 "$T/raw/v1.2.3/ade" 2> /dev/null || sha256sum "$T/raw/v1.2.3/ade") | cut -d' ' -f1)"
  printf '{"component": "ade-cli", "version": "1.2.3", "files": [{"name": "ade", "sha256": "%s"}]}\n' "$sha" > "$d/release.json"
}
pre() { [ "$(id -u)" = 0 ] || printf 'sudo '; }   # what ade and install.sh put before apt-get
# piped <args>: install.sh as the one line runs it (bash reading it from a pipe), with no terminal; tty <keys>: the
# same on a pseudo-terminal, the keys typed ahead. The screen in $T/out.
piped() { (cd "$T/cwd" && env PATH="$F:$T/sys" bash -s -- "$T/prefix" < "$REPO/install.sh") > "$T/out" 2>&1; }
tty() { (cd "$T/cwd" && pty_run "$1" env PATH="$F:$T/sys" bash -c 'bash -s -- "$1" < "$2"' _ "$T/prefix" "$REPO/install.sh") > "$T/out" 2>&1; }
installed() { [ -x "$T/prefix/bin/ade" ] && [ "$(PATH="$F:$T/sys" "$T/prefix/bin/ade" version 2> /dev/null)" = "ade 1.2.3" ]; }

install_with_wget() {   # AC1: Ubuntu Desktop: wget and python3, no curl
  world; cp "$T/wget.later" "$F/wget"; ln -s "$PY" "$F/python3"
  piped || { cat "$T/out"; fail "the one line with wget only"; }
  installed || { cat "$T/out"; fail "ade 1.2.3 is installed"; }
  assert_contains "$CALLS" "wget file://$T/gh/better-ade/ade-cli/releases/download/v1.2.3/release.json" "release.json came with wget"
  assert_contains "$CALLS" "wget file://$T/raw/v1.2.3/ade" "and ade"; assert_not_contains "$T/out" "needs curl" "curl is never asked for"
  assert_not_contains "$CALLS" "apt-get" "nothing is installed with apt"
  printf '{"component": "ade-cli", "version": "1.2.3", "files": [{"name": "ade", "sha256": "%064d"}]}\n' 0 > "$T/gh/better-ade/ade-cli/releases/download/v1.2.3/release.json"
  rm -rf "$T/prefix"; piped && fail "a sha256 mismatch installs nothing"; assert_contains "$T/out" "does not match its sha256" "checked with wget too"
  [ ! -e "$T/prefix/bin/ade" ] || fail "nothing installed"
}

install_names_missing_first() {   # AC2: the missing tools, in one line, before any download
  world
  piped && fail "no curl, wget or python3: the install stops"
  assert_eq "$(grep -c '' "$T/out")" 2 "two lines: what is missing, then what to run"
  assert_eq "$(sed -n 1p "$T/out")" "install: this computer does not have curl python3 yet; the install needs them" "named in one plain line"
  assert_eq "$(cat "$CALLS")" "" "nothing downloaded, nothing run"; assert_not_contains "$T/out" "not valid" "never an invalid release.json"
  cp "$T/wget.later" "$F/wget"; piped && fail "no python3: the install stops"
  assert_eq "$(sed -n 1p "$T/out")" "install: this computer does not have python3 yet; the install needs it" "only python3, when wget is there"
  assert_eq "$(cat "$CALLS")" "" "still nothing downloaded"; assert_not_contains "$T/out" "release.json" "and no word about the manifest"
}

install_apt_after_yes() {   # AC3: one question, then apt-get update and apt-get install -y, then ade
  world; local p; p="$(pre)"
  piped; assert_contains "$T/out" "install: to install them, run: ${p}apt-get update && ${p}apt-get install -y curl python3; then run this install again; nothing installed" "no terminal: the command, nothing run"
  assert_eq "$(cat "$CALLS")" "" "no terminal: nothing run"
  tty "n\n"; assert_contains "$T/out" "Install curl python3 now? This runs: ${p}apt-get update && ${p}apt-get install -y curl python3 [y/N]" "one question, saying what it runs"
  assert_contains "$T/out" "install: nothing installed; to install curl python3 yourself, run: ${p}apt-get update && ${p}apt-get install -y curl python3" "a no: nothing"
  assert_eq "$(cat "$CALLS")" "" "a no runs nothing"; installed && fail "and installs nothing"
  tty "y\n"; installed || { cat "$T/out" "$CALLS"; fail "a yes: the tools, then ade"; }
  assert_eq "$(sed -n 1,2p "$CALLS" | sed 's/^sudo //' | tr '\n' '|')" "apt-get update|apt-get update|" "apt-get update first$( [ -n "$p" ] && echo ', with sudo')"
  grep -qxF "apt-get install -y curl python3" "$CALLS" || { cat "$CALLS"; fail "then apt-get install -y"; }
  [ "$(grep -n '^apt-get install' "$CALLS" | head -1 | cut -d: -f1)" -lt "$(grep -n '^curl ' "$CALLS" | head -1 | cut -d: -f1)" ] || fail "installed before any download"
  rm -rf "$T/prefix" "$F/curl" "$F/python3"; echo update > "$T/apt.fail"; : > "$CALLS"; tty "y\n"
  assert_contains "$T/out" "install: ${p}apt-get update failed; check the network and apt's sources, then run this install again; nothing installed" "a failed update: one line"
  assert_not_contains "$CALLS" "apt-get install" "and no install after it"; installed && fail "nothing installed"
  echo install > "$T/apt.fail"; tty "y\n"; assert_contains "$T/out" "install: ${p}apt-get install -y curl python3 failed; nothing installed" "a failed install: one line"
  rm "$T/apt.fail" "$F/apt-get"; piped; assert_contains "$T/out" "install: install curl python3 with your package manager, then run this install again; nothing installed" "no apt: says so"
  if [ -n "$p" ]; then rm "$F/sudo"; printf '#!/bin/bash\nexit 0\n' > "$F/apt-get"; chmod +x "$F/apt-get"; tty "y\n"
    assert_contains "$T/out" "install: there is no sudo here: as root, run apt-get update && apt-get install -y curl python3, then this install again" "no sudo: the root command"; fi
}

curl_is_required() {   # AC4: curl is named with the other required tools and installed before bun's download
  world; bun_fakes; mv "$F/curl" "$T/curl.later"; ln -s "$PY" "$F/python3"; ln -s "$GIT" "$F/git"; local p; p="$(pre)"; export FAKE_OS=Linux FAKE_CPU=x86_64
  printf '#!/bin/bash\ncase "${1:-}" in ""|-s) echo Linux ;; -m) echo x86_64 ;; *) exec "%s" "$@" ;; esac\n' "$(command -v uname)" > "$F/uname"
  (cd "$T/cwd" && PATH="$F:$T/sys" "$BASH" "$ADE" setup --tools required) > "$T/out" 2>&1 < /dev/null
  assert_contains "$T/out" "missing tools ade needs: curl tmux gh gitleaks bun" "curl, in the one line"
  (cd "$T/cwd" && PATH="$F:$T/sys" "$BASH" "$ADE" doctor) > "$T/out" 2>&1; grep -q "curl     missing (required: " "$T/out" || { cat "$T/out"; fail "ade doctor: curl is required"; }
  : > "$CALLS"; (cd "$T/cwd" && pty_run "y\ry\r" env PATH="$F:$T/sys" "$BASH" "$ADE" setup --tools required) > "$T/out" 2>&1
  grep -qxF "apt-get install -y curl tmux gh gitleaks" "$CALLS" || { cat "$CALLS" "$T/out"; fail "curl installed with the others"; }
  [ "$(grep -n '^apt-get install' "$CALLS" | cut -d: -f1)" -lt "$(grep -n '^curl .*bun' "$CALLS" | head -1 | cut -d: -f1)" ] || { cat "$CALLS"; fail "before bun's download"; }
  assert_contains "$T/out" "installed: bun " "so bun's download works"; assert_not_contains "$T/out" "command not found" "and nothing is not found"
  rm "$F/curl" "$F/tmux" "$F/gh" "$F/gitleaks"; rm -rf "$HOME/.bun"; : > "$CALLS"
  (cd "$T/cwd" && pty_run "n\rn\r" env PATH="$F:$T/sys" "$BASH" "$ADE" setup) > "$T/out" 2>&1
  assert_contains "$T/out" "missing tools ade needs: curl tmux gh gitleaks bun" "the guide names curl with the others"
  assert_contains "$T/out" "Install curl tmux gh gitleaks now? This runs: ${p}apt-get update && ${p}apt-get install -y curl tmux gh gitleaks" "in its one question"
}

apt_update_then_install() {   # AC5: ade's apt installs: update first, sudo unless root, and plain failures
  world; ln -s "$PY" "$F/python3"; ln -s "$GIT" "$F/git"; cp "$T/curl.later" "$F/curl"; printf '#!/bin/bash\necho bun 1\n' > "$F/bun"; chmod +x "$F/bun"; local p; p="$(pre)"
  S() { (cd "$T/cwd" && pty_run "$1" env PATH="$F:$T/sys" "$BASH" "$ADE" setup --tools required) > "$T/out" 2>&1; }
  S "y\r"; assert_contains "$T/out" "Install tmux gh gitleaks now? This runs: ${p}apt-get update && ${p}apt-get install -y tmux gh gitleaks [y/N]" "says both"
  assert_eq "$(grep '^apt-get' "$CALLS" | tr '\n' '|')" "apt-get update|apt-get install -y tmux gh gitleaks|" "runs update, then install"
  [ -z "$p" ] || assert_eq "$(grep '^sudo' "$CALLS" | tr '\n' '|')" "sudo apt-get update|sudo apt-get install -y tmux gh gitleaks|" "each with sudo"
  assert_contains "$T/out" "installed: tmux gh gitleaks" "and says so"
  rm "$F/tmux" "$F/gh" "$F/gitleaks"; echo update > "$T/apt.fail"; : > "$CALLS"; S "y\r"
  assert_contains "$T/out" "${p}apt-get update failed (exit 100), so nothing is installed; check the network and apt's sources" "a failed update: one plain line"
  assert_not_contains "$CALLS" "apt-get install" "and no install"
  echo install > "$T/apt.fail"; S "y\r"; assert_contains "$T/out" "${p}apt-get install -y tmux gh gitleaks failed (exit 100)" "a failed install: one plain line"
  assert_not_contains "$T/out" "run apt-get update first" "never the old advice: the update already ran"
  rm "$T/apt.fail"; (cd "$T/cwd" && PATH="$F:$T/sys" "$BASH" "$ADE" setup --tools required) > "$T/out" 2>&1 < /dev/null
  assert_contains "$T/out" "to install them, run at a terminal: ${p}apt-get update && ${p}apt-get install -y tmux gh gitleaks" "no terminal: the whole command"
  if [ -n "$p" ]; then rm "$F/sudo"; : > "$CALLS"; S "y\r"
    assert_contains "$T/out" "there is no sudo here, so ade cannot install: tmux gh gitleaks; as root, run: apt-get update && apt-get install -y tmux gh gitleaks" "no sudo: the root command"
    assert_eq "$(cat "$CALLS")" "" "and nothing run"; fi
}

readme_lists_ubuntu() {   # AC7: what Ubuntu needs, and the wget line
  local inst c w; inst="$(awk '/^## Install/ { on = 1; next } /^## / { on = 0 } on' "$REPO/README.md")"
  printf '%s\n' "$inst" | grep -qxF "sudo apt-get update && sudo apt-get install -y curl git python3" || fail "the README's Install section lists what Ubuntu needs"
  c="$(printf '%s\n' "$inst" | sed -n 's/^curl -fsSL \(https:[^ ]*\) | bash$/\1/p' | head -1)"; w="$(printf '%s\n' "$inst" | sed -n 's/^wget -qO- \(https:[^ ]*\) | bash$/\1/p' | head -1)"
  [ -n "$c" ] && [ "$c" = "$w" ] || fail "a wget one line with the curl line's URL: [$c] [$w]"
  printf '%s\n' "$inst" | grep -q "^curl -fsSL .* | bash$" || fail "the curl line stays"
}

ALL="install_with_wget install_names_missing_first install_apt_after_yes curl_is_required apt_update_then_install readme_lists_ubuntu"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
