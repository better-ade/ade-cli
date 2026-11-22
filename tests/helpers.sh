#!/bin/bash
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADE="$REPO/ade"
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3: got [$1] want [$2]"; }
assert_contains() { grep -qF -- "$2" "$1" || fail "$3: [$2] not in $1"; }
assert_not_contains() { ! grep -qF -- "$2" "$1" || fail "$3: [$2] unexpectedly in $1"; }
# every test starts clean: no tester's hub, ADE terminal or real home config reaches it
# drop_t: remove this test's own folder (only one fresh made, named ade-test.*); on exit and before the next fresh
drop_t() {
  [ -n "${T:-}" ] && [ -d "$T" ] || return 0
  case "$T" in */ade-test.?*) cd / && chmod -R u+w "$T" 2> /dev/null; rm -rf -- "$T" ;; esac
}
fresh() {
  unset ADE_HUB ADE_HOOK_BIN ADE_METHOD_REPO ADE_REGISTRY_REPO ADE_METHOD_REF ADE_REGISTRY_REF ADE_SKILLS_REPO ADE_SKILLS_REF CLAUDE_CONFIG_DIR
  unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID   # never an agent session (ade reset refuses one)
  export ADE_NO_UPDATE_CHECK=1 ADE_NO_AUTO_UPDATE=1   # never a real release check (test_releases.sh unsets them)
  drop_t; T="$(mktemp -d "${TMPDIR:-/tmp}/ade-test.XXXXXX")"; T="$(cd "$T" && pwd -P)"; trap drop_t EXIT
  export ADE_NO_CLAUDE_UPDATE=1   # the Claude Code update step is tested on its own (test_update.sh)
  export HOME="$T/home"; mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
}
# a minimal hub at $1 named $2: bin/work and bin/sessions print the hub name and each argument on its own line
make_hub() {
  mkdir -p "$1/bin"; : > "$1/bin/lib.sh"; : > "$1/hub.conf"
  local s; for s in work sessions; do
    printf '#!/bin/bash\necho "%s %s"\nfor a in "$@"; do echo "arg:$a"; done\n' "$2" "$s" > "$1/bin/$s"; chmod +x "$1/bin/$s"
  done
}
commit_tag() { git -C "$1" add -A && git -C "$1" commit -qm "$2" && { [ -z "${3:-}" ] || git -C "$1" tag "$3"; }; }
# a local ade-method fixture: tagged v2.1.0, then an untagged later commit the pin must not pick up
make_method_repo() {
  M="$T/method"; mkdir -p "$M/agents" "$M/bmad/custom" "$M/templates/context/decisions"; git init -q "$M"
  cat > "$M/ade.json" <<'JSON'
{ "format": 2,
  "install_templates": { "templates/pull_request_template.md": ".github/pull_request_template.md",
                         "templates/commit-template.txt": ".ade/commit-template.txt" } }
JSON
  echo "rules at v2" > "$M/rules.md"; echo "## Overview" > "$M/templates/pull_request_template.md"
  echo "<type>(<scope>): <summary>" > "$M/templates/commit-template.txt"
  echo "developer role" > "$M/agents/developer.md"; echo "reviewer role" > "$M/agents/reviewer.md"
  echo "[build]" > "$M/bmad/custom/bmad-build.toml"
  echo "context" > "$M/templates/context/README.md"; echo "adrs" > "$M/templates/context/decisions/README.md"
  echo "standards" > "$M/templates/standards.md"
  commit_tag "$M" v2 v2.1.0
  echo "rules after v2" > "$M/rules.md"; commit_tag "$M" later
  export ADE_METHOD_REPO="$M"
}
make_registry_repo() {
  R="$T/registry"; mkdir -p "$R/agents"; git init -q "$R"
  cat > "$R/registry.json" <<'JSON'
{
  "format": 1,
  "roles": [
    { "name": "frontend", "file": "agents/frontend.md", "description": "UI work: components, states, accessibility." },
    { "name": "backend", "file": "agents/backend.md", "description": "APIs, data and migrations." }
  ]
}
JSON
  echo "# Frontend v1.1" > "$R/agents/frontend.md"; echo "# Backend" > "$R/agents/backend.md"
  commit_tag "$R" v11 v1.1.0
  echo "# Frontend later" > "$R/agents/frontend.md"; commit_tag "$R" later
  export ADE_REGISTRY_REPO="$R"
}
# a fake `claude` on PATH: logs each call to $CLAUDE_LOG; marketplace add/list keep state in $CLAUDE_LOG.mkt
stub_claude() {
  local d="$T/fakebin"; mkdir -p "$d"; export CLAUDE_LOG="$T/claude.log"; : > "$CLAUDE_LOG"
  cat > "$d/claude" <<'STUB'
#!/bin/bash
echo "$*" >> "$CLAUDE_LOG"
if [ "$1 $2 $3" = "plugin marketplace list" ]; then cat "$CLAUDE_LOG.mkt" 2>/dev/null; exit 0; fi
if [ "$1 $2 $3" = "plugin marketplace add" ]; then echo "ade-skills" >> "$CLAUDE_LOG.mkt"; fi
exit 0
STUB
  chmod +x "$d/claude"; export PATH="$d:$PATH"
}
# a local ade-skills fixture: a marketplace with git, browser and notes, tagged v0.1.0
make_skills_repo() {
  K="$T/skills"; mkdir -p "$K/.claude-plugin"; git init -q "$K"
  cat > "$K/.claude-plugin/marketplace.json" <<'JSON'
{ "name": "ade-skills", "plugins": [
  { "name": "git", "source": "./plugins/git", "description": "Branch, commit and pull-request conventions." },
  { "name": "browser", "source": "./plugins/browser", "description": "Browser automation with read-only defaults." },
  { "name": "notes", "source": "./plugins/notes", "description": "Meeting notes into the knowledge folder." } ] }
JSON
  commit_tag "$K" k v0.1.0; export ADE_SKILLS_REPO="$K" ADE_SKILLS_REF=v0.1.0
}
# PATH without gh (for the "gh missing" checks): only the folders holding git, python3, curl and the basics
no_gh_path() { local d="$T/nogh" c p; mkdir -p "$d"; for c in git python3 bash sed awk grep mkdir cat dirname basename tr head tail mktemp mv chmod rm ls cp find sort printf env pwd date wc curl cut cksum shasum sha256sum uname; do
  p="$(command -v "$c")" && ln -sf "$p" "$d/$c"; done; echo "$d"; }
# pty_run <input> <command...>: the command on a fresh pseudo-terminal (its own session), the input typed ahead
# (\n escapes) with the terminal's echo off, so a typed key never shows in the transcript; prints what the terminal
# showed and exits with the command's code
pty_run() {
  python3 -c '
import os, pty, sys, termios, time
inp = sys.argv[1].encode().decode("unicode_escape").encode() + b"\x04" * 8   # then end-of-input, never a hang
pid, fd = pty.fork()
if pid == 0:
    a = termios.tcgetattr(0); a[3] &= ~termios.ECHO; termios.tcsetattr(0, termios.TCSANOW, a)
    os.execvp(sys.argv[2], sys.argv[2:])
t = time.time()
while termios.tcgetattr(fd)[3] & termios.ECHO and time.time() - t < 5:
    time.sleep(0.01)
os.write(fd, inp)
out = b""
while True:
    try:
        b = os.read(fd, 4096)
    except OSError:
        break
    if not b:
        break
    out += b
sys.stdout.write(out.decode("utf-8", "replace").replace("\r", ""))
_, st = os.waitpid(pid, 0)
sys.exit(os.WEXITSTATUS(st) if os.WIFEXITED(st) else 1)' "$@"
}
