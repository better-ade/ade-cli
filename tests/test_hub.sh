#!/bin/bash
# story A3: `ade hub new|list|use`, `ade` alone, and the curl install. Fake gh, local template repo, fake bin/init.
# story I3: `ade hub import`, against a local fake hub (bin/setup and bin/adopt log their calls).
. "$(dirname "$0")/helpers.sh"

# a local hub template: bin/lib.sh and a bin/init that writes hub.conf and logs where it ran
make_template() {
  TPL="$T/template"; mkdir -p "$TPL/bin"; git init -q "$TPL"; : > "$TPL/bin/lib.sh"
  cat > "$TPL/bin/init" <<STUB
#!/bin/bash
[ "\${1:-}" = --list ] && { echo "sre                          Site reliability"; exit 0; }
echo "init in \$PWD: \$*" >> "$T/init.log"; echo "HUB_NAME=\$(basename "\$PWD")" > hub.conf
STUB
  chmod +x "$TPL/bin/init"; commit_tag "$TPL" tpl; export ADE_HUB_TEMPLATE_URL="$TPL"
}
ID="--persona sre --client Acme --owner owner1"   # bin/init's required answers, given as flags
# a fake gh: logs "<pwd>: <args>"; repo create <name> ... --clone clones the local template into <name>
stub_gh() {
  local d="$T/fakebin"; mkdir -p "$d"; export GH_LOG="$T/gh.log"; : > "$GH_LOG"
  printf '#!/bin/bash\necho "$PWD: $*" >> "$GH_LOG"\n[ "$1 $2" = "repo create" ] && git clone -q "%s" "$3"\nexit 0\n' "$TPL" > "$d/gh"
  chmod +x "$d/gh"; export PATH="$d:$PATH"
}

new_with_github() {   # AC1
  fresh; make_template; stub_gh
  bash "$ADE" hub new acme $ID < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "hub new exit"; }
  assert_contains "$GH_LOG" "$HOME/hubs: repo create acme --template better-ade/ade-brain --private --clone" "gh call in ~/hubs"
  assert_contains "$T/init.log" "init in $HOME/hubs/acme: --persona sre --client Acme --owner owner1 --name acme" "bin/init ran in the new hub with its answers"
  assert_eq "$(cat "$HOME/.config/ade/hub")" "$HOME/hubs/acme" "saved as the default"
}

public_and_dir() {   # AC2
  fresh; make_template; stub_gh; mkdir -p "$T/elsewhere"
  bash "$ADE" hub new pub --public --dir "$T/elsewhere" $ID < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "exit"; }
  assert_contains "$GH_LOG" "$T/elsewhere: repo create pub --template better-ade/ade-brain --public --clone" "public in --dir"
  assert_not_contains "$GH_LOG" "--private" "private only by default"
  [ -f "$T/elsewhere/pub/hub.conf" ] || fail "hub made in --dir"
}

no_github() {   # AC3
  fresh; make_template; stub_gh
  printf 'sre\nAcme Corp\nowner1\n' | bash "$ADE" hub new loc --no-github > "$T/out" 2>&1 || { cat "$T/out"; fail "exit"; }
  [ ! -s "$GH_LOG" ] || fail "gh not called"
  [ -x "$HOME/hubs/loc/bin/init" ] || fail "template cloned"
  assert_eq "$(git -C "$HOME/hubs/loc" remote)" "" "remote unset"
  assert_contains "$T/init.log" "init in $HOME/hubs/loc: --persona sre --client Acme Corp --owner owner1 --name loc" "missing answers asked, then bin/init ran"
  assert_contains "$T/out" "Site reliability" "the personas listed"
}

refusals_create_nothing() {   # AC4
  fresh; make_template; stub_gh
  for bad in Acme "a b" "a_b" ""; do
    bash "$ADE" hub new "$bad" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "bad name [$bad]"; done
  [ ! -e "$HOME/hubs" ] || fail "bad names create nothing"
  mkdir -p "$HOME/hubs/taken"; bash "$ADE" hub new taken < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "existing folder"
  assert_eq "$(ls -A "$HOME/hubs/taken")" "" "existing folder untouched"
  nogh="$(no_gh_path)"
  PATH="$nogh" bash "$ADE" hub new fresh1 < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "gh missing"
  assert_contains "$T/out" "your hub needs the GitHub CLI (gh)" "names what is missing (A18: no way around GitHub is offered)"
  [ ! -e "$HOME/hubs/fresh1" ] && [ ! -s "$GH_LOG" ] || fail "gh missing creates nothing"
  [ ! -e "$HOME/.config/ade/hub" ] || fail "no default saved by a refusal"
}

