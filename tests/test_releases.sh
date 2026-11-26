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

U="" # the update cache, once fresh has made HOME
settle() {   # the detached fetch (and an auto-install) has finished
  local i; U="$HOME/.config/ade/updates"
  for i in $(seq 1 150); do [ -d "$U/fetching" ] || [ -d "$U/installing" ] || return 0; sleep 0.1; done; fail "the background job did not finish"
}
cmd() { "$A" hub list > /dev/null 2> "$1"; }   # one ordinary command, its banner lines in $1
quiet() { [ -z "$(grep -v '^ade: test mode ' "$1")" ]; }   # nothing in $1 but ade's test-mode line (A16)

once_a_day_once_per_version() {   # AC2: the first command starts the day's fetch, the next ones read the cache
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1; publish 1.3.0
  cmd "$T/err1"; settle; cmd "$T/err2"; cmd "$T/err3"
  assert_contains "$T/err2" "ade-cli 1.3.0 is out (you have 1.2.3): run ade update" "a banner from the cache (one line, A18)"
  assert_not_contains "$T/err3" "is out" "once per new version"; assert_eq "$(manifest_requests)" 1 "at most once a day"
  echo $(( $(date +%s) - 90000 )) > "$U/checked"; cmd "$T/err4"; settle
  assert_eq "$(manifest_requests)" 2 "again the next day"; cmd "$T/err5"; assert_not_contains "$T/err5" "is out" "still once per version"
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1; publish 1.2.3; cmd "$T/e"; settle; cmd "$T/err"; assert_not_contains "$T/err" "is out" "never the installed one"
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1; publish 1.0.0; cmd "$T/e"; settle; cmd "$T/err"; assert_not_contains "$T/err" "is out" "never an older one"
}

security_every_command() {   # AC3
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1; publish 1.3.0 security; cmd "$T/e"; settle
  for i in 1 2 3; do cmd "$T/err"; assert_contains "$T/err" "[security update]" "banner $i"; done
}

badge_and_telegram() {   # AC4
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1; publish 1.3.0
  H="$T/hub"; make_hub "$H" hub; printf 'HUB_NAME=acme\nHUB_CHANNELS=telegram\n' > "$H/hub.conf"; export ADE_HUB="$H"
  printf '#!/bin/bash\necho "chat $*" >> "$FAKE_LOG"\n' > "$H/bin/chat"; chmod +x "$H/bin/chat"
  printf '#!/bin/bash\n[ "$1" = -L ] && shift 2\nexit 0\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
  cmd "$T/e"; settle; cmd "$T/e"; cmd "$T/e"
  assert_eq "$(grep -c '^chat send' "$FAKE_LOG")" 1 "one Telegram line per new version"
  assert_contains "$FAKE_LOG" "chat send ade-cli 1.3.0 is out" "names it"
  "$A" ui --bar "$("$A" ui --session)" > "$T/out" 2>&1; assert_contains "$T/out" "⬆ 1 update" "the tab bar badge"
  printf 'HUB_NAME=acme\n' > "$H/hub.conf"; : > "$FAKE_LOG"; publish 1.4.0; rm -f "$U/checked"
  cmd "$T/e"; settle; cmd "$T/e"; assert_not_contains "$FAKE_LOG" "chat send" "no channel, no Telegram line"
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

manifest_fail_closed() {   # item 9: from MANIFEST_SINCE on, a missing, unreadable or invalid manifest installs nothing
  local m bad
  for bad in missing 'not json' '[1]' '{"component": "ade-cli", "version": "1.2.4", "files": []}' \
    '{"component": "ade-cli", "version": "1.2.4", "files": [{"name": "ade", "sha256": "abc"}]}'; do
    fresh; rel_fixture; export ADE_NO_UPDATE_CHECK=1; publish 1.2.4; m="$T/gh/better-ade/ade-cli/releases/download/v1.2.4/release.json"
    if [ "$bad" = missing ]; then rm "$m"; else printf '%s\n' "$bad" > "$m"; fi
    { echo '#!/bin/bash'; echo 'TAMPERED=1'; tail -n +2 "$REPO/ade"; } > "$T/raw/v1.2.4/ade"
    "$A" update > "$T/out" 2>&1; assert_eq "$?" 1 "$bad: refused"
    assert_contains "$T/out" "nothing installed" "$bad: says so"; assert_eq "$("$A" version)" "ade 1.2.3" "$bad: the old one stays"
    case "$bad" in missing) assert_contains "$T/out" "there is no release.json for ade 1.2.4" "the reason" ;; *) assert_contains "$T/out" "release.json is not valid" "the reason" ;; esac
    (cd "$T" && ADE_CLI_REF=v1.2.4 bash -s -- "$T/p4" < "$REPO/install.sh") > "$T/out" 2>&1 && fail "$bad: the installer refuses"
    assert_contains "$T/out" "nothing installed" "$bad: installer says so"; [ ! -e "$T/p4/bin/ade" ] || fail "$bad: the installer installed it"
  done
}

