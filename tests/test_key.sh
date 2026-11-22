#!/bin/bash
# story A13: `ade key`, through ade-secrets. A fake ade-secrets first on PATH records each call (its arguments, whether
# stdin and stdout are the terminal, and anything piped to it); FAKE_RC is its exit code. Never the real ade-secrets,
# Keychain, pass, age or a clipboard tool; the values here are obvious fakes.
. "$(dirname "$0")/helpers.sh"

# SESSION_VARS (tests/helpers.sh): ade's own list of Claude Code's session markers
key_fixture() {
  # shellcheck disable=SC2086
  unset $SESSION_VARS ADE_SECRETS_STORE ADE_SECRETS_REF HUB_SECRETS FAKE_RC FAKE_STORE_RC
  F="$T/fakebin"; mkdir -p "$F"; export SEC_LOG="$T/secrets.log"; : > "$SEC_LOG"
  cat > "$F/ade-secrets" <<'FAKE'
#!/bin/bash
# fake ade-secrets: one line per call; a piped stdin is read and recorded (ade must never pipe anything to it)
in=tty; [ -t 0 ] || in="pipe:$(cat)"; out=tty; [ -t 1 ] || out=pipe
{ printf 'call'; printf ' [%s]' "$@"; printf ' stdin=%s stdout=%s store=%s\n' "$in" "$out" "${ADE_SECRETS_STORE:-}"; } >> "$SEC_LOG"
echo "$0" >> "$SEC_LOG.self"
case "${1:-}" in
  version) echo "${FAKE_VERSION:-0.3.0}"; exit 0 ;;
  store) mkdir -p "${ADE_SECRETS_HOME:-$HOME/.ade-secrets}"   # as the real one: its store command makes the folder
    [ "${FAKE_STORE_RC:-0}" = 0 ] && echo "store: ${FAKE_STORE:-keychain} (recorded)"; exit "${FAKE_STORE_RC:-0}" ;;
esac
echo "FAKE-SECRETS-OUT $1"; echo "FAKE-SECRETS-ERR $1" >&2
exit "${FAKE_RC:-0}"
FAKE
  printf '#!/bin/bash\nif [ $# -eq 0 ] || [ "$1" = -s ]; then echo "${FAKE_OS:-Darwin}"; else exec "%s" "$@"; fi\n' "$(command -v uname)" > "$F/uname"
  # clipboard tools: ade itself must never touch the clipboard (ade-secrets does, and it is a fake here)
  for c in pbcopy pbpaste osascript xclip xsel wl-copy wl-paste; do printf '#!/bin/bash\necho "%s $*" >> "$CLIP_LOG"\nexit 0\n' "$c" > "$F/$c"; chmod +x "$F/$c"; done
  export CLIP_LOG="$T/clip.log"
  chmod +x "$F/ade-secrets" "$F/uname"; export PATH="$F:$PATH"
}
no_clipboard() { [ ! -s "$CLIP_LOG" ] || { cat "$CLIP_LOG"; fail "ade itself used a clipboard tool"; }; }
calls() { grep -c '^call' "$SEC_LOG"; }
K() { local i="$1"; shift; pty_run "$i" bash "$ADE" key "$@"; }   # ade key on a terminal, answers typed ahead

