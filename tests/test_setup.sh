#!/bin/bash
# story A5: `ade setup`. Fakes for claude, the installer, the hub's bin/keys, bin/agent and bin/chat, and gh; answers
# come on stdin; never the network. Every fake logs its arguments to $T/calls and its environment to $T/envs.
. "$(dirname "$0")/helpers.sh"

setup_fakes() {   # $1 = 1: claude on PATH (default), 0: missing
  mkdir -p "$T/fakebin"; export CALLS="$T/calls" ENVS="$T/envs" ADE_GEMINI_CLI=no-gemini-cli-here   # a host Gemini CLI never answers; : > "$CALLS"; : > "$ENVS"
  if [ "${1:-1}" = 1 ]; then fake_claude "$T/fakebin"; fi
  # a fake gh, signed in (A18: the guide's GitHub step); repo create clones $TPL
  printf '#!/bin/bash\necho "gh $*" >> "$CALLS"\n[ "$1 $2" = "repo create" ] && git clone -q "$TPL" "$3"\n[ "$1 $2" = "api user" ] && echo tester\nexit 0\n' > "$T/fakebin/gh"
  chmod +x "$T/fakebin/gh"; export PATH="$T/fakebin:$PATH"
}
fake_claude() {
  cat > "$1/claude" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$CALLS"; env >> "$ENVS"
case "$1 ${2:-}" in
  "auth status") [ -f "$CALLS.loggedin" ] ;; "auth login") touch "$CALLS.loggedin" ;;
  *) echo "session pwd:$PWD"; for a in "$@"; do echo "arg:$a"; done ;;
esac
STUB
  chmod +x "$1/claude"
}
agent_stub() {   # a fake bin/agent: --live-test <p> answers READY unless $AGENT_FAIL names p
  cat > "$1" <<'STUB'
#!/bin/bash
echo "agent $* pwd=$PWD" >> "$CALLS"; env >> "$ENVS"; IFS= read -r task; echo "task:$task" >> "$CALLS"
case " ${AGENT_FAIL:-} " in *" $2 "*) echo "agent: the key was rejected (401)" >&2; exit 1 ;; esac
echo READY
STUB
  chmod +x "$1"
}
setup_hub() {   # a hub named acme at $T/hub whose fakes log; AGENT_FAIL names providers whose live test fails
  make_hub "$T/hub" hub; printf 'HUB_NAME=acme\nHUB_ROOT_MODEL=opus\n' > "$T/hub/hub.conf"   # no project yet: the guide runs the session
  cat > "$T/hub/bin/keys" <<'STUB'
#!/bin/bash
echo "keys $*" >> "$CALLS"; env >> "$ENVS"
if [ "${1:-}" = set ]; then IFS= read -r v; echo "$2=$v" >> "$CALLS.keystore"; exit 0; fi
[ -f "$CALLS.keystore" ] && sed 's/=.*/ stored/' "$CALLS.keystore"; exit 0
STUB
  agent_stub "$T/hub/bin/agent"
  cat > "$T/hub/bin/chat" <<'STUB'
#!/bin/bash
echo "chat $*" >> "$CALLS"; env >> "$ENVS"; echo "chat ran: $*"
STUB
  chmod +x "$T/hub/bin/keys" "$T/hub/bin/agent" "$T/hub/bin/chat"; export ADE_HUB="$T/hub"
}
setup() { printf '%s\n' 1 "$@" | bash "$ADE" setup > "$T/out" 2>&1; }   # 1: the guide's Claude sign-in step, with the account (A18)
conf() { (. "$T/hub/hub.conf"; eval "echo \"\${$1:-}\""); }

