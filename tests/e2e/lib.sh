#!/bin/bash
# shared by the e2e scripts (story A8): a fresh HOME and prefix, the ade of this checkout installed, real git.
# These scripts use the network (the pinned real repos); tests/run.sh never does.
set -u
# shellcheck disable=SC2034  # REPO and W are used by the scripts that source this file
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"; export HOME="$W/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=e2e GIT_AUTHOR_EMAIL=e2e@example.invalid GIT_COMMITTER_NAME=e2e GIT_COMMITTER_EMAIL=e2e@example.invalid
unset ADE_HUB ADE_HOOK_BIN ADE_METHOD_REPO ADE_REGISTRY_REPO ADE_METHOD_REF ADE_REGISTRY_REF ADE_SKILLS_REPO ADE_SKILLS_REF TMUX
step() { echo; echo "== $*"; }
fail() { echo "E2E FAIL: $*" >&2; exit 1; }
# a fake claude: CI holds no Claude secret (the live smoke is a later story); it logs and succeeds
fake_claude() {
  mkdir -p "$W/fakebin"; cat > "$W/fakebin/claude" <<'C'
#!/bin/bash
echo "claude $*" >> "$HOME/claude.log"
case "$1 ${2:-} ${3:-}" in "plugin marketplace list") cat "$HOME/claude.mkt" 2>/dev/null ;; "plugin marketplace add") echo ade-skills >> "$HOME/claude.mkt" ;; esac
case "$*" in *--remote-control*) echo "orchestrator ready"; exec sleep 600 ;; esac
exit 0
C
  chmod +x "$W/fakebin/claude"; export PATH="$W/fakebin:$PATH"
}
snapshot() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(cksum < "$f" | tr -s ' ' | cut -d' ' -f1-2)" "$f"; done); }