key_delegates() {   # AC1
  fresh; key_fixture
  K "" list > "$T/out" 2>&1 || { cat "$T/out"; fail "list"; }
  assert_contains "$SEC_LOG" "call [list] stdin=tty stdout=tty" "list runs ade-secrets list on the terminal"
  assert_contains "$T/out" "FAKE-SECRETS-OUT list" "its output reaches the terminal, not ade"
  assert_contains "$T/out" "FAKE-SECRETS-ERR list" "its messages too"
  K "" status > /dev/null 2>&1; assert_contains "$SEC_LOG" "call [status] stdin=tty stdout=tty" "status"
  K "" set api.key_1-x > /dev/null 2>&1; assert_contains "$SEC_LOG" "call [set] [api.key_1-x] stdin=tty stdout=tty" "set, the name as one argument"
  K "" set api.key_1-x --clipboard > /dev/null 2>&1; assert_contains "$SEC_LOG" "call [set] [api.key_1-x] [--clipboard] stdin=tty" "set --clipboard"
  K "" copy api.key_1-x > /dev/null 2>&1; assert_contains "$SEC_LOG" "call [copy] [api.key_1-x] stdin=tty stdout=tty" "copy"
  K "" copy api.key_1-x --for 30 > /dev/null 2>&1; assert_contains "$SEC_LOG" "call [copy] [api.key_1-x] [--for] [30] stdin=tty" "copy --for"
  K "" forget api.key_1-x > /dev/null 2>&1; assert_contains "$SEC_LOG" "call [forget] [api.key_1-x] stdin=tty stdout=tty" "forget"
  assert_not_contains "$SEC_LOG" "stdin=pipe" "nothing is ever piped to ade-secrets"
  assert_not_contains "$SEC_LOG" "call [get]" "ade never asks for a value"
  local n; n="$(calls)"
  for a in "set -rf" "copy --for" "forget -x" "set a b" "copy a --for x" "copy a --for" "copy a --for 0" "copy a --for 3601" "copy a --for 9999" "set a --helper" "list x" "status x" "nope" ""; do
    # shellcheck disable=SC2086  # each row is words on purpose
    K "" $a > "$T/out" 2>&1; rc=$?; assert_eq "$rc" 2 "[$a] is refused (usage)"
  done
  assert_eq "$(calls)" "$n" "a refused name or usage never reaches ade-secrets"
  K "" copy a --for 3600 > /dev/null 2>&1; assert_contains "$SEC_LOG" "call [copy] [a] [--for] [3600]" "3600 is the longest"
  K "" copy a --for 0005 > /dev/null 2>&1; assert_contains "$SEC_LOG" "call [copy] [a] [--for] [0005]" "leading zeros are not octal"
  [ -z "$(sort -u "$SEC_LOG.self" | grep -vx "$F/ade-secrets")" ] || fail "every call is the one absolute path found once"
  no_clipboard
}

key_exit_codes() {   # AC2
  fresh; key_fixture; local rc
  for c in 0 1 2 3 4 5; do
    FAKE_RC="$c" K "" copy demo > "$T/out" 2>&1; rc=$?; assert_eq "$rc" "$c" "exit $c comes through"
    case "$c" in
      3) assert_contains "$T/out" "ade: ade-secrets refused: run this in your own terminal" "3: one plain line" ;;
      4) assert_contains "$T/out" "ade: no clipboard here" "4: one plain line" ;;
      5) assert_contains "$T/out" "ade: the store is locked" "5: one plain line" ;;
      *) assert_not_contains "$T/out" "ade:" "$c: no line of ade's" ;;
    esac
  done
  FAKE_RC=4 K "" set demo --clipboard > "$T/out" 2>&1; assert_eq "$?" 4 "set's exit too"
}

key_terminal_only() {   # AC3
  fresh; key_fixture; local a v rc
  for a in "list" "status" "set demo" "set demo --clipboard" "copy demo" "copy demo --for 5" "forget demo"; do
    # shellcheck disable=SC2086
    bash "$ADE" key $a < /dev/null > "$T/out" 2>&1; rc=$?
    assert_eq "$rc" 3 "[$a] without a terminal is refused"; assert_contains "$T/out" "runs only in your own terminal" "[$a] says why"
    for v in $SESSION_VARS; do
      # shellcheck disable=SC2086
      pty_run "" env "$v=1" bash "$ADE" key $a > "$T/out" 2>&1; rc=$?
      assert_eq "$rc" 3 "[$a] with $v set is refused"; assert_contains "$T/out" "not inside an agent session ($v is set)" "[$a] names $v"
    done
  done
  assert_eq "$(calls)" 0 "ade-secrets was never called"
}