manifest_bound() {   # item 10: the manifest of exactly this version and component; its url ignored; never a downgrade
  local d
  fresh; rel_fixture; export ADE_NO_UPDATE_CHECK=1; publish 1.2.4; d="$T/gh/better-ade/ade-cli/releases/download/v1.2.4"
  mkdir -p "$T/raw/v0.0.1"; { echo '#!/bin/bash'; echo 'OLD_VULNERABLE_BUILD=1'; tail -n +2 "$REPO/ade"; } > "$T/raw/v0.0.1/ade"
  old_sha="$( (shasum -a 256 "$T/raw/v0.0.1/ade" 2> /dev/null || sha256sum "$T/raw/v0.0.1/ade") | cut -d' ' -f1)"
  python3 - "$d/release.json" "$old_sha" "file://$T/raw/v0.0.1/ade" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["version"] = "9.9.9"; d["files"][0]["sha256"] = sys.argv[2]; d["files"][0]["url"] = sys.argv[3]; json.dump(d, open(p, "w"))
PY
  "$A" update > "$T/out" 2>&1; assert_eq "$?" 1 "a manifest of another version is refused"
  assert_contains "$T/out" "another version than 1.2.4" "the reason"; assert_eq "$("$A" version)" "ade 1.2.3" "unchanged"
  assert_eq "$(grep -c OLD_VULNERABLE_BUILD "$A")" 0 "the old build never installed"
  publish 1.2.4; python3 - "$d/release.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["component"] = "ade-brain"; json.dump(d, open(p, "w"))
PY
  "$A" update > "$T/out" 2>&1; assert_eq "$?" 1 "another component's manifest is refused"; assert_contains "$T/out" "not the manifest of ade-cli" "says so"
  publish 1.2.4; python3 - "$d/release.json" "file://$T/raw/v0.0.1/ade" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["files"][0]["url"] = sys.argv[2]; json.dump(d, open(p, "w"))
PY
  "$A" update > "$T/out" 2>&1 || { cat "$T/out"; fail "a manifest url is ignored (the tag's file installs)"; }
  assert_eq "$("$A" version)" "ade 1.2.4" "the tagged file"; assert_eq "$(grep -c OLD_VULNERABLE_BUILD "$A")" 0 "never the url's file"
  assert_not_contains "$FAKE_LOG" "v0.0.1" "the url is never fetched"
  echo 1.0.0 > "$T/raw/main/VERSION"; "$A" update > "$T/out" 2>&1
  assert_contains "$T/out" "1.0.0 is older than the installed 1.2.4; refused" "never a downgrade"; assert_eq "$("$A" version)" "ade 1.2.4" "kept"
}

offline_never_blocks() {   # AC6
  fresh; rel_fixture; export ADE_RELEASES_BASE="file://$T/nowhere"
  cmd "$T/err" || fail "a missing manifest never fails a command"; settle
  quiet "$T/err" || { cat "$T/err"; fail "quiet"; }
  [ -s "$U/checked" ] || fail "retried tomorrow (stamp written)"
  cmd "$T/err"; assert_eq "$(grep -c 'release.json' "$FAKE_LOG")" 1 "not again today"
  fresh; rel_fixture; d="$T/gh/better-ade/ade-cli/releases/latest/download"; mkdir -p "$d"; echo "{not json" > "$d/release.json"
  cmd "$T/e"; settle; cmd "$T/err" || fail "malformed"; quiet "$T/err" || fail "a malformed manifest is ignored"
  echo '{"component": "ade-cli", "version": "x"}' > "$d/release.json"; rm -f "$U/checked"
  cmd "$T/e"; settle; cmd "$T/err" || fail "bad version"; quiet "$T/err" || fail "a bad version is ignored"
  printf '{"component": "ade-cli", "version": "1.3.0", "summary": "hi \\u001b]0;pwned\\u0007 \\u001b[31mred"}\n' > "$d/release.json"; rm -f "$U/checked"
  export ADE_NO_AUTO_UPDATE=1; cmd "$T/e"; settle; cmd "$T/err"; assert_contains "$T/err" "ade-cli 1.3.0 is out" "the banner"
  ! grep -q "$(printf '\033')" "$T/err" || fail "no escape sequence from a manifest reaches the terminal"
}

