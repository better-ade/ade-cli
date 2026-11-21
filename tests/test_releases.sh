#!/bin/bash
# story A12: release manifests, update notifications and auto-update. A fake release folder (file:// URLs), a curl
# wrapper that logs every request; never the network.
. "$(dirname "$0")/helpers.sh"

rel_fixture() {   # ade 1.2.3 installed at $T/prefix; publish puts releases in $T/raw (files) and $T/gh (release.json)
  unset ADE_NO_UPDATE_CHECK ADE_NO_AUTO_UPDATE
  export ADE_TEST_ALLOW_FILE_URLS=1 ADE_RELEASES_BASE="file://$T/gh" ADE_CLI_BASE="file://$T/raw" FAKE_LOG="$T/fake.log"; : > "$FAKE_LOG"
  mkdir -p "$T/fakebin" "$T/src" "$T/raw/main"; local real; real="$(command -v curl)"
  printf '#!/bin/bash\nfor a in "$@"; do case "$a" in *://*) echo "curl $a" >> "$FAKE_LOG" ;; esac; done\nexec "%s" "$@"\n' "$real" > "$T/fakebin/curl"
  chmod +x "$T/fakebin/curl"; export PATH="$T/fakebin:$PATH"
  cp "$REPO/ade" "$REPO/install.sh" "$T/src/"; echo 1.2.3 > "$T/src/VERSION"; bash "$T/src/install.sh" "$T/prefix" > /dev/null
  A="$T/prefix/bin/ade"
}
publish() {   # <version> [urgency] [min_supported] [good|bad sha]
  local v="$1" d="$T/gh/better-ade/ade-cli/releases" sha
  mkdir -p "$T/raw/v$v" "$d/latest/download" "$d/download/v$v"; echo "$v" > "$T/raw/main/VERSION"; cp "$REPO/ade" "$T/raw/v$v/ade"
  sha="$( (shasum -a 256 "$T/raw/v$v/ade" 2> /dev/null || sha256sum "$T/raw/v$v/ade") | cut -d' ' -f1)"; [ "${4:-good}" = bad ] && sha="$(printf '%064d' 0)"
  python3 - "$d/download/v$v/release.json" "$v" "${2:-normal}" "${3:-}" "$sha" "file://$T/raw/v$v/ade" <<'PY'
import json, sys
p, v, urg, mins, sha, url = sys.argv[1:7]
json.dump({"component": "ade-cli", "version": v, "released": "2026-11-22T00:00:00Z", "notes_url": "x", "summary": "the %s notes" % v,
           "urgency": urg, "min_supported": mins or None, "files": [{"name": "ade", "url": url, "sha256": sha}]}, open(p, "w"))
PY
  cp "$d/download/v$v/release.json" "$d/latest/download/release.json"
}
manifest_requests() { grep -c "latest/download/release.json" "$FAKE_LOG"; }

once_a_day_once_per_version() {   # AC2
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1; publish 1.3.0
  "$A" hub list > /dev/null 2> "$T/err1"; "$A" hub list > /dev/null 2> "$T/err2"
  assert_contains "$T/err1" "ade-cli 1.3.0 is out (you have 1.2.3): the 1.3.0 notes" "a banner" || cat "$T/err1"
  assert_not_contains "$T/err2" "is out" "once per new version"; assert_eq "$(manifest_requests)" 1 "at most once a day"
  echo $(( $(date +%s) - 90000 )) > "$HOME/.config/ade/updates/ade-cli.checked"; "$A" hub list > /dev/null 2> "$T/err3"
  assert_eq "$(manifest_requests)" 2 "again the next day"; assert_not_contains "$T/err3" "is out" "still once per version"
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1; publish 1.2.3; "$A" hub list > /dev/null 2> "$T/err"; assert_not_contains "$T/err" "is out" "never the installed one"
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1; publish 1.0.0; "$A" hub list > /dev/null 2> "$T/err"; assert_not_contains "$T/err" "is out" "never an older one"
}

security_every_command() {   # AC3
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1; publish 1.3.0 security
  for i in 1 2 3; do "$A" hub list > /dev/null 2> "$T/err"; assert_contains "$T/err" "[security update]" "banner $i"; done
}

badge_and_telegram() {   # AC4
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1; publish 1.3.0
  H="$T/hub"; make_hub "$H" hub; printf 'HUB_NAME=acme\nHUB_CHANNELS=telegram\n' > "$H/hub.conf"; export ADE_HUB="$H"
  printf '#!/bin/bash\necho "chat $*" >> "$FAKE_LOG"\n' > "$H/bin/chat"; chmod +x "$H/bin/chat"
  printf '#!/bin/bash\n[ "$1" = -L ] && shift 2\nexit 0\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
  "$A" hub list > /dev/null 2>&1; "$A" hub list > /dev/null 2>&1
  assert_eq "$(grep -c '^chat send' "$FAKE_LOG")" 1 "one Telegram line per new version"
  assert_contains "$FAKE_LOG" "chat send ade-cli 1.3.0 is out" "names it"
  "$A" ui --bar "$("$A" ui --session)" > "$T/out" 2>&1; assert_contains "$T/out" "⬆ 1 update" "the tab bar badge"
  printf 'HUB_NAME=acme\n' > "$H/hub.conf"; : > "$FAKE_LOG"; publish 1.4.0; rm -f "$HOME/.config/ade/updates/ade-cli.checked"
  "$A" hub list > /dev/null 2>&1; assert_not_contains "$FAKE_LOG" "chat send" "no channel, no Telegram line"
}

