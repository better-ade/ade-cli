#!/bin/bash
# bun is a required tool, installed without Homebrew: the pinned release zip for this OS and CPU from bun's GitHub
# release, its sha256 checked against the release's SHASUMS256.txt, the program put at ~/.bun/bin/bun. Fakes only
# (bun_fakes in helpers.sh: a curl that serves a fake release, uname, sysctl), a finished hub whose bin/chat says which
# bun it finds, a scratch HOME. Never the network, never a real bun, never the person's shell start file.
# SHOW_EXCHANGE=1 prints the tools-step transcript.
. "$(dirname "$0")/helpers.sh"

farm() {   # $T/sys: the system's commands without the ones faked here
  python3 - "$T/sys" "$(command -v python3)" "$(command -v git)" <<'PY'
import os, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
skip = set("code bun curl wget sysctl gitleaks claude gh brew apt-get apt sudo uname open xdg-open tmux yazi bat batcat glow pdftotext pdftoppm "
           "chafa security pass gpg pbcopy xclip xsel wl-copy".split())
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
# the world: every other tool is there, the guide's steps are done (a hub with a project, claude and gh signed in);
# bun is missing, and Homebrew is there only to show it is never asked for bun
world() {
  fresh; F="$T/fakebin"; H="$T/hub"; B="$HOME/.bun/bin/bun"; mkdir -p "$F" "$T/cwd"; farm
  export CALLS="$T/calls" ADE_HUB="$H" SHELL=/bin/zsh; : > "$CALLS"; unset FAKE_OS FAKE_CPU FAKE_ROSETTA
  make_hub "$H" acme; printf 'HUB_NAME=acme\nHUB_ROOT_PROVIDER=anthropic\n' > "$H/hub.conf"; mkdir -p "$H/projects/web"
  printf '#!/bin/bash\necho "chat $* bun=$(command -v bun)" >> "$CALLS"\n' > "$H/bin/chat"
  printf '#!/bin/bash\necho "hub doctor bun=$(command -v bun)"\n' > "$H/bin/doctor"; printf '#!/bin/bash\nexit 0\n' > "$H/bin/keys"
  printf '#!/bin/bash\necho "brew $*" >> "$CALLS"\n' > "$F/brew"; printf '#!/bin/bash\n[ "$1" != api ] || echo tester\n' > "$F/gh"
  local c; for c in claude tmux gitleaks yazi bat glow pdftotext pdftoppm chafa code; do printf '#!/bin/bash\nexit 0\n' > "$F/$c"; done
  chmod +x "$F"/* "$H/bin/"*; bun_fakes
}
# talk <keys> [args]: ade on an 80-column terminal, typed as a person types: each line of <keys> is sent when ade waits
# at a prompt; a line "!<command>" is what the person does elsewhere before pressing Enter; then end of input
talk() {
  local k="$1"; shift
  (cd "$T/cwd" && python3 -c '
import os, pty, select, sys, time
keys = sys.argv[1].encode().decode("unicode_escape").split("\n")[:-1]
pid, fd = pty.fork()
if pid == 0: os.execvp(sys.argv[2], sys.argv[2:])
out, last, sent, end = b"", time.time(), -1, time.time() + 90
while time.time() < end:
    if select.select([fd], [], [], 0.05)[0]:
        try: d = os.read(fd, 4096)
        except OSError: break
        if not d: break
        out += d; last = time.time(); continue
    if out.endswith(b" ") and time.time() - last > 0.2 and sent != len(out):
        sent = len(out)
        if not keys: os.write(fd, b"\x04"); continue
        k = keys.pop(0)
        if k.startswith("!"): os.system(k[1:]); k = ""
        os.write(fd, (k + "\n").encode())
sys.stdout.write(out.decode("utf-8", "replace").replace("\r", ""))
_, st = os.waitpid(pid, 0); sys.exit(os.WEXITSTATUS(st) if os.WIFEXITED(st) else 1)' "$k" env PATH="${ADE_TEST_PATH:-$F:$T/sys}" COLUMNS=80 LINES=24 "$BASH" "$ADE" "$@") > "$T/out" 2>&1
}
A() { (cd "$T/cwd" && PATH="${ADE_TEST_PATH:-$F:$T/sys}" "$BASH" "$ADE" "$@") > "$T/out" 2>&1; }   # without a terminal
last_line() { grep -v '^[[:space:]]*$' "$T/out" | tail -1; }
fits() { local l; while IFS= read -r l; do l="${l%%]: *}"; [ "${#l}" -le 80 ] || fail "wider than 80 columns: [$l]"; done < <(sed "s#$T#<T>#g" "$T/out"); }
curls() { grep -c '^curl ' "$CALLS"; }
choices() { local s; for s in "  1) retry   try again" "  2) manual  show the manual steps" "  3) stop    stop here" "What now? [retry]:"; do assert_contains "$T/out" "$s" "the choices: $s"; done; }
RC_LINE='export PATH="$HOME/.bun/bin:$PATH"   # added by ade: bun'

bun_asset_per_os_and_cpu() {   # the release zip is the one for this OS and CPU
  local os cpu ros want
  while read -r os cpu ros want; do
    world; FAKE_OS="$os" FAKE_CPU="$cpu" FAKE_ROSETTA="$ros" talk "y\n" setup --tools; assert_eq "$?" 0 "$os $cpu: installed"
    assert_eq "$(grep '^curl ' "$CALLS" | tr '\n' ';')" "curl $BUN_URL/$want.zip;curl $BUN_URL/SHASUMS256.txt;" "$os $cpu: the pinned release's $want.zip and its SHASUMS256.txt, nothing else"
    assert_contains "$B" "# $want" "$os $cpu: what is in ~/.bun/bin/bun came from $want.zip"
  done <<EOF2
Darwin arm64 0 bun-darwin-aarch64
Darwin x86_64 0 bun-darwin-x64
Darwin x86_64 1 bun-darwin-aarch64
Linux x86_64 0 bun-linux-x64
Linux aarch64 0 bun-linux-aarch64
Linux amd64 0 bun-linux-x64
EOF2
  assert_eq "$(grep -c "^BUN_VERSION=" "$ADE")" 1 "the version is pinned in one place"; assert_eq "$(grep -c "$BUN_V" "$ADE")" 1 "and written nowhere else in ade"
}

bun_checksum_verified() {   # the zip's sha256 must be the one SHASUMS256.txt of the same release names; a mismatch never installs
  world; talk "y\n" setup --tools; assert_eq "$?" 0 "a matching sha256 installs"
  assert_contains "$T/out" "installed: bun $BUN_V in ~/.bun/bin/bun" "said"; assert_eq "$("$B" --version)" "$BUN_V" "the pinned bun, where bin/chat looks"
  assert_eq "$(ls -l "$B" | cut -c1-10)" "-rwxr-xr-x" "mode 0755"; assert_eq "$(ls "$HOME/.bun/bin")" "bun" "and nothing else left beside it"
  assert_eq "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'ade.*' -newer "$CALLS" 2> /dev/null | wc -l | tr -d ' ')" 0 "the download folder is removed"
  world; cp "$BUN_REL/SHASUMS256.txt" "$T/sums.good"; sed 's/^[0-9a-f]\{8\}/deadbeef/' "$T/sums.good" > "$BUN_REL/SHASUMS256.txt"
  talk "y\n!cp $T/sums.good $BUN_REL/SHASUMS256.txt\n" setup --tools; rc=$?
  assert_contains "$T/out" "bun-darwin-aarch64.zip does not match its sha256; nothing installed" "a mismatch: one plain line"
  assert_contains "$T/out" "details: SHASUMS256.txt of bun-v$BUN_V names another sha256 for it" "where"; choices; fits
  assert_eq "$(curls)" 4 "try again downloads both again"; assert_eq "$rc" 0 "and installs once they match"; [ -x "$B" ] || fail "installed after the retry"
  world; sed 's/^[0-9a-f]\{8\}/deadbeef/' "$BUN_REL/SHASUMS256.txt" > "$T/s"; cp "$T/s" "$BUN_REL/SHASUMS256.txt"; talk "y\nstop\n" setup --tools; assert_eq "$?" 1 "stop: exit 1"
  [ ! -e "$HOME/.bun" ] || fail "a mismatch installs nothing: no ~/.bun"; [ ! -e "$HOME/.zshrc" ] || fail "and adds no PATH line"
  assert_eq "$(last_line)" "ade: stopped; to come back, run ade setup --tools" "and how to come back"
  world; grep -v darwin-aarch64 "$BUN_REL/SHASUMS256.txt" > "$T/s"; cp "$T/s" "$BUN_REL/SHASUMS256.txt"; talk "y\nstop\n" setup --tools
  assert_contains "$T/out" "SHASUMS256.txt names no sha256 for bun-darwin-aarch64.zip; nothing installed" "no sha256 for the zip: refused"; [ ! -e "$HOME/.bun" ] || fail "nothing installed"
  world; echo "<html>not found</html>" > "$BUN_REL/SHASUMS256.txt"; talk "y\nstop\n" setup --tools
  assert_contains "$T/out" "names no sha256 for bun-darwin-aarch64.zip" "a page that is not the list: refused"; [ ! -e "$HOME/.bun" ] || fail "nothing installed"
}

bun_path_line_once() {   # ~/.bun/bin not on PATH: one marked line in the shell's start file, said first, never twice
  world; printf 'alias l=ls' > "$HOME/.zshrc"; talk "y\n" setup --tools
  assert_contains "$T/out" "~/.bun/bin is not on your PATH: ade adds one line to ~/.zshrc, so a new" "said"
  assert_contains "$T/out" "  $RC_LINE" "with the line itself"; fits
  [ "$(grep -n 'adds one line' "$T/out" | cut -d: -f1)" -lt "$(grep -n '^installed: bun' "$T/out" | cut -d: -f1)" ] || fail "said before the end"
  assert_eq "$(cat "$HOME/.zshrc")" "alias l=ls
$RC_LINE" "zsh: ~/.zshrc, the line after what was there (which had no last newline)"
  [ ! -e "$HOME/.bashrc" ] && [ ! -e "$HOME/.profile" ] || fail "and no other start file"
  rm "$B"; talk "y\n" setup --tools; [ -x "$B" ] || fail "installed again"
  assert_eq "$(grep -c '\.bun/bin' "$HOME/.zshrc")" 1 "installed again: the line is not added twice"; assert_not_contains "$T/out" "adds one line" "nor said"
  world; export SHELL=/usr/local/bin/bash; talk "y\n" setup --tools; assert_eq "$(cat "$HOME/.bashrc")" "$RC_LINE" "bash: ~/.bashrc"; [ ! -e "$HOME/.zshrc" ] || fail "not ~/.zshrc"
  world; export SHELL=/usr/bin/fish; talk "y\n" setup --tools; assert_eq "$(cat "$HOME/.profile")" "$RC_LINE" "another shell: ~/.profile"
  world; echo 'export BUN_INSTALL="$HOME/.bun"; export PATH="$BUN_INSTALL/bin:$PATH"; . ~/.bun/bin/x' > "$HOME/.zshrc"; cp "$HOME/.zshrc" "$T/rc"; talk "y\n" setup --tools
  cmp -s "$T/rc" "$HOME/.zshrc" || fail "a start file that already names ~/.bun/bin is left as it is"
  world; ADE_TEST_PATH="$F:$T/sys:$HOME/.bun/bin" talk "y\n" setup --tools; [ -x "$B" ] || fail "installed"
  [ ! -e "$HOME/.zshrc" ] || fail "~/.bun/bin already on PATH: no line"; assert_not_contains "$T/out" "not on your PATH" "and nothing said about PATH"
  world; mkdir "$HOME/.zshrc"; talk "y\n" setup --tools; assert_contains "$T/out" "ade could not write ~/.zshrc; add that line to it yourself" "a start file ade cannot write: said"
  [ -x "$B" ] || fail "bun is installed all the same"
}

bun_found_in_the_same_session() {   # ade and the hub commands it runs find ~/.bun/bin/bun, as the hub's bin/chat looks for it (command -v bun)
  world; talk "y\n" setup --tools; : > "$CALLS"; A chat start < /dev/null
  assert_eq "$(cat "$CALLS")" "chat start bun=$B" "the hub's bin/chat finds bun, with ~/.bun/bin not on the person's PATH"
  A setup --tools < /dev/null; assert_eq "$(cat "$T/out")" "tools: everything ade uses is installed" "and ade itself does"
  mkdir -p "$T/other"; cp "$F/tmux" "$T/other/bun"; : > "$CALLS"; ADE_TEST_PATH="$T/other:$F:$T/sys" A chat start < /dev/null
  assert_eq "$(cat "$CALLS")" "chat start bun=$T/other/bun" "a bun already on PATH stays the one that is found"
}

bun_already_installed_left_alone() {   # Homebrew's bun, or one in ~/.bun/bin: nothing downloaded, nothing changed
  world; mkdir -p "$T/homebrew/bin"; printf '#!/bin/bash\necho 1.0.0\n' > "$T/homebrew/bin/bun"; chmod +x "$T/homebrew/bin/bun"
  ADE_TEST_PATH="$T/homebrew/bin:$F:$T/sys" talk "y\n" setup --tools; assert_eq "$(cat "$T/out")" "tools: everything ade uses is installed" "Homebrew's bun counts"
  assert_eq "$(cat "$CALLS")" "" "nothing downloaded, and brew is not run"; [ ! -e "$HOME/.bun" ] || fail "no ~/.bun"; [ ! -e "$HOME/.zshrc" ] || fail "no PATH line"
  assert_eq "$("$T/homebrew/bin/bun" --version)" "1.0.0" "it is left as it was"
  world; mkdir -p "$HOME/.bun/bin"; printf '#!/bin/bash\necho 1.0.0\n' > "$B"; chmod +x "$B"; before="$(cksum "$B")"
  talk "y\n" setup --tools; assert_contains "$T/out" "tools: everything ade uses is installed" "a bun in ~/.bun/bin counts, on PATH or not"
  assert_eq "$(cat "$CALLS")" "" "nothing downloaded"; assert_eq "$(cksum "$B")" "$before" "it is left as it was"
  # the owner's Mac, 2026-11-23: bun in ~/.bun/bin, not on PATH, so the hub's bin/chat in a new terminal found none
  assert_contains "$T/out" "~/.bun/bin is not on your PATH: ade adds one line to ~/.zshrc, so a new" "not on PATH: said"
  assert_eq "$(cat "$HOME/.zshrc")" "$RC_LINE" "and the start file gets the line, so a new terminal finds bun"
  talk "" setup --tools; assert_eq "$(cat "$T/out")" "tools: everything ade uses is installed" "run again: nothing more"
  assert_eq "$(grep -c '\.bun/bin' "$HOME/.zshrc")" 1 "the line once"
  world; mkdir -p "$HOME/.bun/bin"; printf '#!/bin/bash\necho 1.0.0\n' > "$B"; chmod +x "$B"; talk "y\n" setup
  assert_contains "$HOME/.zshrc" "$RC_LINE" "the guide's tools step does the same"
  world; mkdir -p "$HOME/.bun/bin"; printf '#!/bin/bash\necho 1.0.0\n' > "$B"; chmod +x "$B"; CLAUDECODE=1 A setup --tools < /dev/null
  [ ! -e "$HOME/.zshrc" ] || fail "an agent session never writes the start file"
  world; mkdir -p "$HOME/.bun/bin"; printf '#!/bin/bash\necho 1.0.0\n' > "$B"; chmod +x "$B"; ADE_TEST_PATH="$F:$T/sys:$HOME/.bun/bin" talk "" setup --tools
  [ ! -e "$HOME/.zshrc" ] || fail "~/.bun/bin already on the person's PATH: no line"
  world; rm "$F/tmux"; talk "y\ny\n" setup --tools
  assert_eq "$(grep -c '^brew ' "$CALLS")" 1 "Homebrew installs the other tools"; assert_contains "$CALLS" "brew install tmux" "tmux"; assert_not_contains "$CALLS" "brew install tmux bun" "never bun"
  [ -x "$B" ] || fail "bun from its release, in the same run"
}

bun_in_doctor() {   # ade doctor lists it
  world; A doctor < /dev/null; assert_contains "$T/out" "  bun      missing (required: the Telegram plugin runs on it)" "missing, and why"
  assert_contains "$T/out" "  ade setup --tools installs what is missing" "and how"
  talk "y\n" setup --tools; A doctor < /dev/null; assert_contains "$T/out" "  bun      installed" "installed"; assert_contains "$T/out" "hub doctor bun=$B" "and the hub's doctor finds it"
}

bun_in_the_guide_tools_step() {   # the guide's tools step installs it, before any other step, with no Homebrew at all
  world; rm "$F/brew"; talk "y\n" setup; rc=$?
  [ -z "${SHOW_EXCHANGE:-}" ] || sed "s#$T#<T>#g" "$T/out" >&2
  assert_contains "$T/out" "missing tools ade needs: bun" "the tools step names it"; assert_contains "$T/out" "Install bun now? [y/N]" "one question"
  assert_contains "$T/out" "bun $BUN_V: ade downloads it from github.com/oven-sh/bun, checks its sha256 and" "saying what a yes does"
  assert_contains "$T/out" "puts it in ~/.bun/bin/bun. Homebrew is not used, and no script is run." "and what it does not"
  assert_contains "$T/out" "installed: bun $BUN_V in ~/.bun/bin/bun" "installed"; [ -x "$B" ] || fail "in ~/.bun/bin/bun"
  assert_contains "$T/out" "All set: your hub acme is ready" "and the guide goes on"; assert_eq "$rc" 0 "exit 0"; fits
  [ "$(grep -n '^installed: bun' "$T/out" | cut -d: -f1)" -lt "$(grep -n '^All set' "$T/out" | cut -d: -f1)" ] || fail "in the tools step, before the steps"
  assert_not_contains "$T/out" "Homebrew is not installed" "Homebrew is never needed for bun"
  talk "" setup; assert_not_contains "$T/out" "bun" "run again: nothing about bun"
  world; rm "$F/brew" "$F/tmux"; talk "y\n" setup; assert_contains "$T/out" "Homebrew is not installed (https://brew.sh), so ade cannot install: tmux" "no Homebrew: the other tools wait"
  [ -x "$B" ] || fail "and bun is installed all the same"
  world; rm "$F/brew"; token="$T/keystore"; printf '#!/bin/bash\n[ "${1:-}" = set ] && { cat > /dev/null; : > "%s"; exit 0; }\n[ -f "%s" ] && echo "telegram stored"; exit 0\n' "$token" "$token" > "$H/bin/keys"
  rm -rf "$H/projects/web"; printf '#!/bin/bash\n[ "$1 $2" = "auth status" ] && exit 0\nmkdir -p projects/web\n' > "$F/claude"
  talk "y\ny\n123456789:AAH-S3CRETs3cretS3CRETs3cretS3CRETs3c\nlater\n" setup
  assert_contains "$T/out" "Step 6 of 6: Telegram (optional)" "a first run reaches the Telegram step"; assert_not_contains "$T/out" "Next: bun" "which has nothing to do about bun"
  assert_eq "$(grep -c 'Install bun now' "$T/out")" 1 "asked once, in the tools step"
  world; : > "$CALLS"; PATH="$F:$T/sys" "$BASH" "$REPO/install.sh" "$T/prefix" > "$T/out" 2>&1 < /dev/null
  assert_contains "$T/out" "missing tools ade needs: bun" "install.sh, piped: bun is named"; assert_contains "$T/out" "to install bun, run at a terminal: ade setup --tools" "with how"
  assert_eq "$(cat "$CALLS")" "" "and nothing is downloaded"
  FAKE_OS=Darwin pty_run "y\r" env PATH="$F:$T/sys" "$BASH" "$REPO/install.sh" "$T/prefix" > "$T/out" 2>&1
  assert_contains "$T/out" "installed: bun $BUN_V in ~/.bun/bin/bun" "install.sh at a terminal: bun after a yes"; [ -x "$B" ] || fail "installed by the installer's tools step"
}

bun_failures() {   # download, unzip, a bun that does not run, an unsupported CPU: one plain line, then try again / manual / stop
  world; printf 'curl: (6) Could not resolve host: github.com\n' > "$T/curl.fail"; talk "y\n\n" setup --tools; rc=$?
  assert_contains "$T/out" "The download of bun $BUN_V did not finish" "a download that fails: one plain line"
  assert_contains "$T/out" "details: curl: (6) Could not resolve host: github.com" "with curl's own reason"; choices; fits
  assert_eq "$rc" 0 "Enter tries again, and it installs"; [ -x "$B" ] || fail "installed after the retry"
  world; printf 'x\ny\n' > "$T/curl.fail"; talk "y\nmanual\n" setup --tools; rc=$?
  for s in "To install bun $BUN_V yourself:" "  1. from https://github.com/oven-sh/bun/releases/tag/bun-v$BUN_V" "     download bun-darwin-aarch64.zip and SHASUMS256.txt" \
    "  2. shasum -a 256 bun-darwin-aarch64.zip must print the sha256 that" "     SHASUMS256.txt has for it" \
    "  3. unzip bun-darwin-aarch64.zip && mkdir -p ~/.bun/bin &&" "     mv bun-darwin-aarch64/bun ~/.bun/bin/bun" "then run ade setup --tools"; do assert_contains "$T/out" "$s" "the manual steps: $s"; done
  assert_eq "$rc" 1 "not installed: exit 1"; [ ! -e "$HOME/.bun" ] || fail "nothing installed"; fits
  assert_not_contains "$T/out" "| bash" "no script piped to a shell, not even shown"; ! grep -q 'bun\.sh/install' "$ADE" || fail "bun's install script is nowhere in ade"
  world; echo "not a zip" > "$BUN_REL/bun-darwin-aarch64.zip"; printf '%s  bun-darwin-aarch64.zip\n' "$(shasum -a 256 "$BUN_REL/bun-darwin-aarch64.zip" 2> /dev/null | cut -d' ' -f1 || sha256sum "$BUN_REL/bun-darwin-aarch64.zip" | cut -d' ' -f1)" > "$BUN_REL/SHASUMS256.txt"
  talk "y\nstop\n" setup --tools; assert_eq "$?" 1 "stop"
  assert_contains "$T/out" "bun-darwin-aarch64.zip could not be unpacked; nothing installed" "a zip that does not unpack"; [ ! -e "$HOME/.bun" ] || fail "nothing installed"
  world; python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1], "w").writestr("bun-darwin-aarch64/bun", "#!/bin/bash\nexit 132\n")' "$BUN_REL/bun-darwin-aarch64.zip"
  printf '%s  bun-darwin-aarch64.zip\n' "$(shasum -a 256 "$BUN_REL/bun-darwin-aarch64.zip" 2> /dev/null | cut -d' ' -f1 || sha256sum "$BUN_REL/bun-darwin-aarch64.zip" | cut -d' ' -f1)" > "$BUN_REL/SHASUMS256.txt"
  talk "y\nstop\n" setup --tools; assert_contains "$T/out" "bun $BUN_V does not run on this computer; nothing installed" "a bun that does not run is not installed"; [ ! -e "$HOME/.bun" ] || fail "nothing installed"
  world; rm "$BUN_REL/SHASUMS256.txt"; talk "y\nstop\n" setup --tools
  assert_contains "$T/out" "The download of bun's SHASUMS256.txt did not finish; nothing installed" "no SHASUMS256.txt: nothing to check against, so nothing installed"
  assert_contains "$T/out" "details: curl: (22) The requested URL returned error: 404" "with curl's reason"; [ ! -e "$HOME/.bun" ] || fail "nothing installed"
  world; : > "$HOME/.bun"; talk "y\nstop\n" setup --tools; assert_contains "$T/out" "ade could not write ~/.bun/bin/bun; nothing installed" "a ~/.bun ade cannot write in"
  [ ! -s "$HOME/.bun" ] || fail "what was there is left"; [ ! -e "$HOME/.zshrc" ] || fail "and no PATH line"
  world; FAKE_CPU=riscv64 FAKE_OS=Linux talk "y\nmanual\n" setup --tools; assert_eq "$?" 1 "an unsupported CPU: not installed"
  assert_contains "$T/out" "bun has no download for this computer (Linux riscv64)" "said in one plain line"; choices
  assert_contains "$T/out" "  https://bun.sh/docs/installation lists the computers bun runs on" "the manual steps: bun's own page"; assert_eq "$(curls)" 0 "nothing downloaded"
  world; FAKE_OS=FreeBSD talk "y\nstop\n" setup --tools; assert_contains "$T/out" "bun has no download for this computer (FreeBSD arm64)" "nor another OS"
  world; talk "n\n" setup --tools; assert_eq "$?" 1 "no: exit 1"; assert_eq "$(last_line)" "nothing installed (later: ade setup --tools)" "a no installs nothing"; assert_eq "$(curls)" 0 "no download"
  A setup --tools < /dev/null; assert_eq "$(last_line)" "to install bun, run at a terminal: ade setup --tools" "no terminal: named, with how"; assert_eq "$(curls)" 0 "no download"
  (export CLAUDECODE=1; talk "y\n" setup --tools); assert_contains "$T/out" "ade installs nothing from an agent session; run it yourself at a terminal: ade setup --tools" "an agent session"
  assert_eq "$(curls)" 0 "no download"; [ ! -e "$HOME/.bun" ] || fail "nothing installed"
}

ALL="bun_asset_per_os_and_cpu bun_checksum_verified bun_path_line_once bun_found_in_the_same_session bun_already_installed_left_alone bun_in_doctor bun_in_the_guide_tools_step bun_failures"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
