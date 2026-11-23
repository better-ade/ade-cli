#!/bin/bash
# The guide's Telegram step (ade setup --telegram, and step 6 of ade setup): the token asked once, then every step that
# is left, one at a time, to a bot that passed the hub's test, or one line saying what is left. Fakes only: a hub
# whose bin/keys, bin/chat and bin/schedule keep their state in $T/tg, a fake claude (plugin install), bun, brew and
# a curl that serves a fake bun release (bun_fakes in helpers.sh).
# ade runs with those fakes and the system's own commands ($T/sys), on a scratch HOME. Never Telegram, never a real
# claude, never a key store. SHOW_EXCHANGE=1 prints the whole run's transcript.
. "$(dirname "$0")/helpers.sh"

TOKEN="123456789:AAH-S3CRETs3cretS3CRETs3cretS3CRETs3c"
farm() {   # $T/sys: the system's commands without the ones faked here
  python3 - "$T/sys" "$(command -v python3)" "$(command -v git)" <<'PY'
import os, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
skip = set("code bun curl wget sysctl gitleaks claude gh brew apt-get apt sudo uname open xdg-open tmux yazi bat batcat glow pdftotext pdftoppm chafa "
           "security pass gpg pbcopy xclip xsel wl-copy".split())
for name, target in (("python3", sys.argv[2]), ("git", sys.argv[3])):
    os.symlink(target, os.path.join(d, name))
for src in ("/usr/bin", "/bin", "/usr/sbin", "/sbin"):
    try: names = os.listdir(src)
    except OSError: continue
    for n in names:
        p = os.path.join(d, n)
        if n not in skip and not os.path.lexists(p) and os.access(os.path.join(src, n), os.X_OK):
            os.symlink(os.path.join(src, n), p)
PY
}
# the world: $W/running (the session runs; its content follows "running" in the status line), $W/access (the policy
# when paired), $W/unlocked (the policy allowlist is not a lock: the hub's reason), $W/mode (HUB_CHAT_MODE), $W/stale
# (the mode of a session that started before the lock), $W/busy (the main agent is busy), $W/oldhub (a hub whose
# status names neither the lock nor the mode), $W/<name>.fail (a fake fails once per line of it, that line on stderr; brew prints the whole file)
world() {
  fresh; F="$T/fakebin"; W="$T/tg"; H="$T/hub"; mkdir -p "$F" "$W" "$T/cwd"; farm
  export CALLS="$T/calls" ENVS="$T/envs" FT="$T" ADE_HUB="$H" ADE_TG_WAIT=1; : > "$CALLS"; : > "$ENVS"
  printf 'fails() { [ -s "$FT/tg/$1" ] || return 1; head -1 "$FT/tg/$1" >&2; sed 1d "$FT/tg/$1" > "$FT/tg/$1.n"; mv "$FT/tg/$1.n" "$FT/tg/$1"; }\n' > "$T/fails.sh"
  make_hub "$H" acme; printf 'HUB_NAME=acme\nHUB_ROOT_PROVIDER=anthropic\n' > "$H/hub.conf"; mkdir -p "$H/projects/web"
  cat > "$H/bin/keys" <<'STUB'
#!/bin/bash
echo "keys $*" >> "$CALLS"; env >> "$ENVS"; . "$FT/fails.sh"
if [ "${1:-}" = set ]; then printf 'value for telegram-bot-token: ' >&2; IFS= read -r v; echo >&2   # as the hub's bin/secret --set does
  fails keys.fail && exit 1
  echo "$2=$v" >> "$FT/keystore"; echo "stored telegram-bot-token" >&2; exit 0; fi
[ -f "$FT/keystore" ] && sed 's/=.*/ stored telegram-bot-token/' "$FT/keystore"; exit 0
STUB
  cat > "$H/bin/chat" <<'STUB'
#!/bin/bash
echo "chat $*" >> "$CALLS"; env >> "$ENVS"; . "$FT/fails.sh"; W="$FT/tg"
case "${1:-}" in
  status) if [ -f "$W/running" ]; then echo "acme: running$(cat "$W/running") (pid 4242, since 2026-11-23T01:00Z)"; else echo "acme: stopped"; fi
    lk="not locked"
    if [ -s "$W/access" ]; then pol="$(cat "$W/access")"; [ "$pol" != allowlist ] || [ -f "$W/unlocked" ] || lk="locked to you"
      if [ -f "$W/oldhub" ]; then echo "telegram: policy $pol, groups: 0"; else echo "telegram: policy $pol, groups: 0, $lk"; fi
    else echo "telegram: not paired yet (bin/chat setup telegram)"; fi
    [ ! -f "$W/oldhub" ] || exit 0
    if [ -s "$W/mode" ]; then m="mode: $(cat "$W/mode") (HUB_CHAT_MODE)"
    elif [ "$lk" = "locked to you" ]; then m="mode: auto (telegram is locked to you; HUB_CHAT_MODE=manual in hub.conf turns it off)"
    else m="mode: manual (not locked: telegram has groups; in the session: /telegram:access policy allowlist)"; fi
    [ ! -f "$W/running" ] || [ ! -s "$W/stale" ] || m="$m; the running session is in $(cat "$W/stale"): bin/chat stop, then bin/chat start"
    echo "$m" ;;
  stop) [ -f "$W/stop.stuck" ] || rm -f "$W/running" "$W/stale"; echo "stopped (pid 4242)" ;;
  test) [ ! -f "$W/running" ] || { echo "chat: the orchestrator runs (pid 4242) and reads the bot's messages" >&2; exit 1; }
    fails test.fail && exit 1
    echo "chat: sent a test message to the paired owner; waiting up to 120 s for a reply"; echo "chat: reply received from the paired owner" ;;
  info) echo "bot @acme_bot" ;;
  setup) echo "Telegram for this hub's orchestrator (acme); token: stored. Do these once, in your own terminal:"
    echo "2. bin/keys set telegram   (paste the token at the hidden prompt; never in a chat or a file)" ;;
  *) echo "chat: ade must not run this" >&2; exit 1 ;;
