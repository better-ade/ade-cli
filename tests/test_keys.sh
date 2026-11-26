#!/bin/bash
# story A26: `ade keys` sets the missing keys for you. A fake hub whose bin/keys logs its arguments and the length of
# its stdin only; a stored value goes to the fake store ($T/store) and nowhere else. Terminals are pty_run's.
. "$(dirname "$0")/helpers.sh"

keys_hub() {   # a hub at $H; the store starts with the tools named; $T/fail.<tool>: that tool's set fails
  H="$T/hub"; make_hub "$H" hub; export ADE_HUB="$H" KT="$T"; : > "$T/store"; : > "$T/log"; local t
  for t in "$@"; do echo "$t=already-there" >> "$T/store"; done
  cat > "$H/bin/keys" <<'STUB'
#!/bin/bash
echo "keys $*" >> "$KT/log"
if [ "${1:-}" = set ] && [ $# -eq 2 ]; then IFS= read -r v; echo "stdin $2 ${#v}" >> "$KT/log"
  env >> "$KT/envs"; ps -A -ww -o args= 2> /dev/null | grep -v "pty.fork" >> "$KT/ps"   # the test harness typing the input is not ade
  printf 'value for %s: ' "$2"   # the real hub's prompt, written even when the value comes on stdin
  # a hostile failure: the hub repeats the value it was given
  if [ -f "$KT/fail.$2" ]; then echo "keys: the store refused $v" >&2; exit 1; fi
  echo "$2=$v" >> "$KT/store"; echo "keys: stored"; exit 0; fi
[ $# -eq 0 ] || exit 0
for t in anthropic deepseek glm muse gemini telegram; do
  if grep -q "^$t=" "$KT/store"; then printf '%-10s %-8s %s\n' "$t" stored "$t-key"; echo "  ready for bin/agent"
  else printf '%-10s %-8s %s\n' "$t" missing "$t-key"; echo "  set it: bin/keys set $t"; fi
done
STUB
  chmod +x "$H/bin/keys"
}
stored() { grep -qxF "$1" "$T/store"; }
lists() { grep -c '^anthropic ' "$T/out" | tr -d ' '; }   # how many times the hub's list was shown

keys_guided_yes() {   # AC1
  fresh; keys_hub anthropic muse gemini telegram
  pty_run 'y\nVALUE-deepseek-1\nVALUE-glm-2\n' bash "$ADE" keys > "$T/out" 2>&1 || { cat "$T/out"; fail "exit"; }
  assert_contains "$T/out" "Set the missing keys now? [y/N]" "the one question"
  assert_contains "$T/out" "missing: deepseek, glm" "names what is missing"
  stored "deepseek=VALUE-deepseek-1" || fail "deepseek stored through bin/keys set deepseek on stdin"
  stored "glm=VALUE-glm-2" || fail "glm stored through bin/keys set glm on stdin"
  grep -qx "keys set deepseek" "$T/log" && grep -qx "stdin deepseek 16" "$T/log" || { cat "$T/log"; fail "the value came on stdin"; }
  assert_contains "$T/out" "Paste the deepseek key (hidden; empty skips):" "ade's hidden prompt"
  assert_eq "$(lists)" 2 "the list, then the list again"
  assert_not_contains "$T/out" "telegram key" "telegram is a chat token, not an AI tool key: never asked here"
}

keys_guided_no_or_pipe() {   # AC2
  fresh; keys_hub anthropic muse gemini
  (cd "$T" && "$H/bin/keys") > "$T/want"; : > "$T/log"
  pty_run 'n\n' bash "$ADE" keys > "$T/out" 2>&1 || { cat "$T/out"; fail "no: exit 0"; }
  assert_eq "$(lists)" 1 "no: the list once"; assert_not_contains "$T/out" "Paste" "and nothing asked"
  ! grep -q "keys set" "$T/log" || fail "no: nothing stored"
  bash "$ADE" keys < /dev/null > "$T/got" 2>&1 || fail "piped: exit 0"
  cmp -s "$T/want" "$T/got" || { diff "$T/want" "$T/got"; fail "piped: byte-identical to the hub's list"; }
  pty_run 'y\nVALUE-x\n' bash -c "bash '$ADE' keys > '$T/got'" > "$T/out" 2>&1 || fail "stdout not a terminal: exit 0"
  cmp -s "$T/want" "$T/got" || { diff "$T/want" "$T/got"; fail "stdout not a terminal: the list alone"; }
  pty_run '' bash -c "bash '$ADE' keys < /dev/null" > "$T/out" 2>&1 || fail "stdin not a terminal: exit 0"
  assert_not_contains "$T/out" "Set the missing" "stdin not a terminal: asks nothing"; assert_eq "$(lists)" 1 "the list alone"
  ! grep -q "keys set" "$T/log" || fail "nothing stored without a terminal"
  ! grep -q VALUE "$T/store" || fail "and nothing reached the store"
  fresh; keys_hub deepseek glm muse gemini; : > "$T/log"
  pty_run 'y\nVALUE-ant\n' bash "$ADE" keys > "$T/out" 2>&1 || fail "only anthropic missing: exit 0"
  assert_not_contains "$T/out" "Set the missing" "anthropic alone (optional) is not missing: no question"; assert_eq "$(lists)" 1 "the list alone"
  ! grep -q "keys set" "$T/log" || fail "nothing asked or stored"
}

keys_missing_flag() {   # AC3
  fresh; keys_hub anthropic muse gemini
  pty_run 'VALUE-ds\nVALUE-glm\n' bash "$ADE" keys --missing > "$T/out" 2>&1 || { cat "$T/out"; fail "exit"; }
  assert_not_contains "$T/out" "Set the missing keys now?" "no question"
  stored "deepseek=VALUE-ds" && stored "glm=VALUE-glm" || { cat "$T/out"; fail "each missing tool asked and stored"; }
  fresh; keys_hub anthropic muse gemini
  bash "$ADE" keys --missing < /dev/null > "$T/out" 2> "$T/err"; assert_eq "$?" 2 "not a terminal: exit 2"
  assert_eq "$(wc -l < "$T/err" | tr -d ' ')" 1 "one line"; assert_contains "$T/err" "terminal" "the reason"
  ! grep -q "keys set" "$T/log" || fail "nothing stored"
  pty_run '' bash -c "bash '$ADE' keys --missing > /dev/null" > "$T/out" 2>&1; assert_eq "$?" 2 "stdout not a terminal: exit 2"
  (export CLAUDECODE=1; pty_run '' bash "$ADE" keys --missing > "$T/out" 2>&1); assert_eq "$?" 2 "an agent session is never asked"
  fresh; keys_hub deepseek glm muse gemini
  pty_run '' bash "$ADE" keys --missing > "$T/out" 2>&1 || fail "nothing missing: exit 0"
  assert_contains "$T/out" "no AI tool key is missing" "says so"
}

keys_skip_and_fail() {   # AC4
  fresh; keys_hub anthropic gemini; touch "$T/fail.glm"
  pty_run 'y\n\nVALUE-glm-bad\nVALUE-muse-ok\n' bash "$ADE" keys > "$T/out" 2>&1; rc=$?
  assert_eq "$rc" 1 "a failed store: exit 1"
  assert_contains "$T/out" "deepseek: skipped" "empty skips"; ! grep -q "keys set deepseek" "$T/log" || fail "a skip stores nothing"
  assert_contains "$T/out" "The glm key was not stored (the hub's bin/keys set glm, exit 1" "a failed store says so"
  assert_not_contains "$T/out" "VALUE-glm-bad" "with no value in the message"; assert_contains "$T/out" "<hidden>" "the value the hub repeated is hidden"
  assert_not_contains "$T/out" "What now?" "and moves on"
  stored "muse=VALUE-muse-ok" || { cat "$T/out"; fail "the next tool is still asked"; }
  assert_eq "$(lists)" 2 "then the list again"
}

keys_passthrough() {   # AC5
  fresh; keys_hub
  printf 'VALUE-pass\n' | bash "$ADE" keys set glm > /dev/null 2>&1 || fail "set"
  grep -qx "keys set glm" "$T/log" && grep -qx "stdin glm 10" "$T/log" || { cat "$T/log"; fail "set glm reached the hub with stdin"; }
  bash "$ADE" keys share alice glm --days 3 < /dev/null > /dev/null 2>&1; grep -qx "keys share alice glm --days 3" "$T/log" || fail "share"
  bash "$ADE" keys receive https://one.example/x --from bob < /dev/null > /dev/null 2>&1
  grep -qx "keys receive https://one.example/x --from bob" "$T/log" || fail "receive"
  : > "$T/log"; pty_run '' bash "$ADE" keys forget glm > "$T/out" 2>&1; grep -qx "keys forget glm" "$T/log" || fail "at a terminal too"
  assert_not_contains "$T/out" "Set the missing" "a passed-through command asks nothing of its own"
  bash "$ADE" keys --missing extra < /dev/null > /dev/null 2>&1; grep -qx "keys --missing extra" "$T/log" || fail "only --missing alone is ade's"
}

keys_no_value() {   # AC6
  fresh; keys_hub anthropic muse gemini; touch "$T/fail.glm"
  pty_run 'y\nVALUE-SECRET-ds-0001\nVALUE-SECRET-glm-0002\n' bash "$ADE" keys > "$T/out" 2>&1
  stored "deepseek=VALUE-SECRET-ds-0001" || { cat "$T/out"; fail "stored"; }
  [ -s "$T/envs" ] && [ -s "$T/ps" ] || fail "the fake saw its environment and the process list"
  hits="$(grep -rl "VALUE-SECRET" "$T" | grep -vx "$T/store")"
  assert_eq "$hits" "" "no output, argv, environment, process list or other file holds a value"
  ! grep -rq "VALUE-SECRET" "$HOME" || fail "nothing in ade's config"
}

keys_ctrl_c() {   # review: Ctrl-C at the hidden prompt stops ade (130); what is typed after it is never read or stored
  fresh; keys_hub anthropic muse gemini deepseek
  python3 - "$T/pty.out" bash "$ADE" keys <<'PY'
import os, pty, select, sys, time
outp = sys.argv[1]; pid, fd = pty.fork()
if pid == 0: os.execvp(sys.argv[2], sys.argv[2:])
buf = b""; sent = []
def pump(t=0.2):
    global buf; end = time.time() + t
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
    if b"[y/N]" in buf and "y" not in sent: os.write(fd, b"y\n"); sent.append("y")
    if b"Paste the glm key" in buf and "c" not in sent: time.sleep(0.3); os.write(fd, b"\x03"); sent.append("c"); pump(0.5)
    if "c" in sent:
        try: os.write(fd, b"VISIBLE-GLM-KEY\n")
        except OSError: pass
        pump(0.5); break
open(outp, "wb").write(buf)
try: os.write(fd, b"\x04\x04")
except OSError: pass
_, st = os.waitpid(pid, 0); sys.exit(os.WEXITSTATUS(st) if os.WIFEXITED(st) else 128 + os.WTERMSIG(st))
PY
  rc=$?; assert_eq "$rc" 130 "Ctrl-C: exit 130"
  ! grep -q VISIBLE "$T/store" || fail "nothing typed after Ctrl-C is stored"
  assert_not_contains "$T/pty.out" "VISIBLE-GLM-KEY" "nor shown"
}

ALL="keys_guided_yes keys_guided_no_or_pipe keys_missing_flag keys_skip_and_fail keys_passthrough keys_no_value keys_ctrl_c"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