secrets_release() {   # <tag> <files json>: a release.json for ade-secrets at that tag, under file://$T/gh
  local d="$T/gh/better-ade/ade-secrets/releases/download/$1"; mkdir -p "$d"
  printf '{"component": "ade-secrets", "version": "%s", "released": "2026-11-22T02:42:36Z", "summary": "fixture", "urgency": "normal", "min_supported": null, "files": %s}\n' "${1#v}" "$2" > "$d/release.json"
}
key_install_pinned() {   # AC4: the pinned tag's release.json must list every file; v0.3.0 lists none, so nothing installs
  fresh; key_fixture; rm -f "$F/ade-secrets"
  for t in git tmux gh yazi bat glow pdftotext pdftoppm chafa; do command -v "$t" > /dev/null 2>&1 || { printf '#!/bin/bash\nexit 0\n' > "$F/$t"; chmod +x "$F/$t"; }; done
  printf '#!/bin/bash\necho "brew $*" >> "%s/brew.log"; exit 1\n' "$T" > "$F/brew"; chmod +x "$F/brew"
  export ADE_TEST_ALLOW_FILE_URLS=1 ADE_RELEASES_BASE="file://$T/gh"
  secrets_release v0.3.0 '[]'   # as the real v0.3.0 release.json: no files
  local sha; sha="$(printf 'x' | shasum -a 256 2> /dev/null | cut -d' ' -f1)"; [ -n "$sha" ] || sha="$(printf 'x' | sha256sum | cut -d' ' -f1)"
  mkdir -p "$T/gh/better-ade/ade-secrets/releases/latest/download"   # a later release that lists them is not the pin
  printf '{"component": "ade-secrets", "version": "9.9.9", "files": [{"name": "ade-secrets", "sha256": "%s"}, {"name": "vault.sh", "sha256": "%s"}]}\n' "$sha" "$sha" \
    > "$T/gh/better-ade/ade-secrets/releases/latest/download/release.json"
  bash "$ADE" setup --tools < /dev/null > "$T/out" 2>&1
  assert_contains "$T/out" "to install it, run ade setup --tools at a terminal" "without a terminal: no question, one line"
  pty_run "n\n" bash "$ADE" setup --tools > "$T/out" 2>&1
  assert_contains "$T/out" "Install ade-secrets v0.3.0 now" "asks first, naming the pinned tag"; assert_contains "$T/out" "ade-secrets not installed" "no: nothing"
  pty_run "y\n" bash "$ADE" setup --tools > "$T/out" 2>&1
  assert_contains "$T/out" "names no sha256 for: ade-secrets vault.sh, so nothing is installed" "v0.3.0 lists no file: nothing installed"
  assert_contains "$T/out" "lists bin/ade-secrets and lib/vault.sh" "says what the release must publish"
  pty_run "y\n" env ADE_SECRETS_REF=v0.4.0 bash "$ADE" setup --tools > "$T/out" 2>&1
  assert_contains "$T/out" "there is no release.json for ade-secrets v0.4.0" "a tag without a release.json installs nothing"
  secrets_release v0.4.0 '[{"name": "ade-secrets", "sha256": "'"$sha"'"}]'
  pty_run "y\n" env ADE_SECRETS_REF=v0.4.0 bash "$ADE" setup --tools > "$T/out" 2>&1
  assert_contains "$T/out" "names no sha256 for: vault.sh" "every file must be listed"
  printf '{"component": "ade-brain", "version": "0.4.0", "files": []}\n' > "$T/gh/better-ade/ade-secrets/releases/download/v0.4.0/release.json"
  pty_run "y\n" env ADE_SECRETS_REF=v0.4.0 bash "$ADE" setup --tools > "$T/out" 2>&1
  assert_contains "$T/out" "is not valid (it is not the manifest of ade-secrets)" "another component's manifest is refused"
  pty_run "y\n" env ADE_SECRETS_REF=main bash "$ADE" setup --tools > "$T/out" 2>&1
  assert_contains "$T/out" "ADE_SECRETS_REF must be a release tag" "only a pinned release tag"
  pty_run "y\n" env CLAUDECODE=1 bash "$ADE" setup --tools > "$T/out" 2>&1
  assert_contains "$T/out" "ade installs nothing from an agent session" "never from an agent session"
  ! command -v ade-secrets > /dev/null 2>&1 || fail "nothing was installed on PATH"
  [ -z "$(find "$HOME" -name 'ade-secrets*' -o -name vault.sh 2> /dev/null)" ] || fail "no ade-secrets file under HOME"
  [ ! -f "$T/brew.log" ] || fail "no package manager ran"
}

key_missing_tool() {   # AC5
  fresh; key_fixture; rm -f "$F/ade-secrets"; local a rc
  for a in "list" "status" "set demo" "copy demo" "forget demo"; do
    # shellcheck disable=SC2086
    bash "$ADE" key $a < /dev/null > "$T/out" 2>&1; rc=$?
    assert_eq "$rc" 2 "[$a] without ade-secrets exits 2"; assert_eq "$(wc -l < "$T/out" | tr -d ' ')" 1 "[$a] one line"
    assert_contains "$T/out" "ade-secrets is not installed; get it with: ade setup --tools" "[$a] says how to get it"
  done
}