bare_ade() {   # AC5
  fresh; mkdir -p "$T/nowhere" "$T/fakebin"; local c   # fakes: never the host's claude or gh sign-in state
  for c in claude gh; do printf '#!/bin/bash\nexit 1\n' > "$T/fakebin/$c"; chmod +x "$T/fakebin/$c"; done; export PATH="$T/fakebin:$PATH"
  out=$(cd "$T/nowhere" && bash "$ADE" < /dev/null); rc=$?; assert_eq "$rc" 0 "no hub exit 0"
  echo "$out" > "$T/out"; assert_contains "$T/out" "[ ] 4. Your hub" "no hub: the guide's steps (A18)"
  assert_contains "$T/out" "run ade setup at a terminal" "and the command"
  make_hub "$T/h" h; echo "HUB_NAME=acme" > "$T/h/hub.conf"
  out=$(cd "$T/nowhere" && ADE_HUB="$T/h" bash "$ADE"); rc=$?; assert_eq "$rc" 0 "hub exit 0"
  echo "$out" > "$T/out"
  assert_contains "$T/out" "hub: acme ($T/h)" "hub name"; assert_contains "$T/out" "h sessions" "runs ade status"
  [ "$(grep -c '^  ade ' "$T/out")" = 3 ] || { cat "$T/out"; fail "three next commands"; }
}

list_and_use() {   # AC6
  fresh; make_hub "$T/one" one; make_hub "$T/two" two; mkdir -p "$T/plain"
  bash "$ADE" hub use "$T/one" > /dev/null 2>&1 || fail "use one"
  bash "$ADE" hub use "$T/two" > /dev/null 2>&1 || fail "use two"
  bash "$ADE" hub list > "$T/out" 2>&1 || fail "list exit"
  grep -E "^  +$T/one$" "$T/out" > /dev/null && grep -E "^\* +$T/two$" "$T/out" > /dev/null || { cat "$T/out"; fail "both listed, two marked"; }
  bash "$ADE" hub use "$T/plain" > "$T/out" 2>&1; assert_eq "$?" 2 "not a hub refused"
  assert_eq "$(cat "$HOME/.config/ade/hub")" "$T/two" "default unchanged by a refusal"
  rm -rf "$T/one"; bash "$ADE" hub list > "$T/out" 2>&1; assert_contains "$T/out" "$T/one (missing)" "a gone hub is marked"
}

curl_install() {   # AC7
  fresh; mkdir -p "$T/raw/main" "$T/raw/v9.9.9" "$T/raw/v1.2.3" "$T/run"; echo 9.9.9 > "$T/raw/main/VERSION"
  cp "$ADE" "$T/raw/v9.9.9/ade"; sed 's/^set -u$/set -u; echo tagged-1.2.3 >\&2/' "$ADE" > "$T/raw/v1.2.3/ade"
  local v d; export ADE_RELEASES_BASE="file://$T/gh"   # each release's release.json (A12: required from 0.2.0 on)
  for v in 9.9.9 1.2.3; do d="$T/gh/better-ade/ade-cli/releases/download/v$v"; mkdir -p "$d"
    printf '{"component": "ade-cli", "version": "%s", "files": [{"name": "ade", "sha256": "%s"}]}\n' "$v" \
      "$( (shasum -a 256 "$T/raw/v$v/ade" 2> /dev/null || sha256sum "$T/raw/v$v/ade") | cut -d' ' -f1)" > "$d/release.json"; done
  (cd "$T/run" && ADE_CLI_BASE="file://$T/raw" PATH="/usr/bin:/bin" bash -s -- "$T/prefix" < "$REPO/install.sh") > "$T/out" 2>&1 || { cat "$T/out"; fail "piped install"; }
  assert_eq "$("$T/prefix/bin/ade" version)" "ade 9.9.9" "the release named in main's VERSION"
  assert_contains "$T/out" "add $T/prefix/bin to your PATH" "missing PATH entry reported"
  (cd "$T/run" && ADE_CLI_BASE="file://$T/raw" ADE_CLI_REF=v1.2.3 bash -s -- "$T/prefix" < "$REPO/install.sh") > "$T/out" 2>&1 || { cat "$T/out"; fail "re-install"; }
  assert_eq "$("$T/prefix/bin/ade" version 2>/dev/null)" "ade 1.2.3" "re-run replaced the binary at the given tag"
  "$T/prefix/bin/ade" version 2>&1 | grep -q tagged-1.2.3 || fail "the tagged file was installed"
  (cd "$T/run" && ADE_CLI_BASE="file://$T/raw" ADE_CLI_REF=v4.0.0 bash -s -- "$T/prefix" < "$REPO/install.sh") > "$T/out" 2>&1; assert_eq "$?" 1 "a missing tag fails"
  assert_eq "$("$T/prefix/bin/ade" version 2>/dev/null)" "ade 1.2.3" "a failed download keeps the old binary"
}