installer_asks_first() {   # AC1
  fresh; setup_fakes 0; setup_hub
  mkdir -p "$T/inst"; printf '#!/bin/bash\nmkdir -p "$HOME/.local/bin"; echo installer-ran >> "%s"\n' "$CALLS" > "$T/inst/install.sh"
  fake_claude "$T/inst"; printf 'cp "%s/claude" "$HOME/.local/bin/claude"\n' "$T/inst" >> "$T/inst/install.sh"
  export ADE_CLAUDE_INSTALLER="file://$T/inst/install.sh" PATH="$T/fakebin:$(no_claude_path)"
  printf 'y\n' | bash "$ADE" setup > "$T/out" 2>&1; assert_not_contains "$CALLS" "installer-ran" "a non-https installer is refused without the test flag"
  export ADE_TEST_ALLOW_FILE_URLS=1
  printf 'n\n' | bash "$ADE" setup > "$T/out" 2>&1; rc=$?; assert_eq "$rc" 1 "no stops"
  assert_contains "$T/out" "file://$T/inst/install.sh" "the prompt shows the URL that will run"
  assert_contains "$T/out" "curl -fsSL https://claude.ai/install.sh | bash" "names the manual command"
  assert_not_contains "$CALLS" "installer-ran" "nothing installed without a yes"
  printf 'y\n' | ADE_NO_CLAUDE_UPDATE= bash "$ADE" setup > "$T/out" 2>&1
  assert_contains "$CALLS" "installer-ran" "a yes runs the installer"
  [ "$(grep -n '^claude update' "$CALLS" | head -1 | cut -d: -f1)" -gt "$(grep -n 'installer-ran' "$CALLS" | cut -d: -f1)" ] 2>/dev/null || fail "installs, then updates"
  [ -x "$HOME/.local/bin/claude" ] || fail "claude installed"
}
no_claude_path() { local d="$T/noclaude"; mkdir -p "$d"; local c p; for c in git python3 bash sed awk grep mkdir cat dirname basename tr head tail mktemp mv chmod rm ls cp find sort env pwd date wc curl touch rmdir sleep cut kill; do
  p="$(command -v "$c")" && ln -sf "$p" "$d/$c"; done; echo "$d"; }

account_signin() {   # AC2
  fresh; setup_fakes; setup_hub
  setup 1 "" n || { cat "$T/out"; fail "setup exit"; }
  assert_contains "$CALLS" "claude auth login" "Claude Code's own login"
  assert_not_contains "$CALLS" "keys set" "stores nothing"
  bash "$ADE" setup --check > "$T/out" 2>&1; assert_contains "$T/out" "sign-in: signed in (account)" "check shows account"
}

key_only_on_stdin() {   # AC3
  fresh; setup_fakes; setup_hub
  setup 3 "S3CRET-deepseek-key" "" y "S3CRET-telegram-token" || { cat "$T/out"; fail "setup exit"; }
  assert_contains "$CALLS.keystore" "deepseek=S3CRET-deepseek-key" "the key reached bin/keys set deepseek on stdin"
  assert_contains "$CALLS.keystore" "telegram=S3CRET-telegram-token" "the token reached bin/keys set telegram on stdin"
  hits=$(grep -rl "S3CRET" "$T" | grep -v "calls.keystore$"); assert_eq "$hits" "" "no other file, argv log, env log or output holds a secret"
}

glm_needs_live_check() {   # AC4
  fresh; setup_fakes; setup_hub; export AGENT_FAIL=glm
  setup 4 "glm-key" 1 "" n || { cat "$T/out"; fail "setup exit"; }
  grep -iE "glm.*needs the live check" "$T/out" > /dev/null && grep -iE "muse.*needs the live check" "$T/out" > /dev/null || { cat "$T/out"; fail "listed as needing the live check"; }
  assert_contains "$T/out" "glm cannot be the everything agent until its live check passes" "refused as default"
  assert_eq "$(conf HUB_ROOT_PROVIDER)" "anthropic" "the second answer became the top agent"
  case " $(conf HUB_PROVIDERS_ALLOWED) " in *" glm "*) fail "glm in no role" ;; esac
  fresh; setup_fakes; setup_hub; export AGENT_FAIL=glm; printf '4\nglm-key\n' | bash "$ADE" setup --top > "$T/out" 2>&1
  assert_eq "$(conf HUB_ROOT_PROVIDER)" "" "glm then no answer: no top agent written"
}