key_store_choice() {   # AC6: no store recorded: the first set asks; ade-secrets records it; ade never runs `store <name>`
  fresh; key_fixture; export FAKE_STORE_RC=2
  K "\n" set demo > "$T/out" 2>&1 || { cat "$T/out"; fail "set"; }
  assert_contains "$T/out" "1) the macOS Keychain (default)" "macOS offers the Keychain first"
  assert_contains "$SEC_LOG" "call [set] [demo] stdin=tty stdout=tty store=keychain" "Enter: the Keychain, for ade-secrets to record"
  K "3\n" set demo > /dev/null 2>&1; assert_contains "$SEC_LOG" "call [set] [demo] stdin=tty stdout=tty store=age" "3: age"
  K "pass\n" set demo > /dev/null 2>&1; assert_contains "$SEC_LOG" "call [set] [demo] stdin=tty stdout=tty store=pass" "by name"
  FAKE_OS=Linux K "\n" set demo > "$T/out" 2>&1; assert_contains "$T/out" "1) pass (default)  2) age" "Linux: pass or age"
  assert_not_contains "$T/out" "Keychain" "no Keychain on Linux"
  FAKE_OS=Linux K "2\n" set demo > /dev/null 2>&1; assert_eq "$(tail -1 "$SEC_LOG")" "call [set] [demo] stdin=tty stdout=tty store=age" "Linux 2: age"
  local n; n="$(grep -c '^call \[set\]' "$SEC_LOG")"
  FAKE_OS=Linux K "keychain\n" set demo > "$T/out" 2>&1; assert_eq "$?" 2 "a store not offered is refused"
  assert_eq "$(grep -c '^call \[set\]' "$SEC_LOG")" "$n" "and nothing is set"
  : > "$SEC_LOG"; FAKE_STORE_RC=0 K "" set demo > "$T/out" 2>&1
  assert_not_contains "$T/out" "has no store yet" "a recorded store: no question"
  assert_contains "$SEC_LOG" "call [set] [demo] stdin=tty stdout=tty store=" "and ade passes no store"
  : > "$SEC_LOG"; ADE_SECRETS_STORE=pass K "" set demo > "$T/out" 2>&1
  assert_not_contains "$SEC_LOG" "call [store]" "the person's own ADE_SECRETS_STORE: not even asked"
  K "\n" copy demo > /dev/null 2>&1; K "\n" list > /dev/null 2>&1
  assert_not_contains "$SEC_LOG" "call [copy] [demo] stdin=tty stdout=tty store=keychain" "only set asks"
  grep -E '^call \[store\] \[' "$SEC_LOG" && fail "ade never sets or switches the store"; return 0
}

