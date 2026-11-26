#!/bin/bash
# story I3: ade hub import end to end. HOME A makes a hub from the real ade-brain template, pinned to a commit with
# bin/adopt (I2); HOME B imports it three ways (--share, --handover, --clone --no-github). Each ends with the hub's
# bin/doctor passing and ade hub list showing it. Real git and the real hub scripts; no GitHub (network: the clone).
. "$(dirname "$0")/lib.sh"
BRAIN_PIN="${ADE_E2E_BRAIN_PIN:-424d127f26e10546b520e00e2b8a51061e4849da}"   # ade-brain main with I1 and I2 (PR #92)
step "install from this checkout"; bash "$REPO/install.sh" "$W/prefix" || fail "install"
export PATH="$W/prefix/bin:$PATH"; fake_claude

step "the ade-brain template at the pin"
git clone -q https://github.com/better-ade/ade-brain "$W/template" || fail "clone template"
git -C "$W/template" checkout -q -B main "$BRAIN_PIN" || fail "checkout $BRAIN_PIN"
[ -x "$W/template/bin/adopt" ] || fail "the pinned template has no bin/adopt"
export ADE_HUB_TEMPLATE_URL="$W/template"

step "HOME A: ade hub new --no-github"
export HOME="$W/homeA"; mkdir -p "$HOME"
ade hub new team --no-github --dir "$W/a" --persona devops-sre --client Example --owner owner1 < /dev/null || fail "hub new"
SRC="$W/a/team"
# the hub's first save needs gitleaks (hub_first_save); where it is missing, the fixture commits the rendered hub itself
if [ -n "$(git -C "$SRC" status --porcelain)" ]; then
  git -C "$SRC" add -A && git -C "$SRC" -c core.hooksPath=/dev/null commit -qm "the hub as bin/init rendered it" || fail "commit hub A"
fi

export HOME="$W/homeB"; mkdir -p "$HOME"
check() {   # <folder> <mode>: bin/doctor passes, ade hub list shows it as the default
  local h; h="$(cd "$1" && pwd -P)" || fail "$2: no folder $1"
  (cd "$h" && HUB="$h" ./bin/doctor < /dev/null > "$W/doctor.out" 2>&1) || { cat "$W/doctor.out"; fail "$2: bin/doctor"; }
  ade hub list > "$W/list.out" || fail "$2: hub list"
  grep -qxF "* $h" "$W/list.out" || { cat "$W/list.out"; fail "$2: not the default in ade hub list"; }
}
step "HOME B: --share"
ade hub import "$SRC" --share --name shared --dir "$W/b" < /dev/null > "$W/share.out" 2>&1 || { cat "$W/share.out"; fail "import --share"; }
cat "$W/share.out"; grep -q "Left to do by hand:" "$W/share.out" || fail "share: no list of what is left"
check "$W/b/shared" share
owner_is() { [ "$(. "$1/hub.conf" > /dev/null 2>&1; printf '%s' "${HUB_OWNER:-}")" = "$2" ]; }   # <hub> <name>
owner_is "$W/b/shared" owner1 || fail "share: the owner stays"

step "HOME B: --handover"
ade hub import "$SRC" --handover --owner "Ana Lee" --name taken --dir "$W/b" < /dev/null > "$W/hand.out" 2>&1 || { cat "$W/hand.out"; fail "import --handover"; }
cat "$W/hand.out"; owner_is "$W/b/taken" "Ana Lee" || fail "handover: the new owner"
check "$W/b/taken" handover

step "HOME B: --clone --no-github"
ade hub import "$SRC" --clone --owner "Ana Lee" --name anas --dir "$W/b" --no-github < /dev/null > "$W/clone.out" 2>&1 || { cat "$W/clone.out"; fail "import --clone"; }
cat "$W/clone.out"; [ "$(git -C "$W/b/anas" rev-list --count HEAD)" = 1 ] || fail "clone: one commit"
[ -z "$(git -C "$W/b/anas" remote)" ] || fail "clone: no remote"
owner_is "$W/b/anas" "Ana Lee" || fail "clone: the new owner"
check "$W/b/anas" clone
for h in shared taken anas; do grep -qF "$W/b/$h" "$W/list.out" || fail "ade hub list misses $h"; done
echo; echo "e2e import: ok"