esac
STUB
  printf '#!/bin/bash\necho "NAME FOLDER ROLE STATUS"; if [ -f "$FT/tg/busy" ]; then echo "main . orchestrator busy"; else echo "main . orchestrator idle"; fi\n' > "$H/bin/sessions"
  cat > "$H/bin/schedule" <<'STUB'
#!/bin/bash
echo "schedule $*" >> "$CALLS"; env >> "$ENVS"; . "$FT/fails.sh"; fails schedule.fail && exit 1
if grep -q '^HUB_CHAT=telegram$' "$HUB/hub.conf" && [ ! -f "$FT/tg/service.down" ]; then : > "$FT/tg/running"; fi
echo "installed ai.agent-hub.acme.chat"
STUB
  cat > "$F/claude" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$CALLS"; env >> "$ENVS"; . "$FT/fails.sh"
if [ "$1 $2" = "plugin install" ]; then fails plugin.fail && exit 1; [ ! -f "$FT/tg/plugin.noop" ] || exit 0
  mkdir -p "$HOME/.claude/plugins"
  echo '{"version": 2, "plugins": {"telegram@claude-plugins-official": [{"scope": "user", "version": "0.0.6"}]}}' > "$HOME/.claude/plugins/installed_plugins.json"
  echo "Successfully installed plugin: telegram@claude-plugins-official (scope: user)"; fi
exit 0
STUB
  # brew: $W/brew.fail is the installer's whole message for one failed run; it is never asked for bun
  cat > "$F/brew" <<'STUB'