# story I3: a hub to import at $T/src/<name>: bin/setup and bin/adopt log where they ran and their arguments; a clone's
# bin/adopt starts a fresh history like the real one. noadopt: a hub from before I2 (no bin/adopt)
make_src() {
  S="$T/src/$1"; mkdir -p "$S/bin"; git init -q "$S"; : > "$S/bin/lib.sh"; echo "HUB_NAME=$1" > "$S/hub.conf"
  printf '#!/bin/bash\necho "setup in $PWD HUB=$HUB" >> "%s/setup.log"\n' "$T" > "$S/bin/setup"
  if [ "${2:-}" != noadopt ]; then cat > "$S/bin/adopt" <<STUB
#!/bin/bash
echo "adopt in \$PWD HUB=\$HUB: \$*" >> "$T/adopt.log"
if [ "\$1" = --clone ]; then rm -rf .git && git init -q && git add -A && git commit -qm adopted; fi
echo; echo "Left to do by hand:"; echo "The schedule: bin/schedule install"
STUB
  fi
  chmod +x "$S"/bin/*; commit_tag "$S" src
}
stub_gh_log() {   # a fake gh that only logs "<pwd>: <args>"
  local d="$T/fakebin"; mkdir -p "$d"; export GH_LOG="$T/gh.log"; : > "$GH_LOG"
  printf '#!/bin/bash\necho "$PWD: $*" >> "$GH_LOG"\nexit 0\n' > "$d/gh"; chmod +x "$d/gh"; export PATH="$d:$PATH"
}
import_modes() {   # I3 AC1: each mode clones, runs bin/setup then bin/adopt with its flags, and makes it the default
  local h
  fresh; make_src acme; stub_gh_log; h="$HOME/hubs/acme"
  bash "$ADE" hub import "$T/src/acme" --share < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "share exit"; }
  assert_eq "$(cat "$T/setup.log")" "setup in $h HUB=$h" "bin/setup ran in the clone"
  assert_eq "$(cat "$T/adopt.log")" "adopt in $h HUB=$h: --share" "bin/adopt --share"
  assert_eq "$(cat "$HOME/.config/ade/hub")" "$h" "share: the default hub"
  assert_contains "$T/out" "Left to do by hand:" "bin/adopt's list is shown"
  assert_contains "$T/out" "default hub: ~/hubs/acme" "says it is the default"
  bash "$ADE" hub list | grep -qxF "* $h" || fail "listed as the default"
  [ ! -s "$GH_LOG" ] || fail "share makes no GitHub call"
  assert_eq "$(git -C "$h" remote get-url origin)" "$T/src/acme" "a share keeps its origin"

  fresh; make_src acme; stub_gh_log; mkdir -p "$T/else"; h="$T/else/mine"
  bash "$ADE" hub import "$T/src/acme" --handover --owner "Ana Lee" --name mine --dir "$T/else" < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "handover exit"; }
  assert_eq "$(cat "$T/adopt.log")" "adopt in $h HUB=$h: --handover --owner Ana Lee" "bin/adopt --handover --owner (one argument)"
  assert_eq "$(cat "$HOME/.config/ade/hub")" "$h" "handover: the default hub in --dir as --name"
  bash "$ADE" hub import "$T/src/acme" --handover --owner Bo --from none --name mine2 --dir "$T/else" < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "handover --from"; }
  assert_contains "$T/adopt.log" ": --handover --owner Bo --from none" "--from reaches bin/adopt"

  fresh; make_src acme; stub_gh_log; h="$HOME/hubs/mycopy"
  printf 'Ana\n' | bash "$ADE" hub import "$T/src/acme" --clone --name mycopy --no-github > "$T/out" 2>&1 || { cat "$T/out"; fail "clone exit"; }
  assert_eq "$(cat "$T/adopt.log")" "adopt in $h HUB=$h: --clone --owner Ana --name mycopy" "bin/adopt --clone, the owner asked"
  assert_eq "$(cat "$HOME/.config/ade/hub")" "$h" "clone: the default hub"
  [ -f "$T/setup.log" ] || fail "clone: bin/setup ran"
}
import_ask_and_refusals() {   # I3 AC2: no mode and no terminal: exit 2, nothing cloned; a folder that exists: refused
  fresh; make_src acme; stub_gh_log
  bash "$ADE" hub import "$T/src/acme" < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "no mode, no terminal"
  assert_contains "$T/out" "--share, --handover or --clone" "names the flags"
  [ ! -e "$HOME/hubs" ] && [ ! -e "$HOME/.config/ade/hub" ] || fail "nothing cloned, no default"
  for a in "--share --clone" "--share --owner x" "--share --name Bad" "--share --name" "--bogus" ""; do
    # shellcheck disable=SC2086
    bash "$ADE" hub import "$T/src/acme" $a < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "refused: [$a]"; done
  bash "$ADE" hub import < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "no source"
  [ ! -e "$HOME/hubs" ] || fail "refusals clone nothing"
  mkdir -p "$HOME/hubs/acme"; echo keep > "$HOME/hubs/acme/f"
  bash "$ADE" hub import "$T/src/acme" --share < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "an existing folder"
  assert_eq "$(ls -A "$HOME/hubs/acme")" "f" "the existing folder is untouched"; [ ! -e "$T/adopt.log" ] || fail "nothing run"
  rm -rf "$HOME/hubs/acme"   # at a terminal, the mode is asked
  pty_run 'share\n' bash "$ADE" hub import "$T/src/acme" > "$T/out" 2>&1 || { cat "$T/out"; fail "asked at a terminal"; }
  assert_contains "$T/out" "handover" "the modes are listed"; assert_contains "$T/adopt.log" ": --share" "the answer is the mode"
}
import_github() {   # I3 AC3: a clone gets its own private repo (gh repo create, pushed) unless --no-github
  local h; fresh; make_src acme; stub_gh_log; h="$HOME/hubs/copy2"
  bash "$ADE" hub import "$T/src/acme" --clone --owner Ana --name copy2 < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "clone with github"; }
  assert_contains "$GH_LOG" "$h: repo create copy2 --private --source . --remote origin --push" "gh repo create, private, pushed"
  assert_eq "$(cat "$HOME/.config/ade/hub")" "$h" "the default hub"
  fresh; make_src acme; stub_gh_log
  bash "$ADE" hub import "$T/src/acme" --clone --owner Ana --name copy3 --no-github < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "no-github"; }
  [ ! -s "$GH_LOG" ] || fail "--no-github: no gh call"
}
import_old_or_not_hub() {   # I3 AC4: a hub without bin/adopt (older than I2) is refused and its clone removed
  fresh; make_src old noadopt; stub_gh_log
  bash "$ADE" hub import "$T/src/old" --share < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "old hub refused"
  assert_contains "$T/out" "update that hub first" "the reason"
  [ ! -e "$HOME/hubs/old" ] || fail "the clone is removed"; [ ! -e "$T/setup.log" ] || fail "nothing run in it"
  [ ! -e "$HOME/.config/ade/hub" ] || fail "no default"
  mkdir -p "$T/src/plain"; git init -q "$T/src/plain"; echo x > "$T/src/plain/x"; commit_tag "$T/src/plain" x
  bash "$ADE" hub import "$T/src/plain" --share < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "not a hub"
  [ ! -e "$HOME/hubs/plain" ] || fail "a non-hub clone is removed"
  make_src acme; printf '#!/bin/bash\necho refused >&2; exit 2\n' > "$T/src/acme/bin/adopt"   # a bin/adopt that refuses
  commit_tag "$T/src/acme" adopt-fails
  bash "$ADE" hub import "$T/src/acme" --share < /dev/null > "$T/out" 2>&1; assert_eq "$?" 1 "bin/adopt failing fails the import"
  assert_contains "$T/out" "the clone is removed" "says so"; [ ! -e "$HOME/hubs/acme" ] || fail "a clone whose bin/adopt failed is removed"
  [ ! -e "$HOME/.config/ade/hub" ] || fail "no default after a failure"
  mkdir -p "$HOME/.agent-hub/taken"
  bash "$ADE" hub import "$T/src/acme" --clone --owner A --name taken --no-github < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "a clone name this machine has"
  [ ! -e "$HOME/hubs/taken" ] || fail "refused before the clone"
  bash "$ADE" hub import "$T/src/acme" --share --from none < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "--from only with --handover"
  bash "$ADE" hub import "$T/src/none" --share < /dev/null > "$T/out" 2>&1; assert_eq "$?" 1 "a clone that fails"
  [ ! -e "$HOME/hubs/none" ] || fail "nothing left"
}
import_documented() {   # I3 AC5
  fresh; bash "$ADE" hub > "$T/out" 2>&1; assert_contains "$T/out" "ade hub import" "usage lists import"
  bash "$ADE" help > "$T/out" 2>&1; assert_contains "$T/out" "ade hub import" "help lists import"
  assert_contains "$REPO/README.md" "ade hub import" "README"; assert_contains "$REPO/CHANGELOG.md" "ade hub import" "CHANGELOG"
}

ALL="new_with_github public_and_dir no_github refusals_create_nothing bare_ade list_and_use curl_install import_modes import_ask_and_refusals import_github import_old_or_not_hub import_documented"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