doctor_hub() {   # <dir> <delegates 0|1> <rules 0|1>: a hub whose bin/doctor and bin/keys are fakes
  make_hub "$1" hub; printf 'HUB_NAME=acme\n' > "$1/hub.conf"; mkdir -p "$1/.claude"
  printf '#!/bin/bash\necho "hub doctor ran"\n' > "$1/bin/doctor"
  if [ "$2" = 1 ]; then printf '#!/bin/bash\nset -u\n# >>> ade-secrets delegation (docs/contract.md v1 in better-ade/ade-secrets)\n# <<< ade-secrets delegation\n' > "$1/bin/secret"
  else printf '#!/bin/bash\nset -u\necho built-in\n' > "$1/bin/secret"; fi
  if [ "$3" = 1 ]; then cat > "$1/.claude/settings.json" <<'J'
{"permissions": {"deny": ["Read(~/.ade-secrets/**)", "Bash(security find-generic-password*)", "Bash(security dump-keychain*)",
  "Bash(pass show*)", "Bash(pbpaste*)"], "ask": ["Bash(ade-secrets *)"], "allow": ["Bash(git status)"]}}
J
  else printf '{"permissions": {"deny": ["Bash(pbpaste*)"]}}\n' > "$1/.claude/settings.json"; fi
  chmod +x "$1/bin/"*
}
key_doctor() {   # AC7
  fresh; key_fixture; doctor_hub "$T/hub" 1 1; export ADE_HUB="$T/hub"
  # no ~/.ade-secrets yet: "none chosen", and the tool's store command (which would make the folder) is not called
  pty_run "" bash "$ADE" doctor > "$T/out" 2>&1; assert_contains "$T/out" "secrets: ade-secrets 0.3.0, store none chosen yet" "no folder: none chosen"
  pty_run "" bash "$ADE" setup --check > /dev/null 2>&1
  [ ! -e "$HOME/.ade-secrets" ] || fail "a check made ~/.ade-secrets"; assert_not_contains "$SEC_LOG" "call [store]" "no store call without the folder"
  mkdir -m 700 "$HOME/.ade-secrets"
  pty_run "" bash "$ADE" doctor > "$T/out" 2>&1
  assert_contains "$T/out" "secrets: ade-secrets 0.3.0, store keychain" "version and store"; assert_contains "$T/out" "hub doctor ran" "then the hub's doctor"
  assert_not_contains "$T/out" "built-in store" "a delegating hub"; assert_not_contains "$T/out" "lacks" "with every rule"
  pty_run "" bash "$ADE" setup --check > "$T/out" 2>&1; assert_contains "$T/out" "secrets: ade-secrets 0.3.0, store keychain" "setup --check too"
  FAKE_STORE_RC=2 pty_run "" bash "$ADE" doctor > "$T/out" 2>&1; assert_contains "$T/out" "store none chosen yet (the first ade key set asks)" "no store yet"
  bash "$ADE" doctor < /dev/null > "$T/out" 2>&1; assert_contains "$T/out" "store unknown here (run ade doctor in your own terminal)" "no terminal: not asked"
  doctor_hub "$T/hub2" 0 0; ADE_HUB="$T/hub2" pty_run "" bash "$ADE" doctor > "$T/out" 2>&1
  assert_contains "$T/out" "secrets: the hub still uses its built-in store" "a hub without H2's block"; assert_contains "$T/out" "update it: ade update" "with what to run"
  assert_contains "$T/out" "lacks the ade-secrets permission rules (Read(~/.ade-secrets/**) Bash(security find-generic-password*)" "names the missing rules"
  HUB_SECRETS=builtin pty_run "" bash "$ADE" doctor > "$T/out" 2>&1; assert_contains "$T/out" "HUB_SECRETS=builtin keeps the hub on its built-in store" "builtin"
  rm -f "$F/ade-secrets"; pty_run "" bash "$ADE" doctor > "$T/out" 2>&1
  assert_contains "$T/out" "secrets: ade-secrets is not installed (ade setup --tools); the hub uses its built-in store" "missing"
  grep -vE '^call \[(version|store)\]' "$SEC_LOG" && fail "doctor asks only for the version and the store's name"; return 0
}