#!/bin/bash
echo "brew $*" >> "$CALLS"
if [ -s "$FT/tg/brew.fail" ]; then cat "$FT/tg/brew.fail" >&2; rm -f "$FT/tg/brew.fail"; exit 1; fi
for t in "$@"; do case "$t" in gitleaks) printf '#!/bin/bash\nexit 0\n' > "$FT/fakebin/$t"; chmod +x "$FT/fakebin/$t" ;; esac; done
echo "==> Pouring ${*: -1}"
STUB
  printf '#!/bin/bash\nif [ $# -eq 0 ] || [ "$1" = -s ]; then echo "${FAKE_OS:-Darwin}"; else exec "%s" "$@"; fi\n' "$(command -v uname)" > "$F/uname"
  local c; for c in bun tmux gh gitleaks yazi bat glow pdftotext pdftoppm chafa code; do printf '#!/bin/bash\nexit 0\n' > "$F/$c"; done
  chmod +x "$F"/* "$H/bin/"*; bun_fakes
}
plugin_there() { mkdir -p "$HOME/.claude/plugins"; echo '{"plugins": {"telegram@claude-plugins-official": [{"scope": "user", "version": "0.0.6"}]}}' > "$HOME/.claude/plugins/installed_plugins.json"; }
token_there() { echo "telegram=$TOKEN" > "$T/keystore"; }
# talk <keys> [args]: ade on an 80-column terminal, typed as a person types: each line of <keys> is sent when ade waits
# at a prompt (the screen ends in a space and is quiet); a line "!<command>" is what the person does elsewhere (in
# Telegram, in the other window) before pressing Enter; then end of input. The screen goes to $T/out.
talk() {
  local k="$1"; shift
  (cd "$T/cwd" && python3 -c '
import os, pty, select, sys, time
keys = sys.argv[1].encode().decode("unicode_escape").split("\n")[:-1]
pid, fd = pty.fork()
if pid == 0: os.execvp(sys.argv[2], sys.argv[2:])
out, last, sent, end = b"", time.time(), -1, time.time() + 90
while time.time() < end:
    if select.select([fd], [], [], 0.05)[0]:
        try: d = os.read(fd, 4096)
        except OSError: break
        if not d: break
        out += d; last = time.time(); continue
    if out.endswith(b" ") and time.time() - last > 0.2 and sent != len(out):
        sent = len(out)
        if not keys: os.write(fd, b"\x04"); continue
        k = keys.pop(0)
        if k.startswith("!"): os.system(k[1:]); k = ""
        os.write(fd, (k + "\n").encode())
sys.stdout.write(out.decode("utf-8", "replace").replace("\r", ""))
_, st = os.waitpid(pid, 0); sys.exit(os.WEXITSTATUS(st) if os.WIFEXITED(st) else 1)' "$k" env PATH="$F:$T/sys" COLUMNS=80 LINES=24 "$BASH" "$ADE" "$@") > "$T/out" 2>&1
}
A() { (cd "$T/cwd" && PATH="$F:$T/sys" "$BASH" "$ADE" "$@") > "$T/out" 2>&1; }   # without a terminal; answers on stdin
last_line() { grep -v '^[[:space:]]*$' "$T/out" | tail -1; }
fits() { local l; while IFS= read -r l; do l="${l%%]: *}"; [ "${#l}" -le 80 ] || fail "wider than 80 columns: [$l]"; done < <(sed "s#$T#<T>#g" "$T/out"); }
did() { grep -vE '^(keys ?|chat status|chat info.*)$' "$CALLS" | tr '\n' ';'; }   # what ade ran, without what only reads
no_wall() { assert_not_contains "$T/out" "Do these once" "never the hub's list of every step"; ! grep -q "^chat setup" "$CALLS" || fail "bin/chat setup is never run"
  ! grep -q "^chat start" "$CALLS" || fail "ade never starts the session for the person"; }
no_token() {   # the token is in the fake key store and nowhere else: no screen, argument log or environment log
  local hits; hits="$(grep -rl "S3CRET" "$T" | grep -v "/keystore$")"; assert_eq "$hits" "" "no screen, argument or environment holds the token"; }
# the person, in the other window and in Telegram
person() { START="!: > $W/running"; PAIR="!echo pairing > $W/access"; LOCK="!echo allowlist > $W/access"; }

tg_token_asked_once() {   # 1: one hidden prompt; the hub's own prompt and its "stored" line are not shown
  world; person; talk "y\n$TOKEN\nlater\n" setup --telegram; rc=$?
  assert_eq "$(grep -c 'Bot token (hidden; Enter skips):' "$T/out")" 1 "one prompt for the token"
  assert_not_contains "$T/out" "value for telegram-bot-token" "the hub's prompt is not a second one"
  assert_not_contains "$T/out" "stored telegram-bot-token" "nor its own line"
  assert_eq "$(cat "$T/keystore")" "telegram=$TOKEN" "the token reached bin/keys set telegram on stdin"
  assert_eq "$(grep -c '^keys set telegram' "$CALLS")" 1 "stored once"; assert_contains "$T/out" "checked: the token is in the hub's key store" "checked after"
  assert_contains "$HOME/.config/ade/keys-set" "telegram" "noted for ade reset --keys (the name only)"
  no_token; no_wall; assert_eq "$rc" 0 "later: the step ends"
  world; talk "y\n\n" setup --telegram; assert_eq "$(last_line)" "Telegram skipped (no token; later: ade setup --telegram)" "Enter at the token skips"
  [ ! -e "$T/keystore" ] || fail "nothing stored"
  world; talk "n\n" setup --telegram
  assert_eq "$(last_line)" "Telegram skipped (later: ade setup --telegram)" "no skips it"; assert_not_contains "$CALLS" "keys set" "and stores nothing"
  world; person; echo "could not store telegram-bot-token in the Keychain" > "$W/keys.fail"; talk "y\n$TOKEN\n\n$TOKEN\nlater\n" setup --telegram
  assert_contains "$T/out" "The token was not stored: could not store telegram-bot-token in the Keychain" "a store that fails: one plain line"
  for s in "  1) token  enter the token again" "  2) later  finish Telegram later" "  3) stop   stop here" "What now? [token]:"; do assert_contains "$T/out" "$s" "$s"; done
  assert_eq "$(grep -c 'Bot token (hidden' "$T/out")" 2 "asked again only after it failed"; assert_eq "$(cat "$T/keystore")" "telegram=$TOKEN" "then stored"
  no_token; fits
  world; echo "x" > "$W/keys.fail"; talk "y\n$TOKEN\nlater\n" setup --telegram
  assert_eq "$(last_line)" "Telegram is not finished: enter your bot's token, then ade setup --telegram" "later, with no token stored"
}

tg_full_run() {   # 2, 4: every step, to a bot that passed the test; the one ending line
  world; person; rm "$F/bun"
  talk "y\n$TOKEN\ny\n$START\n$PAIR\n$LOCK\n" setup --telegram; rc=$?
  [ -z "${SHOW_EXCHANGE:-}" ] || sed "s#$T#<T>#g" "$T/out" >&2
  assert_eq "$rc" 0 "it finished"; assert_eq "$(last_line)" "Telegram is working: your bot passed its test, and its session is running." "the ending"
  for s in "Next: bun, the program the Telegram plugin runs on." "checked: bun is installed" \
    "Next: the Telegram plugin for Claude Code, installed for your user." "checked: the Telegram plugin is installed" \
    "checked: the session is running, with your bot connected" "checked: your Telegram account is paired" "checked: only your account reaches the bot" \
    "Next: closing the session in your other window, so the hub can test the bot." "Next: the test. Your bot sends you a message in Telegram: reply to it with" \
    "checked: your bot's message reached you, and your reply reached the hub" \
    "Next: your hub keeps the session with your bot running, in the background." "checked: the session is running in the background"; do
    assert_contains "$T/out" "$s" "said or checked: $s"; done
  assert_contains "$T/out" "Install bun now? [y/N]" "bun, missing all the same: asked first, as ade setup --tools asks"
  assert_contains "$T/out" "installed: bun $BUN_V in ~/.bun/bin/bun" "and installed the same way"; [ -x "$HOME/.bun/bin/bun" ] || fail "where the hub's bin/chat finds it"
  assert_eq "$(did)" "keys set telegram;curl $BUN_URL/bun-darwin-aarch64.zip;curl $BUN_URL/SHASUMS256.txt;claude plugin install telegram@claude-plugins-official --scope user;chat stop;chat test telegram;schedule install;" "what ade ran, in order"
  assert_eq "$(grep -c '^HUB_CHAT=telegram$' "$H/hub.conf")" 1 "HUB_CHAT=telegram in hub.conf"
  [ "$(grep -n '^HUB_CHAT' "$H/hub.conf" | wc -l | tr -d ' ')" = 1 ] || fail "written once"
  grep -q '"bot": "@acme_bot"' "$H/.ade/connections.json" || fail "the channel is recorded with the bot's public name"
  no_token; no_wall; fits
  assert_eq "$(grep -c 'Your turn' "$T/out")" 3 "three steps for the person, each shown once"
  A setup --check < /dev/null; assert_eq "$(grep '^telegram:' "$T/out")" "telegram: on (auto)" "ade setup --check: on, and the mode"
  A < /dev/null; assert_contains "$T/out" "telegram: on (auto)" "ade alone: on, and the mode"
  : > "$CALLS"; A setup --telegram < /dev/null; assert_eq "$?" 0 "run again, finished"
  assert_eq "$(cat "$T/out")" "Telegram is working: your bot passed its test, and its session is running." "nothing asked or shown again, the one line"
  ! grep -qE "^(keys set|brew|curl|claude|chat (stop|test)|schedule)" "$CALLS" || fail "and nothing done again"
}

tg_one_step_at_a_time() {   # 3: a step for the person is alone on the screen, waited for, then checked
  world; person; token_there; plugin_there
  talk "\n\nlater\n" setup --telegram; rc=$?; assert_eq "$rc" 0 "later ends the step"
  for s in "Your turn: open a second terminal window (keep this one open) and type:" "  cd $H && bin/chat start" "Press Enter when done (or type later):"; do assert_contains "$T/out" "$s" "the step: $s"; done
  assert_not_contains "$T/out" "/telegram:access" "the next steps are not on the screen yet"
  assert_contains "$T/out" "The session with your bot is not running yet" "Enter with nothing done: checked, and said"
  assert_contains "$T/out" "details: the hub's own words: ade chat status" "where"
  for s in "  1) again  show the step again" "  2) later  finish Telegram later" "  3) stop   stop here" "What now? [again]:"; do assert_contains "$T/out" "$s" "$s"; done
  assert_eq "$(grep -c 'Your turn: open a second terminal' "$T/out")" 2 "again shows that step again"
  assert_eq "$(last_line)" "Telegram is not finished: start your bot's session, then ade setup --telegram" "the ending names the one thing left"
  no_wall; fits
  echo ", channel not connected" > "$W/running"; talk "\nlater\n" setup --telegram
  assert_contains "$T/out" "The session runs, but your bot has not connected to it yet" "running without the bot is not done"
  : > "$W/running"; talk "\n$PAIR\n\n\nstop\n" setup --telegram; rc=$?
  assert_not_contains "$T/out" "second terminal" "the session runs: that step is not shown"
  assert_contains "$T/out" "Your Telegram account is not paired yet" "the pairing is checked"
  assert_contains "$T/out" "  /telegram:access pair <code>" "the exact text"; assert_contains "$T/out" "checked: your Telegram account is paired" "then checked"
  assert_contains "$T/out" "  /telegram:access policy allowlist" "then the next step, alone"
  assert_contains "$T/out" "The bot is not locked to your account yet (now: pairing)" "and checked"
  assert_eq "$rc" 1 "stop: exit 1"; assert_eq "$(last_line)" "ade: stopped; to come back, run ade setup --telegram" "and how to come back"
  [ "$(grep -n 'access pair' "$T/out" | head -1 | cut -d: -f1)" -lt "$(grep -n 'checked: your Telegram account is paired' "$T/out" | cut -d: -f1)" ] || fail "order"
  [ "$(grep -n 'checked: your Telegram account is paired' "$T/out" | cut -d: -f1)" -lt "$(grep -n 'policy allowlist' "$T/out" | head -1 | cut -d: -f1)" ] || fail "one step, then the next"
  talk "" setup --telegram; assert_eq "$?" 1 "the end of input stops"; assert_eq "$(last_line | sed 's/^Press Enter when done (or type later): *//')" "ade: stopped (no answer); to come back, run ade setup --telegram" "with the line"
  (export CLAUDECODE=1; A setup --telegram < /dev/null); assert_contains "$T/out" "The next step is for a person, at a terminal; an agent cannot do it." "an agent session is told so"
  assert_eq "$(last_line)" "Telegram is not finished: allow only your account, then ade setup --telegram" "and how it stands"
  mkdir -p "$T/my hub"; mv "$H" "$T/my hub/h"; export ADE_HUB="$T/my hub/h"; rm -f "$W/running" "$W/access"; talk "later\n" setup --telegram
  assert_contains "$T/out" "  cd '$T/my hub/h' && bin/chat start" "a hub path with a space is quoted"
}

