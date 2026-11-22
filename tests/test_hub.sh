#!/bin/bash
# story A3: `ade hub new|list|use`, `ade` alone, and the curl install. Fake gh, local template repo, fake bin/init.
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
  assert_contains "$T/out" "--no-github" "names the way out"
  [ ! -e "$HOME/hubs/fresh1" ] && [ ! -s "$GH_LOG" ] || fail "gh missing creates nothing"
  [ ! -e "$HOME/.config/ade/hub" ] || fail "no default saved by a refusal"
}

bare_ade() {   # AC5
  fresh; mkdir -p "$T/nowhere"
  out=$(cd "$T/nowhere" && bash "$ADE"); rc=$?; assert_eq "$rc" 0 "no hub exit 0"
  assert_eq "$out" 'no hub yet: run `ade hub new <name>`' "no-hub hint"
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

ALL="new_with_github public_and_dir no_github refusals_create_nothing bare_ade list_and_use curl_install"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