setup_hub_for() {   # <delegates 0|1>: a hub for setup and restore: bin/keys names deepseek's key, bin/agent answers READY
  H="$T/hub"; doctor_hub "$H" "$1" 1; printf 'HUB_NAME=acme\nHUB_ROOT_MODEL=opus\n' > "$H/hub.conf"; export CALLS="$T/calls" ADE_HUB="$H" ADE_GEMINI_CLI=no-gemini-cli-here; : > "$CALLS"
  cat > "$H/bin/keys" <<'S'
#!/bin/bash
echo "keys $*" >> "$CALLS"
if [ "${1:-}" = set ]; then IFS= read -r v; echo "$2=$v" >> "$CALLS.keystore"; exit 0; fi
printf 'anthropic  uses your Claude login (no key here)\n'
printf 'deepseek   missing  %s\nglm        missing  zai-api-key\nmuse       missing  meta-model-api-key\ngemini     missing  gemini-api-key\n' "${FAKE_DEEPSEEK_COL:-deepseek-api-key}"
[ -f "$CALLS.keystore" ] && sed 's/=.*/ stored/' "$CALLS.keystore"; exit 0
S
  printf '#!/bin/bash\necho "agent $*" >> "$CALLS"; IFS= read -r t; echo READY\n' > "$H/bin/agent"
  printf '#!/bin/bash\necho "chat $*" >> "$CALLS"\n[ "$1 $2" = "info telegram" ] && echo "bot @acme_bot"; exit 0\n' > "$H/bin/chat"
  printf '#!/bin/bash\necho "claude $*" >> "$CALLS"\n[ "$1 $2" = "auth status" ]\n' > "$F/claude"
  chmod +x "$H/bin/"* "$F/claude"
}
restore_record() {
  mkdir -p "$H/.ade"; printf '{"format": 1, "focus": [{"provider": "deepseek", "sign_in": "key"}%s], "channels": [{"type": "telegram", "bot": "@acme_bot"}]}\n' "${1:-}" > "$H/.ade/connections.json"
}
key_setup_restore() {   # AC8
  fresh; key_fixture; setup_hub_for 1; local p n
  # Claude Code's own keys (ade's HUB_KEY_USERS table): helper entries, said plainly first, under the hub's names
  for p in "2 anthropic anthropic" "3 deepseek deepseek-api-key" "4 glm zai-api-key" "5 muse meta-model-api-key"; do
    set -- $p; : > "$SEC_LOG"
    pty_run "$1\nc\n" bash "$ADE" setup --top > "$T/out" 2>&1
    assert_contains "$T/out" "Claude Code, and anything it runs, can read it without a dialog; that is how its sessions get it." "$2: what the helper mark means, first"
    assert_contains "$T/out" "from the clipboard (c)" "$2: offers --clipboard"
    assert_contains "$SEC_LOG" "call [set] [$3] [--clipboard] [--helper] [--kind] [api-key] [--used-by] [hub] stdin=tty stdout=tty" "$2: ade key set, as bin/secret --set would"
  done
  assert_contains "$HOME/.config/ade/keys-set" "deepseek" "recorded by name for ade reset --keys"
  pty_run "3\np\n" bash "$ADE" setup --top > /dev/null 2>&1; assert_eq "$(tail -1 "$SEC_LOG")" "call [set] [deepseek-api-key] [--helper] [--kind] [api-key] [--used-by] [hub] stdin=tty stdout=tty store=" "p: the hidden prompt"
  # keys Claude Code is not given (the Telegram token, the Gemini API key): not stored in ade-secrets, one line
  : > "$SEC_LOG"; pty_run "y\n" bash "$ADE" setup --telegram > "$T/out" 2>&1
  assert_contains "$T/out" "telegram: this key is not supported with ade-secrets yet (Claude Code is not given it); the hub's built-in store handles it" "telegram: one line"
  restore_record ', {"provider": "gemini", "sign_in": "key"}'
  pty_run "y\np\ny\ny\n" bash "$ADE" restore > "$T/out" 2>&1
  assert_contains "$SEC_LOG" "call [set] [deepseek-api-key] [--helper]" "restore: a Claude Code key through ade key set"
  assert_contains "$T/out" "gemini: this key is not supported with ade-secrets yet" "restore: gemini refused"
  assert_contains "$T/out" "telegram: this key is not supported with ade-secrets yet" "restore: the bot token refused"
  if grep -E '^call \[set\] \[(telegram|gemini|gemini-api-key)\]' "$SEC_LOG"; then fail "no helper entry for a key Claude Code is not given"; fi
  assert_not_contains "$CALLS" "keys set" "never bin/keys set on a delegating hub"
  pty_run "3\ns\n" bash "$ADE" setup --top > "$T/out" 2>&1; assert_contains "$T/out" "deepseek: skipped" "s skips"
  # an agent session: refused before ade-secrets or the hub's key list is asked
  : > "$SEC_LOG"; : > "$CALLS"; pty_run "3\nc\n" env CLAUDE_PID=1 bash "$ADE" setup --top > "$T/out" 2>&1; assert_eq "$?" 3 "CLAUDE_PID: refused"
  assert_contains "$T/out" "not inside an agent session (CLAUDE_PID is set)" "says why"
  assert_eq "$(calls)" 0 "no call to ade-secrets"; assert_not_contains "$CALLS" "keys" "nor to the hub's bin/keys"
  # the hub's third column is used only when it is one name by the contract's rule
  for n in "-rf" "a b" "../x"; do : > "$SEC_LOG"
    FAKE_DEEPSEEK_COL="$n" pty_run "3\np\n" bash "$ADE" setup --top > /dev/null 2>&1
    assert_contains "$SEC_LOG" "call [set] [deepseek] [--helper]" "column [$n]: the tool's name instead"; done
  assert_not_contains "$SEC_LOG" "stdin=pipe" "nothing piped to ade-secrets"; no_clipboard
  # a hub without H2's block: today's bin/keys set path, the token on its stdin, and ade-secrets untouched
  fresh; key_fixture; setup_hub_for 0
  printf 'y\nfake-token-not-real\n' | bash "$ADE" setup --telegram > "$T/out" 2>&1 || { cat "$T/out"; fail "setup --telegram (built-in)"; }
  assert_contains "$CALLS.keystore" "telegram=fake-token-not-real" "bin/keys set telegram, as before"
  restore_record; pty_run "y\nfake-deep-not-real\ny\nfake-token-2\n" bash "$ADE" restore > "$T/out" 2>&1
  assert_contains "$CALLS.keystore" "deepseek=fake-deep-not-real" "restore: bin/keys set, as before"
  grep '^call \[set\]' "$SEC_LOG" && fail "ade-secrets is not used for a hub that does not delegate"; no_clipboard; return 0
}