tg_resumes() {   # 5: run again, it starts at the first thing not done and shows nothing that is done
  world; person; rm "$F/bun"
  talk "y\n$TOKEN\ny\n$START\nlater\n" setup --telegram; assert_eq "$(last_line)" "Telegram is not finished: pair your Telegram account, then ade setup --telegram" "later, typed at the wait"
  assert_contains "$T/out" "Your turn: in Telegram, send your bot any message" "it stopped at the pairing"
  : > "$CALLS"; talk "$PAIR\n$LOCK\n" setup --telegram; rc=$?; assert_eq "$rc" 0 "the second run finishes"
  for s in "Do you want to reach" "Bot token" "BotFather" "bun" "the Telegram plugin" "second terminal"; do assert_not_contains "$T/out" "$s" "not shown again: $s"; done
  head -1 "$T/out" > "$T/first"; assert_contains "$T/first" "Your turn: in Telegram, send your bot any message. It replies with a pairing" "it starts at the first thing not done"
  ! grep -qE "^(keys set|brew|curl|claude)" "$CALLS" || fail "nothing done again"
  assert_eq "$(last_line)" "Telegram is working: your bot passed its test, and its session is running." "and ends working"
  rm "$W/running"; A setup --check < /dev/null; assert_contains "$T/out" "telegram: not finished: start it in the background (ade setup --telegram)" "a session that stopped: not finished"
  : > "$CALLS"; A setup --telegram < /dev/null; assert_eq "$(did)" "schedule install;" "the run after starts it again, and only that"
  assert_eq "$(last_line)" "Telegram is working: your bot passed its test, and its session is running." "working again"
}