hub_when_missing() {   # AC5
  fresh; setup_fakes; mkdir -p "$T/nowhere"
  TPL="$T/template"; mkdir -p "$TPL/bin"; git init -q "$TPL"; : > "$TPL/bin/lib.sh"
  printf '#!/bin/bash\n[ "$1" = --list ] && exit 0\necho "init ran: $*" >> "%s"\necho HUB_NAME=fresh > hub.conf\n' "$CALLS" > "$TPL/bin/init"; chmod +x "$TPL/bin/init"; agent_stub "$TPL/bin/agent"; commit_tag "$TPL" t
  export ADE_HUB_TEMPLATE_URL="$TPL" TPL
  (cd "$T/nowhere" && printf '%s\n' 1 fresh sre Acme owner1 1 "" n | bash "$ADE" setup) > "$T/out" 2>&1 || { cat "$T/out"; fail "setup exit"; }
  assert_contains "$CALLS" "gh repo create fresh --template better-ade/ade-brain --private --clone" "on GitHub (A18: required)"
  assert_contains "$CALLS" "init ran: --persona sre --client Acme --owner owner1 --name fresh" "ade hub new ran"; [ -f "$HOME/hubs/fresh/hub.conf" ] || fail "hub made"
  fresh; setup_fakes; setup_hub; setup 1 "" n || fail "with a hub"
  assert_not_contains "$T/out" "No hub yet" "a hub skips it"
}

guided_session() {   # AC6
  fresh; setup_fakes; setup_hub; setup 1 "" n || fail "exit"
  assert_contains "$T/out" "session pwd:$T/hub" "starts ade claude at the hub"
  assert_contains "$T/out" "arg:--remote-control" "through ade claude"
  for s in "ade init" "ade agent add" "ade skills add" "bin/models" "bin/chat setup telegram" "ask before each change"; do
    assert_contains "$T/out" "$s" "the prompt names: $s"; done
}

check_changes_nothing() {   # AC7
  fresh; setup_fakes; setup_hub; echo "telegram=x" > "$CALLS.keystore"; printf 'HUB_CHANNELS="telegram"\n' >> "$T/hub/hub.conf"; mkdir -p "$T/hub/projects/a" "$T/hub/projects/b"
  snap() { (cd "$T" && find hub home -type f -exec cksum {} + | sort); }
  before="$(snap)"; bash "$ADE" setup --check < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "check exit"; }
  assert_eq "$(snap)" "$before" "no file changed"
  ! grep -E "auth login|keys set|keys forget|agent |chat setup|^gh" "$CALLS" > /dev/null || { cat "$CALLS"; fail "no writing call"; }
  for s in "claude code: installed" "sign-in: not signed in" "hub: $T/hub" "projects: 2" "channel: telegram"; do assert_contains "$T/out" "$s" "line: $s"; done
  assert_eq "$(wc -l < "$T/out" | tr -d ' ')" 5 "one line per step"
}

top_first_only_one() {   # AC8
  fresh; setup_fakes; setup_hub
  setup "1 3" 1 "" n || { cat "$T/out"; fail "exit"; }
  assert_contains "$T/out" "accepted: a number from 1 to 5" "two answers refused, and asked again (A18)"
  top_line=$(grep -n "everything agent" "$T/out" | head -1 | cut -d: -f1); focus_line=$(grep -n "focus agents" "$T/out" | head -1 | cut -d: -f1)
  [ -n "$top_line" ] && [ -n "$focus_line" ] && [ "$top_line" -lt "$focus_line" ] || fail "top asked first"
  sed -n "${top_line},${focus_line}p" "$T/out" | grep -qi gemini && fail "Gemini is not offered for the top"
  assert_eq "$(conf HUB_ROOT_PROVIDER)" anthropic "one top agent"
}