key_tool_path() {   # fix round item 6: ade-secrets found once, as an absolute path; never a copy in a project, the hub or a work tree
  fresh; key_fixture; local P="$T/proj" W="$T/plain" rc
  mkdir -p "$P/bin" "$W/bin"; git init -q "$P"; cp "$F/ade-secrets" "$P/bin/ade-secrets"; cp "$F/ade-secrets" "$W/bin/ade-secrets"
  (cd "$T" && PATH="$P/bin:$PATH" pty_run "" bash "$ADE" key list) > "$T/out" 2>&1; rc=$?
  assert_eq "$rc" 2 "a copy in a git work tree is refused"; assert_contains "$T/out" "refused $P/bin/ade-secrets: it lies in the git work tree $P" "names the file and why"
  (cd "$W" && PATH="$W/bin:$PATH" pty_run "" bash "$ADE" key list) > "$T/out" 2>&1
  assert_contains "$T/out" "refused $W/bin/ade-secrets: it lies under the current folder" "a copy under the current folder"
  make_hub "$T/hub" hub; mkdir -p "$T/hub/tools"; cp "$F/ade-secrets" "$T/hub/tools/ade-secrets"
  (cd "$T" && ADE_HUB="$T/hub" PATH="$T/hub/tools:$PATH" pty_run "" bash "$ADE" key list) > "$T/out" 2>&1
  assert_contains "$T/out" "it lies under the hub ($T/hub)" "a copy under the hub"
  ln -s "$P/bin/ade-secrets" "$W/link"; mkdir -p "$T/lnk"; ln -s "$P/bin/ade-secrets" "$T/lnk/ade-secrets"
  (cd "$T" && PATH="$T/lnk:$PATH" pty_run "" bash "$ADE" key list) > "$T/out" 2>&1
  assert_contains "$T/out" "it lies in the git work tree $P" "a link to a copy in a work tree"
  assert_eq "$(calls)" 0 "no refused copy ran"
  (cd "$HOME" && pty_run "" bash "$ADE" key list) > "$T/out" 2>&1 || { cat "$T/out"; fail "from the home folder"; }
  pty_run "" bash "$ADE" doctor > /dev/null 2>&1; pty_run "" bash "$ADE" key status > /dev/null 2>&1
  [ -z "$(sort -u "$SEC_LOG.self" | grep -vx "$F/ade-secrets")" ] || { cat "$SEC_LOG.self"; fail "every call: the absolute path"; }
  (cd "$T" && PATH="$P/bin:$PATH" bash "$ADE" doctor < /dev/null) > "$T/out" 2>&1; assert_contains "$T/out" "secrets: refused $P/bin/ade-secrets" "doctor says it too"
}

key_hostile() {   # AC9: the hostile names, each refused (exit 2) before ade-secrets runs (the full table: test_hostile.sh)
  fresh; key_fixture; local long x rc a; long="$(printf 'a%.0s' $(seq 1 65))"
  for x in "a b" "a
b" "$(printf 'a\tb')" "$(printf 'a\033[2Jb')" ".." "../x" "-rf" "--helper" "$long" "" "héllo" "a/b" "\$(touch $T/pwned)"; do
    for a in set copy forget; do
      K "" "$a" "$x" > "$T/out" 2>&1; rc=$?; assert_eq "$rc" 2 "[key $a] with [$x]"
    done
  done
  assert_eq "$(calls)" 0 "no hostile name reached ade-secrets"; [ ! -e "$T/pwned" ] || fail "an input ran"
  K "" set "$(printf 'a%.0s' $(seq 1 64))" > /dev/null 2>&1; assert_eq "$(grep -c '^call \[set\]' "$SEC_LOG")" 1 "64 characters is the longest name"
}

ALL="key_delegates key_exit_codes key_terminal_only key_install_pinned key_missing_tool key_store_choice key_doctor key_setup_restore key_hostile key_tool_path"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