tg_states() {   # 4: ade setup --check, ade alone and the guide's list say on, not finished or off
  world; A setup --check < /dev/null; assert_contains "$T/out" "telegram: off" "nothing begun: off"
  A < /dev/null; assert_contains "$T/out" "telegram: off" "ade alone: off"
  A setup < /dev/null; grep -E '\[ \] 6\. Telegram \(optional\) +off' "$T/out" > /dev/null || { cat "$T/out"; fail "the guide's list: off"; }
  assert_contains "$T/out" "All set" "an optional step that was never begun is not offered"; assert_not_contains "$T/out" "Step 6" "nor run"
  token_there; plugin_there; A setup --check < /dev/null
  assert_contains "$T/out" "telegram: not finished: start your bot's session (ade setup --telegram)" "begun: not finished, and what is left"
  A < /dev/null; assert_contains "$T/out" "telegram: not finished: start your bot's session (ade setup --telegram)" "ade alone"
  snap() { (cd "$T" && find hub home -type f -exec cksum {} + | sort); }; before="$(snap)"; A setup --check < /dev/null; assert_eq "$(snap)" "$before" "the check writes nothing"
  ! grep -qE "^(keys set|chat (stop|test|start|setup)|schedule|claude plugin install)" "$CALLS" || fail "and runs nothing that changes"
  person; talk "$START\n$PAIR\n$LOCK\n" setup; rc=$?   # the guide picks a begun Telegram step up, with nothing else left
  grep -E "\[ \] 6\. Telegram \(optional\) +not finished: start your bot's session" "$T/out" > /dev/null || { cat "$T/out"; fail "the guide's list: not finished"; }
  assert_contains "$T/out" "Step 6 of 6: Telegram (optional)" "the guide comes back to it"; assert_not_contains "$T/out" "Do you want to reach" "without asking again"
  assert_contains "$T/out" "Telegram is working: your bot passed its test, and its session is running." "to the end"
  assert_contains "$T/out" "checked: Telegram is on" "checked"; assert_eq "$rc" 0 "exit 0"; fits
  A setup < /dev/null; grep -E '\[x\] 6\. Telegram \(optional\) +on' "$T/out" > /dev/null || fail "the guide's list: on"
  world; token_there; plugin_there; talk "later\n" setup
  assert_contains "$T/out" "checked: Telegram is not finished; ade setup --telegram comes back to it" "the guide's check line"; assert_contains "$T/out" "All set" "the guide still ends"
}