never_delays_a_command() {   # item 12: a stalled network, every component in use: the command does not wait
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1
  H="$T/hub"; make_hub "$H" hub; echo 1.0.0 > "$H/VERSION"; git init -q "$H"; mkdir -p "$H/.ade/agents"; echo v2.0.0 > "$H/.ade/method-version"; export ADE_HUB="$H"
  mkdir -p "$HOME/.claude/plugins"; echo '{"version": 2, "plugins": {"git@ade-skills": [{}]}}' > "$HOME/.claude/plugins/installed_plugins.json"
  # a curl that stalls (and ignores --max-time), as a blackholed network
  printf '#!/bin/bash\nfor a in "$@"; do case "$a" in *release.json) echo "curl $a" >> "$FAKE_LOG"; echo $$ >> "%s/stalled"; exec sleep 30 ;; esac; done\nexit 7\n' "$T" > "$T/fakebin/curl"
  cd "$H" || fail "cd"; s="$(python3 -c 'import time; print(time.time())')"; "$A" hub list > /dev/null 2>&1; e="$(python3 -c 'import time; print(time.time())')"
  python3 -c "import sys; sys.exit(0 if $e - $s < 1.5 else 1)" || fail "the command waited for the network ($s .. $e)"
  sleep 3.5; assert_eq "$(grep -c 'latest/download/release.json' "$FAKE_LOG")" 5 "every component in use asked"
  while read -r p; do kill -0 "$p" 2> /dev/null && fail "a request outlived the 2-second budget"; done < "$T/stalled"
  [ ! -d "$HOME/.config/ade/updates/fetching" ] || fail "the job ended"
}

no_check_no_request() {   # AC7
  fresh; rel_fixture; publish 1.3.0; export ADE_NO_UPDATE_CHECK=1
  cmd "$T/e"; sleep 0.3; assert_not_contains "$FAKE_LOG" "release.json" "no request"
}