focus_multi_live_tests() {   # AC9
  fresh; setup_fakes; setup_hub; export AGENT_FAIL=deepseek
  setup 1 "1 2 3" "gem-key" "ds-key" n || { cat "$T/out"; fail "exit"; }
  for p in anthropic gemini deepseek; do grep -q "^agent --live-test $p " "$CALLS" || fail "live test $p"; done
  assert_contains "$CALLS" "task:Reply with the word READY" "the tiny task"
  grep -E "deepseek: failed .*the key was rejected \(401\)" "$T/out" > /dev/null || { cat "$T/out"; fail "reason shown"; }
  grep -E "gemini: ready" "$T/out" > /dev/null || fail "gemini ready"
  assert_eq "$(conf HUB_PROVIDERS_ALLOWED)" "anthropic gemini" "a failed provider is in no role"
}

no_gpt_or_codex() {   # AC11
  fresh; setup_fakes; setup_hub; setup 1 "" n
  ! grep -qiE "gpt|codex|openai" "$T/out" || fail "never offered"
  ! grep -qiE "gpt|codex|openai" "$ADE" || fail "not in ade either"
}

telegram_step() {   # AC12
  fresh; setup_fakes; setup_hub; setup 1 "" y "tok-123" || { cat "$T/out"; fail "exit"; }
  assert_eq "$(grep -c "Telegram?" "$T/out")" 1 "asked once"; assert_contains "$T/out" "@BotFather" "explains the bot"
  [ "$(grep -n "focus agents" "$T/out" | head -1 | cut -d: -f1)" -lt "$(grep -n "Telegram?" "$T/out" | cut -d: -f1)" ] || fail "Telegram asked after the providers"
  assert_contains "$CALLS" "keys set telegram" "token to bin/keys"; assert_contains "$CALLS" "chat setup telegram" "then bin/chat setup"
  [ "$(grep -n '^keys set telegram' "$CALLS" | cut -d: -f1)" -lt "$(grep -n '^chat setup telegram' "$CALLS" | cut -d: -f1)" ] || fail "order"
  fresh; setup_fakes; setup_hub; setup 1 "" n; ! grep -qE "^(keys set telegram|chat )" "$CALLS" || fail "no skips it"
  fresh; setup_fakes; setup_hub; printf 'y\ntok\n' | bash "$ADE" setup --telegram > "$T/out" 2>&1 || { cat "$T/out"; fail "--telegram"; }
  grep -q "^chat setup telegram" "$CALLS" || fail "--telegram runs the step"; assert_not_contains "$CALLS" "agent " "and nothing else"
  assert_not_contains "$T/out" "session pwd" "no session"
}

test_reruns() {   # AC10
  fresh; setup_fakes; setup_hub; printf 'HUB_PROVIDERS_ALLOWED="anthropic deepseek"\n' >> "$T/hub/hub.conf"
  snap() { (cd "$T" && find hub home -type f -exec cksum {} + | sort); }
  before="$(snap)"; bash "$ADE" setup --test < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "test exit"; }
  assert_eq "$(snap)" "$before" "nothing else changed"
  grep -q "anthropic: ready" "$T/out" && grep -q "deepseek: ready" "$T/out" || { cat "$T/out"; fail "each allowed provider tested"; }
  grep "^agent --live-test" "$CALLS" | while read -r l; do d="${l##*pwd=}"
    case "$d" in "$T/hub"*|"$REPO"*) fail "ran in a real checkout: $d" ;; esac; [ ! -e "$d" ] || fail "throwaway folder removed"; done || exit 1
  : > "$CALLS"; bash "$ADE" setup --test gemini < /dev/null > "$T/out" 2>&1
  assert_eq "$(grep -c '^agent --live-test' "$CALLS")" 1 "one provider"; assert_contains "$CALLS" "agent --live-test gemini" "the named one"
  bash "$ADE" setup --test telegram < /dev/null > "$T/out" 2>&1; assert_contains "$CALLS" "chat test telegram" "telegram test"
  bash "$ADE" setup --test gpt < /dev/null > "$T/out" 2>&1; assert_eq "$?" 2 "unknown provider"
}

