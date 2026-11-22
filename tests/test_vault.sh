#!/bin/bash
# story A14: `ade vault`, through ade-secrets. The same fake ade-secrets as test_key.sh (each call's arguments, whether
# stdin and stdout are the terminal, anything piped to it; FAKE_RC its exit code) and, for ade ui, a fake tmux that
# records its calls. Never the real ade-secrets, a keychain or a clipboard tool.
. "$(dirname "$0")/helpers.sh"

SESSION_VARS="CLAUDECODE CLAUDE_CODE_CHILD_SESSION CLAUDE_PID CLAUDE_CODE_SESSION_ID CLAUDE_CODE_BRIDGE_SESSION_ID
  CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CLAUDE_CODE_EXECPATH CLAUDE_CODE_SSE_PORT CLAUDE_CODE_ENTRYPOINT"
vault_fixture() {
  # shellcheck disable=SC2086
  unset $SESSION_VARS ADE_SECRETS_STORE FAKE_RC
  F="$T/fakebin"; mkdir -p "$F"; export SEC_LOG="$T/secrets.log"; : > "$SEC_LOG"
  cat > "$F/ade-secrets" <<'FAKE'
#!/bin/bash
in=tty; [ -t 0 ] || in="pipe:$(cat)"; out=tty; [ -t 1 ] || out=pipe
{ printf 'call'; printf ' [%s]' "$@"; printf ' stdin=%s stdout=%s\n' "$in" "$out"; } >> "$SEC_LOG"
[ "${1:-}" = version ] && { echo 0.3.0; exit 0; }
echo "FAKE-VAULT-SCREEN $*"
exit "${FAKE_RC:-0}"
FAKE
  chmod +x "$F/ade-secrets"; export PATH="$F:$PATH"
}
calls() { grep -c '^call' "$SEC_LOG"; }
V() { local i="$1"; shift; pty_run "$i" bash "$ADE" vault "$@"; }

vault_delegates() {   # AC1
  fresh; vault_fixture; local c rc
  V "" > "$T/out" 2>&1 || { cat "$T/out"; fail "vault"; }
  assert_eq "$(cat "$SEC_LOG")" "call [vault] stdin=tty stdout=tty" "ade vault runs ade-secrets vault on the terminal"
  assert_contains "$T/out" "FAKE-VAULT-SCREEN vault" "what it draws reaches the terminal, not ade"
  V "" lock > /dev/null 2>&1; assert_eq "$(tail -1 "$SEC_LOG")" "call [lock] stdin=tty stdout=tty" "lock"
  V "" unlock > /dev/null 2>&1; assert_eq "$(tail -1 "$SEC_LOG")" "call [unlock] stdin=tty stdout=tty" "unlock"
  for c in 0 1 2 3 4 5; do FAKE_RC="$c" V "" > /dev/null 2>&1; rc=$?; assert_eq "$rc" "$c" "exit $c comes through"; done
  FAKE_RC=5 V "" unlock > "$T/out" 2>&1; assert_eq "$?" 5 "unlock's exit too"; assert_contains "$T/out" "ade: the store is locked" "5: one plain line"
  local n; n="$(calls)"
  for a in "x" "lock x" "-h" "vault" "list"; do
    # shellcheck disable=SC2086
    V "" $a > /dev/null 2>&1; assert_eq "$?" 2 "[vault $a] is refused (usage)"; done
  V "" "" > /dev/null 2>&1; assert_eq "$?" 2 "an empty word is refused"
  assert_eq "$(calls)" "$n" "a refused word never reaches ade-secrets"
  assert_not_contains "$SEC_LOG" "stdin=pipe" "nothing piped to ade-secrets"
}

vault_terminal_only() {   # AC2
  fresh; vault_fixture; local a v rc
  for a in "" "lock" "unlock"; do
    # shellcheck disable=SC2086
    bash "$ADE" vault $a < /dev/null > "$T/out" 2>&1; rc=$?
    assert_eq "$rc" 3 "[vault $a] without a terminal"; assert_contains "$T/out" "runs only in your own terminal" "[vault $a] says why"
    for v in $SESSION_VARS; do
      # shellcheck disable=SC2086
      pty_run "" env "$v=1" bash "$ADE" vault $a > "$T/out" 2>&1; rc=$?
      assert_eq "$rc" 3 "[vault $a] with $v"; assert_contains "$T/out" "($v is set)" "[vault $a] names $v"
    done
  done
  assert_eq "$(calls)" 0 "ade-secrets was never called"
  rm -f "$F/ade-secrets"; bash "$ADE" vault < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "missing: exit 2"
  assert_contains "$T/out" "ade-secrets is not installed; get it with: ade setup --tools" "missing: how to get it"
}