tg_lock_then_auto() {   # never "working" before the bot is locked to the person; then what auto mode means, and the mode shown
  local AUTO="The chat now runs in auto mode: your main agent acts on your Telegram"
  line_of() { grep -nF -- "$1" "$T/out" | head -1 | cut -d: -f1; }
  # the full run: the one line to type, waited for, checked by the hub's own status, then the mode
  world; person; token_there; plugin_there
  talk "$START\n$PAIR\n$LOCK\n" setup --telegram; rc=$?; assert_eq "$rc" 0 "it finished"
  [ -z "${SHOW_EXCHANGE:-}" ] || sed "s#$T#<T>#g" "$T/out" >&2
  for s in "Your turn: in the same Claude Code window, type:" "  /telegram:access policy allowlist" \
    "After this, only your Telegram account reaches your main agent, and the" "chat can run in auto mode (no questions at the terminal)." \
    "checked: only your account reaches the bot" "$AUTO" "messages without asking at the terminal. Claude Code's auto mode still refuses" \
    "risky actions. To turn it off: HUB_CHAT_MODE=manual in hub.conf."; do assert_contains "$T/out" "$s" "the lock exchange: $s"; done
  [ "$(line_of "checked: only your account reaches the bot")" -lt "$(line_of "Next: the test.")" ] || fail "locked before the test"
  [ "$(line_of "checked: the session is running in the background")" -lt "$(line_of "$AUTO")" ] || fail "the mode is said once the new session runs"
  assert_eq "$(last_line)" "Telegram is working: your bot passed its test, and its session is running." "the ending"; fits; no_wall
  # the policy allowlist alone is not the lock: the hub says whether only the person gets in
  world; person; token_there; plugin_there; : > "$W/running"; echo allowlist > "$W/access"; : > "$W/unlocked"
  A setup --check < /dev/null; assert_contains "$T/out" "telegram: not finished: allow only your account (ade setup --telegram)" "an allowlist that is not a lock: not finished"
  talk "\nlater\n" setup --telegram
  assert_contains "$T/out" "  /telegram:access policy allowlist" "the lock step is shown"
  assert_contains "$T/out" "The bot is not locked to your account alone yet (policy allowlist, not locked)" "Enter with no lock: checked with the hub, and said"
  assert_eq "$(last_line)" "Telegram is not finished: allow only your account, then ade setup --telegram" "not working until locked"
  assert_not_contains "$CALLS" "chat test" "no test before the lock"; assert_not_contains "$H/hub.conf" "HUB_CHAT" "and nothing switched on"
  assert_not_contains "$T/out" "auto mode:" "no word of auto mode before the lock"
  talk "!rm $W/unlocked\n" setup --telegram; assert_eq "$?" 0 "locked: to the end"
  assert_contains "$T/out" "$AUTO" "then auto mode is explained"; assert_eq "$(last_line)" "Telegram is working: your bot passed its test, and its session is running." "working"
  # a bot that is on but no longer locked: on, in manual mode, said so; ade setup --telegram offers the lock, then
  # restarts the session (it started before the lock) when the main agent is idle
  world; person; token_there; plugin_there; : > "$W/running"; echo allowlist > "$W/access"; : > "$W/unlocked"; echo HUB_CHAT=telegram >> "$H/hub.conf"
  A setup --check < /dev/null; assert_eq "$(grep '^telegram:' "$T/out")" "telegram: on (manual: not locked)" "on, manual: not locked"
  : > "$CALLS"; talk "!rm $W/unlocked; echo manual > $W/stale\n" setup --telegram; rc=$?; assert_eq "$rc" 0 "locked and restarted"
  assert_contains "$T/out" "checked: only your account reaches the bot" "the lock is checked"
  assert_contains "$T/out" "Next: restarting the session with your bot, so it runs in auto mode." "said before"
  assert_contains "$T/out" "checked: the session is running again, in auto mode" "checked after"
  assert_eq "$(did)" "chat stop;schedule install;" "the restart: the hub's own stop, then its schedule"
  assert_contains "$T/out" "$AUTO" "and what auto mode means"; assert_eq "$(last_line)" "Telegram is working: your bot passed its test, and its session is running." "working"; fits
  A setup --check < /dev/null; assert_eq "$(grep '^telegram:' "$T/out")" "telegram: on (auto)" "then on (auto)"
  # a busy main agent is never interrupted: the person is told exactly how
  echo manual > "$W/stale"; : > "$W/busy"; : > "$CALLS"
  A setup --check < /dev/null; assert_eq "$(grep '^telegram:' "$T/out")" "telegram: on (manual: restart for auto, ade setup --telegram)" "a session from before the lock"
  A setup --telegram < /dev/null; assert_eq "$?" 0 "busy: the step ends"
  assert_contains "$T/out" "busy, so ade does not restart it. When it is idle, type:" "said"; assert_contains "$T/out" "  ade chat stop && ade setup --telegram" "exactly how"
  assert_not_contains "$CALLS" "chat stop" "not stopped"; assert_not_contains "$CALLS" "schedule" "nor restarted"
  assert_not_contains "$T/out" "Telegram is working" "and not called working in the new mode"; fits
  # a restart that does not come back is said, never believed
  rm "$W/busy"; touch "$W/service.down"; A setup --telegram < /dev/null
  assert_contains "$T/out" "The session did not restart" "a restart that fails"; assert_not_contains "$T/out" "auto mode:" "no auto line then"
  # HUB_CHAT_MODE in hub.conf is the person's own choice: shown, never argued with
  world; token_there; plugin_there; : > "$W/running"; echo allowlist > "$W/access"; echo HUB_CHAT=telegram >> "$H/hub.conf"; echo manual > "$W/mode"
  A setup --check < /dev/null; assert_eq "$(grep '^telegram:' "$T/out")" "telegram: on (manual)" "HUB_CHAT_MODE=manual"
  echo plan > "$W/mode"; A < /dev/null; assert_contains "$T/out" "telegram: on (plan)" "ade alone, another mode"
  A setup --telegram < /dev/null; assert_eq "$(cat "$T/out")" "Telegram is working: your bot passed its test, and its session is running." "run again: the one line"
  world; person; token_there; plugin_there; echo manual > "$W/mode"; talk "$START\n$PAIR\n$LOCK\n" setup --telegram
  assert_contains "$T/out" "The chat runs in manual mode (HUB_CHAT_MODE in hub.conf)." "a run with HUB_CHAT_MODE set says that mode"; assert_not_contains "$T/out" "auto mode:" "not auto"
  # a hub whose status names neither the lock nor the mode (an older one): as before
  world; person; token_there; plugin_there; : > "$W/oldhub"; talk "$START\n$PAIR\n$LOCK\n" setup --telegram; assert_eq "$?" 0 "an older hub finishes"
  assert_not_contains "$T/out" "auto mode:" "no mode is claimed for it"; assert_eq "$(last_line)" "Telegram is working: your bot passed its test, and its session is running." "working"
  A setup --check < /dev/null; assert_eq "$(grep '^telegram:' "$T/out")" "telegram: on" "and its line names no mode"
  ! grep -rqE "access\.json" "$CALLS" || fail "ade never reads access.json itself"
}