auto_update_policy() {   # AC8 + item 12: from a terminal, in a detached job, then one report; never in an agent session
  fresh; rel_fixture; publish 1.2.4; cmd "$T/e"; settle
  pty_run '' "$A" hub list > "$T/out" 2>&1; settle; assert_contains "$T/out" "installing it in the background" "a patch installs itself"
  assert_eq "$("$A" version)" "ade 1.2.4" "installed"
  pty_run '' "$A" hub list > "$T/out" 2>&1; assert_eq "$(grep -c 'auto-update: ade 1.2.3 -> 1.2.4' "$T/out")" 1 "then one line"
  fresh; rel_fixture; publish 1.3.0; cmd "$T/e"; settle; pty_run '' "$A" hub list > /dev/null 2>&1; settle; assert_eq "$("$A" version)" "ade 1.3.0" "a minor installs itself"
  fresh; rel_fixture; publish 2.0.0; cmd "$T/e"; settle; pty_run '' "$A" hub list > "$T/out" 2>&1; settle
  assert_eq "$("$A" version)" "ade 1.2.3" "a major asks first"; assert_contains "$T/out" "run ade update" "says how"
  fresh; rel_fixture; publish 1.3.0 normal 1.2.9; cmd "$T/e"; settle; pty_run '' "$A" hub list > /dev/null 2>&1; settle
  assert_eq "$("$A" version)" "ade 1.2.3" "a min_supported jump asks first"
  fresh; rel_fixture; publish 1.2.4 security; cmd "$T/e"; settle; pty_run '' "$A" hub list > /dev/null 2>&1; settle; assert_eq "$("$A" version)" "ade 1.2.4" "security installs"
  fresh; rel_fixture; export ADE_NO_AUTO_UPDATE=1; publish 1.2.4; cmd "$T/e"; settle; pty_run '' "$A" hub list > "$T/out" 2>&1; settle
  assert_eq "$("$A" version)" "ade 1.2.3" "ADE_NO_AUTO_UPDATE=1 only notifies"; assert_contains "$T/out" "is out" "notified"
  # not from a terminal, not in an agent session, not when switched off
  fresh; rel_fixture; publish 1.2.4; cmd "$T/e"; settle; cmd "$T/err"; settle; assert_eq "$("$A" version)" "ade 1.2.3" "no terminal: no install"
  CLAUDECODE=1 pty_run '' "$A" hub list > /dev/null 2>&1; settle; assert_eq "$("$A" version)" "ade 1.2.3" "an agent session: no install"
  "$A" update --auto off > "$T/out" 2>&1 || fail "--auto off"; assert_eq "$(cat "$HOME/.config/ade/auto-update")" off "stored in ~/.config/ade"
  pty_run '' "$A" hub list > /dev/null 2>&1; settle; assert_eq "$("$A" version)" "ade 1.2.3" "switched off: no install"
  "$A" update --auto on > /dev/null 2>&1; pty_run '' "$A" hub list > /dev/null 2>&1; settle; assert_eq "$("$A" version)" "ade 1.2.4" "switched on again"
  "$A" update --auto maybe > /dev/null 2>&1; assert_eq "$?" 2 "--auto takes on or off"
}

auto_update_failure_says_why() {   # item 9: an auto-install that cannot be verified installs nothing and shows the whole reason
  fresh; rel_fixture; publish 1.2.4; rm "$T/gh/better-ade/ade-cli/releases/download/v1.2.4/release.json"
  { echo '#!/bin/bash'; echo 'TAMPERED=1'; tail -n +2 "$REPO/ade"; } > "$T/raw/v1.2.4/ade"
  cmd "$T/e"; settle; pty_run '' "$A" hub list > /dev/null 2>&1; settle; pty_run '' "$A" hub list > "$T/out" 2>&1
  assert_eq "$("$A" version)" "ade 1.2.3" "nothing installed"; assert_eq "$(grep -c '^TAMPERED=1' "$A")" 0 "never the tampered file"
  assert_contains "$T/out" "the auto-update failed: there is no release.json for ade 1.2.4" "the reason, whole"
  assert_contains "$T/out" "nothing installed" "and what it means"
}

release_workflow_passes_assets() {   # item 11: the shared release workflow attaches and hashes ade
  grep -Eq '^ +with: \{.*assets: ade[ ,}]' "$REPO/.github/workflows/release.yml" || fail "release.yml passes assets: ade"
}

ci_real_tools() {   # story C1 AC8: the suite installs the real tools its tests would skip without; both e2e jobs run hub_commands
  local ci="$REPO/.github/workflows/ci.yml"
  job() { awk -v j="  $1:" '$0==j{p=1;next} p&&/^  [a-z]/{p=0} p' "$ci"; }   # the lines of one job
  job suite | grep -Eq 'Darwin.*brew install.*(tmux.*poppler|poppler.*tmux)' || fail "suite installs tmux and poppler on macOS"
  job suite | grep -Eq 'Linux.*apt-get install.*poppler-utils' || fail "suite installs poppler-utils on Linux"
  job e2e-linux | grep -Eq 'run: (/bin/)?bash tests/e2e/hub_commands\.sh$' || fail "e2e-linux runs hub_commands.sh"
  job e2e-macos | grep -Eq 'run: (/bin/)?bash tests/e2e/hub_commands\.sh$' || fail "e2e-macos runs hub_commands.sh"
  [ -f "$REPO/tests/e2e/hub_commands.sh" ] || fail "tests/e2e/hub_commands.sh exists"
}

ALL="once_a_day_once_per_version security_every_command badge_and_telegram sha_mismatch_refused manifest_fail_closed manifest_bound
  offline_never_blocks never_delays_a_command no_check_no_request auto_update_policy auto_update_failure_says_why release_workflow_passes_assets ci_real_tools"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
