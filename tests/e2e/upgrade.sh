#!/bin/bash
# story A8 layer 5: install the previous release tag, make a hub and a project with it, upgrade to this checkout, then
# re-run status, doctor and init: no file is lost or overwritten.
. "$(dirname "$0")/lib.sh"
head="$(git -C "$REPO" rev-parse HEAD)"; prev=""   # the newest release tag that is not this commit
for t in $(git -C "$REPO" tag --list 'v*' --sort=-v:refname); do [ "$(git -C "$REPO" rev-parse "$t^{commit}")" = "$head" ] || { prev="$t"; break; }; done
[ -n "$prev" ] || { echo "no earlier release tag: nothing to upgrade from"; exit 0; }
step "install the previous release $prev"; ADE_CLI_REF="$prev" bash "$REPO/install.sh" "$W/prefix" || fail "install $prev"
export PATH="$W/prefix/bin:$PATH"; fake_claude
[ "$(ade version)" = "ade ${prev#v}" ] || fail "old version: $(ade version)"
step "a hub and a project with $prev"
git clone -q https://github.com/better-ade/ade-brain "$W/hub" || fail "clone template"
(cd "$W/hub" && bin/init --persona devops-sre --client Example --owner owner1 --name up) || fail "bin/init"
mkdir -p "$HOME/.config/ade"; echo "$W/hub" > "$HOME/.config/ade/hub"
P="$W/proj"; mkdir -p "$P"; git init -q "$P"; (cd "$P" && ade init && ade agent add frontend) || fail "init with $prev"
before_p="$(snapshot "$P")"; before_h="$(snapshot "$W/hub")"
step "upgrade to this checkout"; bash "$REPO/install.sh" "$W/prefix" || fail "upgrade"
[ "$(ade version)" = "ade $(cat "$REPO/VERSION")" ] || fail "new version"
ade help | grep -q "^  orchestrator" || fail "the new binary is installed"
ade status || fail "status"; ade doctor; echo "doctor exit $?"
(cd "$P" && ade init) || fail "init after the upgrade"
check() {   # every file from before is still there, unchanged
  printf '%s\n' "$2" | while IFS= read -r l; do [ -n "$l" ] || continue
    printf '%s\n' "$3" | grep -qxF -- "$l" || { echo "changed or lost in $1: $l"; exit 1; }; done
}
check project "$before_p" "$(snapshot "$P")" || fail "project files kept"
check hub "$before_h" "$(snapshot "$W/hub")" || fail "hub files kept"
echo; echo "e2e upgrade from $prev: ok"