ui_fixture() {   # a hub, and a fake tmux that logs every call (one line each)
  make_hub "$T/hub" hub; printf 'HUB_NAME=acme\n' > "$T/hub/hub.conf"; mkdir -p "$T/hub/projects/api"
  export ADE_HUB="$T/hub" AGENT_STATE="$T/state" TMUX_LOG="$T/tmux.log"; mkdir -p "$AGENT_STATE"; : > "$TMUX_LOG"
  printf '#!/bin/bash\necho "NAME FOLDER PID PARENT STARTED ROLE STATUS LAST"\n' > "$T/hub/bin/sessions"; chmod +x "$T/hub/bin/sessions"
  cat > "$F/tmux" <<'FAKE'
#!/bin/bash
[ "$1" = -L ] && shift 2
{ printf 'tmux'; printf ' %s' "$@"; printf '\n'; } >> "$TMUX_LOG"
case "$1" in has-session) [ -f "$TMUX_LOG.s" ]; exit $? ;; new-session) touch "$TMUX_LOG.s" ;; esac
exit 0
FAKE
  printf '#!/bin/bash\necho "claude $*"\n' > "$F/claude"; chmod +x "$F/tmux" "$F/claude"
}
vault_popup() {   # AC3: prefix v opens the vault in a popup that closes when it exits; ade never captures it
  fresh; vault_fixture; ui_fixture
  bash "$ADE" ui --detach > "$T/out" 2>&1 || { cat "$T/out"; fail "ui"; }
  S="$(bash "$ADE" ui --session)"; C="$HOME/.config/ade/ui-$S.tmux.conf"
  line="$(grep -- '-T prefix v ' "$C")" || fail "a key for the vault"
  case "$line" in *"display-popup -E -w 90% -h 90% \""*"' vault\"") ;; *) fail "prefix v: a popup that runs ade vault and closes with it: $line" ;; esac
  case "$line" in *pipe-pane*|*capture*|*tee*|*">"*) fail "nothing of the popup is captured or logged: $line" ;; esac
  assert_not_contains "$C" "pipe-pane" "no pane is piped to a log"
  bash "$ADE" ui --keys < /dev/null > "$T/out"; assert_contains "$T/out" "prefix v   vault:" "the help popup lists the key"
  # the popup's own command, on a terminal: ade-secrets vault, attached
  cmd="${line#*display-popup -E -w 90% -h 90% \"}"; cmd="${cmd%\"}"
  case "$cmd" in "ADE_HUB='$T/hub' '"*"' vault") ;; *) fail "the popup runs ade vault: $cmd" ;; esac
  pty_run "" env ADE_HUB="$T/hub" bash "$ADE" vault > /dev/null 2>&1; assert_eq "$(tail -1 "$SEC_LOG")" "call [vault] stdin=tty stdout=tty" "the vault in the popup's terminal"
  # every capture ade makes: only the links key's, of the pane it was given; none names the vault or its popup
  bash "$ADE" ui --menu links %3 > /dev/null 2>&1; bash "$ADE" ui --bar "$S" > /dev/null 2>&1; bash "$ADE" dash --once > "$T/dash" 2>&1
  grep 'capture-pane' "$TMUX_LOG" > "$T/captures" || true
  assert_eq "$(grep -c . "$T/captures")" 1 "one capture: the links key's"; assert_contains "$T/captures" "capture-pane -p -J -S -2000 -t %3" "of its pane"
  if grep -i 'vault\|popup' "$T/captures"; then fail "no capture names the vault's popup"; fi
  [ "$(grep -c 'tmux capture-pane' "$ADE")" = 1 ] || fail "ade has one capture-pane call (the links key's), never the vault's popup"
  assert_not_contains "$T/dash" "FAKE-VAULT-SCREEN" "nothing of the vault in ade dash"; assert_not_contains "$T/dash" "vault" "ade dash names no vault"
  if grep -rl 'FAKE-VAULT-SCREEN' "$HOME" "$AGENT_STATE" 2> /dev/null; then fail "nothing of the vault in a log or file"; fi
  assert_eq "$(grep -c '^call \[vault\]' "$SEC_LOG")" 1 "the vault ran only when opened"
}

vault_reminder() {   # AC4: ade-secrets v0.3.0 offers no names-only way to ask which keys are due: no reminder, ade asks nothing
  fresh; vault_fixture; make_hub "$T/hub" hub; export ADE_HUB="$T/hub"
  pty_run "" bash "$ADE" > "$T/out" 2>&1 || { cat "$T/out"; fail "ade alone"; }
  assert_eq "$(calls)" 0 "ade alone never calls ade-secrets"
  assert_not_contains "$T/out" "rotat" "no reminder"
  N="$REPO/docs/notes/A14-ade-vault.md"
  assert_contains "$N" "no names-only way to ask which keys are due" "the note says why it is left out"
  assert_contains "$N" "ade-secrets list --due" "and what ade-secrets would need"
}

vault_docs() {   # AC5: README, help and CHANGELOG, in plain words, with the Owner check
  fresh; local f
  bash "$ADE" help > "$T/help"
  assert_contains "$T/help" "  key         ade key list | set <name> [--clipboard] | copy <name> [--for N] | forget <name> | status" "help: ade key"
  assert_contains "$T/help" "  vault       ade vault [lock | unlock]" "help: ade vault"
  for f in README.md CHANGELOG.md; do
    assert_contains "$REPO/$f" "ade key" "$f: ade key"; assert_contains "$REPO/$f" "ade vault" "$f: ade vault"
    assert_contains "$REPO/$f" "Owner check" "$f: the Owner check"
    assert_contains "$REPO/$f" "before a real key is stored" "$f: before a real key"
  done
  assert_contains "$REPO/README.md" "| \`ade key list\` · \`ade key set <name> [--clipboard]\`" "README: the command reference"
  assert_contains "$REPO/README.md" "| \`ade vault [lock\\|unlock]\`" "README: the vault row"
  assert_contains "$REPO/README.md" "never shows, logs or keeps a value" "README: plain words on what ade does not do"
}

ALL="vault_delegates vault_terminal_only vault_popup vault_reminder vault_docs"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