live_test_temp_safety() {   # review 1: a failed mktemp never runs the test in, or removes, the current folder
  fresh; setup_fakes; setup_hub; mkdir -p "$T/userdir"; echo keep > "$T/userdir/file"
  printf '#!/bin/bash\nexit 1\n' > "$T/fakebin/mktemp"; chmod +x "$T/fakebin/mktemp"
  (cd "$T/userdir" && bash "$ADE" setup --test anthropic < /dev/null) > "$T/out" 2>&1; assert_eq "$?" 1 "fails"
  assert_eq "$(cat "$T/userdir/file" 2>/dev/null)" keep "the current folder survives"
  assert_contains "$T/out" "no temp folder" "says why"; assert_not_contains "$CALLS" "agent --live-test" "nothing ran"
}

exported_names_cleared() {   # review 2: SECRET or ANSWER exported by the caller never carries a typed key to a child
  fresh; setup_fakes; setup_hub; export SECRET=preset ANSWER=preset HUB_ANSWER=preset
  setup 3 "S3CRET-ds" "" n || { cat "$T/out"; fail "exit"; }
  ! grep -qE "^(SECRET|ANSWER|HUB_ANSWER)=" "$ENVS" || fail "no child env holds SECRET, ANSWER or HUB_ANSWER"
  ! grep -rq "S3CRET-ds" "$ENVS" || fail "the key in no child env"
}

ready_whole_line() {   # review 3: READY counts only as a whole line; echoing the task back is a failure
  fresh; setup_fakes; setup_hub; printf '#!/bin/bash\ncat\n' > "$T/hub/bin/agent"
  bash "$ADE" setup --test anthropic < /dev/null > "$T/out" 2>&1; assert_eq "$?" 1 "an echo of the task fails"
  assert_contains "$T/out" "anthropic: failed" "reported failed"
  printf '#!/bin/bash\ncat > /dev/null; printf "  READY\\r\\n"\n' > "$T/hub/bin/agent"
  bash "$ADE" setup --test anthropic < /dev/null > "$T/out" 2>&1 || { cat "$T/out"; fail "READY with spaces and CR is ready"; }
}

top_keeps_allowed() {   # review 6: --top makes the new top allowed and keeps the old list
  fresh; setup_fakes; setup_hub; printf 'HUB_PROVIDERS_ALLOWED="anthropic gemini"\n' >> "$T/hub/hub.conf"
  printf '3\nds-key\n' | bash "$ADE" setup --top > "$T/out" 2>&1 || { cat "$T/out"; fail "--top exit"; }
  assert_eq "$(conf HUB_PROVIDERS_ALLOWED)" "deepseek anthropic gemini" "new top plus the old list"
}

failed_asks_key_again() {   # review 8: a provider that failed its test asks for its key again when picked again
  fresh; setup_fakes; setup_hub; export AGENT_FAIL=deepseek
  printf '3\nkey-one\n3\nkey-two\n' | bash "$ADE" setup --top > "$T/out" 2>&1
  assert_eq "$(grep -c 'Paste the deepseek key' "$T/out")" 2 "asked twice"
  assert_contains "$CALLS.keystore" "deepseek=key-two" "the second key stored"
}

guided_default_mode() {   # review 9: the guided session runs in the default permission mode
  fresh; setup_fakes; setup_hub; setup 1 "" n || fail "exit"
  grep -A1 "^arg:--permission-mode" "$T/out" | tail -1 | grep -qx "arg:default" || { cat "$T/out"; fail "--permission-mode default"; }
}