tg_steps_fail() {   # 2: each step ade does goes through the shared failure function
  world; person; token_there; : > "$W/running"; echo allowlist > "$W/access"
  echo "Error: marketplace not reachable" > "$W/plugin.fail"; echo "chat: the test message was not sent: Unauthorized" > "$W/test.fail"; echo "schedule: launchctl refused" > "$W/schedule.fail"
  talk "\n\n\n" setup --telegram; rc=$?; assert_eq "$rc" 0 "try again, three times, to the end"
  assert_contains "$T/out" "The Telegram plugin was not installed: Error: marketplace not reachable" "the plugin: one plain line"
  assert_contains "$T/out" "details: ~/.config/ade/last-failure" "where"; grep -q "launchctl refused" "$HOME/.config/ade/last-failure" || fail "the tool's own text is kept there (the last one that failed)"
  for s in "  1) retry  try again" "  2) later  finish Telegram later" "  3) stop   stop here" "What now? [retry]:"; do assert_contains "$T/out" "$s" "$s"; done
  assert_contains "$T/out" "The test did not pass: the test message was not sent: Unauthorized" "the test: the hub's own reason"
  assert_contains "$T/out" "details: ade setup --test telegram runs it alone" "where"
  assert_contains "$T/out" "The background session has not started: schedule: launchctl refused" "the schedule"
  assert_contains "$T/out" "details: ade chat logs shows the hub's own lines" "where"
  assert_eq "$(last_line)" "Telegram is working: your bot passed its test, and its session is running." "then working"; fits
  assert_eq "$(grep -c '^claude plugin install' "$CALLS")" 2 "the plugin: tried again"; assert_eq "$(grep -c '^chat test' "$CALLS")" 2 "the test: sent again"
  world; token_there; touch "$W/plugin.noop"; talk "later\n" setup --telegram
  assert_contains "$T/out" "Claude Code does not list the Telegram plugin as installed" "an install that installs nothing is checked, not believed"
  assert_eq "$(last_line)" "Telegram is not finished: install the Telegram plugin, then ade setup --telegram" "later"
  world; token_there; plugin_there; : > "$W/running"; echo allowlist > "$W/access"; echo "chat: no reply within 120 s" > "$W/test.fail"; talk "later\n" setup --telegram
  assert_contains "$T/out" "The test did not pass: no reply within 120 s" "no reply"
  assert_eq "$(last_line)" "Telegram is not finished: pass the bot's test, then ade setup --telegram" "never working without the test"
  assert_not_contains "$H/hub.conf" "HUB_CHAT" "HUB_CHAT is not set before the test passed"; assert_not_contains "$CALLS" "schedule" "nor the schedule installed"
  A setup --check < /dev/null; assert_contains "$T/out" "telegram: not finished: pass the bot's test" "and the state says so"
  : > "$W/running"; touch "$W/stop.stuck"; : > "$CALLS"; talk "later\n" setup --telegram; assert_contains "$T/out" "The session in your other window is still running" "a session that does not close"
  assert_not_contains "$CALLS" "chat test" "no test while it runs"
  rm "$W/stop.stuck" "$W/running"; touch "$W/service.down"; talk "stop\n" setup --telegram; assert_eq "$?" 1 "stop"
  assert_contains "$T/out" "The background session has not started" "a schedule that starts nothing: checked with bin/chat status"
  A setup --check < /dev/null; assert_contains "$T/out" "telegram: not finished: start it in the background" "the state"
}