sha_mismatch_refused() {   # AC5: ade update and the installer
  fresh; rel_fixture; export ADE_NO_UPDATE_CHECK=1; publish 1.3.0 normal "" bad
  "$A" update > "$T/out" 2>&1; assert_eq "$?" 1 "a mismatch is an error"
  assert_contains "$T/out" "does not match its sha256" "says why"; assert_eq "$("$A" version)" "ade 1.2.3" "the old version stays"
  (cd "$T" && bash -s -- "$T/p2" < "$REPO/install.sh") > "$T/out" 2>&1 && fail "the installer refuses a mismatch"
  assert_contains "$T/out" "does not match its sha256" "installer says why"; [ ! -e "$T/p2/bin/ade" ] || fail "nothing installed"
  (cd "$T" && bash -s -- "$T/prefix" < "$REPO/install.sh") > /dev/null 2>&1; assert_eq "$("$A" version)" "ade 1.2.3" "a re-install keeps the old one"
  publish 1.3.0; "$A" update > "$T/out" 2>&1 || { cat "$T/out"; fail "a match installs"; }; assert_eq "$("$A" version)" "ade 1.3.0" "verified update"
  (cd "$T" && bash -s -- "$T/p3" < "$REPO/install.sh") > /dev/null 2>&1 || fail "the installer installs a match"
  assert_eq "$("$T/p3/bin/ade" version)" "ade 1.3.0" "installed"
}

offline_never_blocks() {   # AC6
  fresh; rel_fixture; export ADE_RELEASES_BASE="file://$T/nowhere"; s=$(date +%s)
  "$A" hub list > /dev/null 2> "$T/err" || fail "a missing manifest never fails a command"
  [ $(( $(date +%s) - s )) -le 3 ] || fail "and never slows it"; [ ! -s "$T/err" ] || { cat "$T/err"; fail "quiet"; }
  [ -s "$HOME/.config/ade/updates/ade-cli.checked" ] || fail "retried tomorrow (stamp written)"
  "$A" hub list > /dev/null 2>&1; assert_eq "$(grep -c 'release.json' "$FAKE_LOG")" 1 "not again today"
  fresh; rel_fixture; d="$T/gh/better-ade/ade-cli/releases/latest/download"; mkdir -p "$d"; echo "{not json" > "$d/release.json"
  "$A" hub list > /dev/null 2> "$T/err" || fail "malformed"; [ ! -s "$T/err" ] || fail "a malformed manifest is ignored"
  echo '{"version": "x"}' > "$d/release.json"; rm -f "$HOME/.config/ade/updates/ade-cli.checked"
  "$A" hub list > /dev/null 2> "$T/err" || fail "bad version"; [ ! -s "$T/err" ] || fail "a bad version is ignored"
}

no_check_no_request() {   # AC7
  fresh; rel_fixture; publish 1.3.0; export ADE_NO_UPDATE_CHECK=1
  "$A" hub list > /dev/null 2>&1; assert_not_contains "$FAKE_LOG" "release.json" "no request"
}

auto_update_policy() {   # AC8 (and A11's daily check)
  fresh; rel_fixture; publish 1.2.4; "$A" hub list > /dev/null 2> "$T/err"
  assert_eq "$("$A" version)" "ade 1.2.4" "a patch installs itself"; assert_eq "$(grep -c 'auto-updated' "$T/err")" 1 "then one line"
  fresh; rel_fixture; publish 1.3.0; "$A" hub list > /dev/null 2>&1; assert_eq "$("$A" version)" "ade 1.3.0" "a minor installs itself"
  fresh; rel_fixture; publish 2.0.0; "$A" hub list > /dev/null 2> "$T/err"
  assert_eq "$("$A" version)" "ade 1.2.3" "a major asks first"; assert_contains "$T/err" "run ade update" "says how"
  fresh; rel_fixture; publish 1.3.0 normal 1.2.9; "$A" hub list > /dev/null 2> "$T/err"
  assert_eq "$("$A" version)" "ade 1.2.3" "a min_supported jump asks first"
  fresh; rel_fixture; publish 1.2.4 security; "$A" hub list > /dev/null 2>&1; assert_eq "$("$A" version)" "ade 1.2.4" "security installs at once"
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1; publish 1.2.4; "$A" hub list > /dev/null 2> "$T/err"
  assert_eq "$("$A" version)" "ade 1.2.3" "ADE_NO_AUTO_UPDATE=1 only notifies"; assert_contains "$T/err" "is out" "notified"
}

ALL="once_a_day_once_per_version security_every_command badge_and_telegram sha_mismatch_refused offline_never_blocks no_check_no_request auto_update_policy"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