other_hub_errors_pass() {   # review 10: only "no hub found" makes a new hub
  fresh; setup_fakes; mkdir -p "$T/nothub"; export ADE_HUB="$T/nothub"
  printf '1\nfresh\n' | bash "$ADE" setup > "$T/out" 2>&1; assert_eq "$?" 2 "a bad ADE_HUB is an error"
  assert_contains "$T/out" "is not a hub"; [ ! -e "$HOME/hubs" ] || fail "no hub made"
}

reasons_scrubbed() {   # review: printed failure reasons hide key-shaped strings and Telegram bot URLs; the test runs with key variables scrubbed
  fresh; setup_fakes; setup_hub; export ANTHROPIC_API_KEY=leak-ant DEEPSEEK_API_KEY=leak-ds
  printf '#!/bin/bash\nenv >> "$ENVS"; cat > /dev/null; echo "bad key sk-ant-abcdefgh12345678 at https://api.telegram.org/bot123456:ABCdefGHIjklMNO/send" >&2; exit 1\n' > "$T/hub/bin/agent"
  bash "$ADE" setup --test anthropic < /dev/null > "$T/out" 2>&1
  assert_not_contains "$T/out" "sk-ant-abcdefgh12345678" "key-shaped text hidden"; assert_not_contains "$T/out" "ABCdefGHIjklMNO" "bot token hidden"
  assert_contains "$T/out" "anthropic: failed" "still reported"
  ! grep -qE "^(ANTHROPIC_API_KEY|DEEPSEEK_API_KEY)=" "$ENVS" || fail "key variables scrubbed from the live test"
}

gemini_account() {   # review: Gemini offers its CLI's account login
  fresh; setup_fakes; setup_hub; printf '#!/bin/bash\necho "gemini $*" >> "$CALLS"\n' > "$T/fakebin/gemini"; chmod +x "$T/fakebin/gemini"; export ADE_GEMINI_CLI=gemini
  setup 1 2 a n || { cat "$T/out"; fail "exit"; }
  grep -q "^gemini" "$CALLS" || fail "the Gemini CLI login ran"; ! grep -q "keys set gemini" "$CALLS" || fail "no key stored"
  grep -q "gemini: ready" "$T/out" || fail "then live-tested"
}

hidden_on_a_pty() {   # review 5: under a real pseudo-terminal the typed token never appears in the terminal output
  fresh; setup_fakes; setup_hub
  python3 - "$ADE" "$T/pty.out" <<'PY' || fail "pty run"
import os, pty, sys, time, select
ade, outp = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", ade, "setup", "--telegram"])
buf = b""; sent = []
def pump(t=0.2):
    global buf
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 4096)
            except OSError: return False
            if not d: return False
            buf += d
    return True
deadline = time.time() + 20
while time.time() < deadline:
    if not pump(): break
    if b"Telegram? [y/N]" in buf and "y" not in sent: os.write(fd, b"y" + bytes([10])); sent.append("y")
    if b"Bot token (hidden):" in buf and "t" not in sent: os.write(fd, b"PTY-T0KEN-typed" + bytes([10])); sent.append("t")
    if b"chat ran: setup telegram" in buf: break
pump(0.5); open(outp, "wb").write(buf); os.waitpid(pid, 0)
PY
  assert_contains "$T/pty.out" "Bot token (hidden):" "the prompt was shown"; assert_contains "$CALLS.keystore" "telegram=PTY-T0KEN-typed" "the token was stored"
  assert_not_contains "$T/pty.out" "PTY-T0KEN-typed" "the token never shows on the terminal"
}

ALL="live_test_temp_safety exported_names_cleared ready_whole_line top_keeps_allowed failed_asks_key_again guided_default_mode other_hub_errors_pass reasons_scrubbed gemini_account hidden_on_a_pty installer_asks_first account_signin key_only_on_stdin glm_needs_live_check hub_when_missing guided_session check_changes_nothing top_first_only_one focus_multi_live_tests no_gpt_or_codex telegram_step test_reruns"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