tg_bun_fails() {   # bun missing at the Telegram step all the same: offered the same way (its release, never Homebrew), and the choices
  world; person; token_there; plugin_there; rm "$F/bun"; printf 'curl: (6) Could not resolve host: github.com\n' > "$T/curl.fail"
  talk "y\nmanual\n" setup --telegram; rc=$?
  assert_contains "$T/out" "Next: bun, the program the Telegram plugin runs on." "the step is said"
  assert_contains "$T/out" "The download of bun $BUN_V did not finish" "a download that fails: one plain line"
  assert_contains "$T/out" "details: curl: (6) Could not resolve host: github.com" "where"
  for s in "  1) retry   try again" "  2) manual  show the manual steps" "  3) later   skip Telegram for now" "  4) stop    stop here" "What now? [retry]:"; do assert_contains "$T/out" "$s" "$s"; done
  assert_contains "$T/out" "To install bun $BUN_V yourself:" "manual"; assert_contains "$T/out" "     download bun-darwin-aarch64.zip and SHASUMS256.txt" "the steps, shown and not run"
  assert_not_contains "$T/out" "| bash" "no script piped to a shell"
  assert_eq "$(last_line)" "Telegram is not finished: install bun, then ade setup --telegram" "the ending"; assert_eq "$rc" 0 "the step ended"; fits
  assert_eq "$(did)" "curl $BUN_URL/bun-darwin-aarch64.zip;" "ade tried the download and nothing else: no brew, no softwareupdate"
  printf 'curl: (28) Operation timed out\n' > "$T/curl.fail"; : > "$CALLS"; talk "y\n\n$START\n$PAIR\n$LOCK\n" setup --telegram; rc=$?
  assert_eq "$(grep -c '^curl ' "$CALLS")" 3 "try again downloads again, with no second question"; assert_eq "$(grep -c 'Install bun now' "$T/out")" 1 "asked once"
  assert_contains "$T/out" "checked: bun is installed" "checked"; assert_not_contains "$CALLS" "brew" "never Homebrew"
  assert_eq "$(last_line)" "Telegram is working: your bot passed its test, and its session is running." "and on to the end"; assert_eq "$rc" 0 "exit 0"
  world; token_there; rm "$F/bun"; sed 's/^[0-9a-f]\{8\}/deadbeef/' "$BUN_REL/SHASUMS256.txt" > "$T/s"; cp "$T/s" "$BUN_REL/SHASUMS256.txt"; talk "y\nlater\n" setup --telegram
  assert_contains "$T/out" "bun-darwin-aarch64.zip does not match its sha256; nothing installed" "a sha256 that does not match"; [ ! -e "$HOME/.bun" ] || fail "installs nothing"
  assert_eq "$(last_line)" "Telegram is not finished: install bun, then ade setup --telegram" "skip for now"
  world; token_there; rm "$F/bun"; talk "n\nstop\n" setup --telegram; assert_eq "$?" 1 "stop"
  assert_contains "$T/out" "bun is not installed yet; the Telegram plugin runs on it" "a no to the install"; assert_contains "$T/out" "details: ade setup --tools installs it too" "where"
  assert_not_contains "$CALLS" "curl" "nothing downloaded without a yes"; assert_not_contains "$CALLS" "brew" "and no Homebrew"
  world; token_there; rm "$F/bun"; talk "n\nmanual\n" setup --telegram; assert_contains "$T/out" "To install bun $BUN_V yourself:" "a no, then the manual steps"
  assert_contains "$T/out" "then run ade setup --telegram" "and how to come back"
  world; token_there; rm "$F/bun"; printf '#!/bin/bash\necho "apt-get $*" >> "$CALLS"\n' > "$F/apt-get"; chmod +x "$F/apt-get"
  FAKE_OS=Linux FAKE_CPU=x86_64 talk "y\nlater\n" setup --telegram; assert_contains "$CALLS" "curl $BUN_URL/bun-linux-x64.zip" "Linux: the same way, its own zip"
  assert_contains "$T/out" "checked: bun is installed" "installed"; assert_not_contains "$CALLS" "apt-get" "and apt is not asked for it"
  world; token_there; rm "$F/bun"; mkdir -p "$HOME/.bun/bin"; printf '#!/bin/bash\n' > "$HOME/.bun/bin/bun"; chmod +x "$HOME/.bun/bin/bun"; A setup --check < /dev/null
  assert_contains "$T/out" "telegram: not finished: install the Telegram plugin" "a bun already in ~/.bun/bin counts"
}

tools_report_brew_failures() {   # the same two failures in ade setup --tools, and gitleaks among the required tools
  world; rm "$F/gitleaks" "$F/tmux"
  talk "y\n" setup --tools; assert_contains "$CALLS" "brew install tmux gitleaks" "gitleaks is a required tool, installed with the others after a yes"
  assert_contains "$T/out" "missing tools ade needs: tmux gitleaks" "named"; [ -x "$F/gitleaks" ] || fail "installed"
  A doctor < /dev/null; assert_contains "$T/out" "gitleaks installed" "ade doctor lists it"
  cp "$F/gh" "$F/tmux"; rm "$F/gitleaks"; A doctor < /dev/null; assert_contains "$T/out" "gitleaks missing (required: the hub's secret scan before each save)" "and why"
  printf 'Error: Your Command Line Tools are too outdated.\nYou should download the Command Line Tools for Xcode 26.6.\n' > "$W/brew.fail"
  talk "y\n" setup --tools; assert_eq "$(last_line)" "Homebrew needs newer Command Line Tools: run softwareupdate --install -a" "Command Line Tools: the same plain line"
  printf 'Warning: The following taps are not trusted:\n  some/tap\nHomebrew is currently ignoring formulae because tap trust is required.\nError: failed\n' > "$W/brew.fail"
  talk "y\n" setup --tools; assert_eq "$(last_line)" "Homebrew does not trust the gitleaks tap yet" "a tap that is not trusted: the same plain line"
  rm "$F/tmux"; printf 'tap trust is required\n' > "$W/brew.fail"; talk "y\n" setup --tools
  assert_eq "$(last_line)" "Homebrew does not trust one of its taps yet (see brew trust)" "several packages: no tap is guessed"
  assert_not_contains "$CALLS" "trust" "ade never runs brew trust"; fits
  printf '#!/bin/bash\necho "apt-get $*" >> "$CALLS"\n' > "$F/apt-get"; printf '#!/bin/bash\n"$@"\n' > "$F/sudo"; chmod +x "$F/apt-get" "$F/sudo"; : > "$CALLS"
  FAKE_OS=Linux talk "y\n" setup --tools required; grep -qE "^apt-get install -y tmux gitleaks$" "$CALLS" || { cat "$CALLS" "$T/out"; fail "apt has gitleaks (Ubuntu 24.04)"; }
}

ALL="tg_token_asked_once tg_full_run tg_lock_then_auto tg_one_step_at_a_time tg_resumes tg_states tg_steps_fail tg_bun_fails tools_report_brew_failures"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
