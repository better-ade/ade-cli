#!/bin/bash
# story A8 layer 6: a typed key is never shown, never in argv (ps while bin/keys reads it), never in a file.
# Drives ade setup with expect, and again in a real tmux pane with send-keys. Fakes for the hub's sign-in steps.
. "$(dirname "$0")/lib.sh"
KEY="e2e-K3Y-$$-typed"
H="$W/hub"; mkdir -p "$H/bin"; : > "$H/bin/lib.sh"; echo "HUB_NAME=e2e" > "$H/hub.conf"; export ADE_HUB="$H" PSLOG="$W/ps.log"
cat > "$H/bin/keys" <<'K'
#!/bin/bash
ps -A -o args= >> "$PSLOG"   # every process's argv while the key is being handed over
[ "${1:-}" = set ] && { IFS= read -r v; echo "$2=$v" >> "$HOME/keystore"; ps -A -o args= >> "$PSLOG"; }
exit 0
K
printf '#!/bin/bash\nps -A -o args= >> "$PSLOG"; cat > /dev/null; echo READY\n' > "$H/bin/agent"; chmod +x "$H/bin/keys" "$H/bin/agent"
fake_claude
leaks() {   # $1 = where: the key in no file except the fake key store, and in no process list
  local hits; hits="$(grep -rlF -- "$KEY" "$W" 2>/dev/null | grep -vx "$HOME/keystore")"
  [ -z "$hits" ] || { grep -hF -- "$KEY" $hits | head -5; fail "$1: the key is in $hits"; }
  grep -qx "deepseek=$KEY" "$HOME/keystore" || fail "$1: the key did not reach bin/keys"
}
if command -v expect > /dev/null; then
  step "expect: ade setup --top on a pty"
  printf '%s\n' "$KEY" | expect -f "$REPO/tests/e2e/setup.exp" "$REPO/ade" "$W/screen.expect" > /dev/null || { cat "$W/screen.expect"; fail "expect run"; }
  grep -q "Pick one" "$W/screen.expect" || fail "screen text"
  leaks expect   # the screen log is under $W: the key must not be in it
  rm -f "$HOME/keystore"
else echo "no expect here"; fi
if command -v tmux > /dev/null; then
  step "tmux: send-keys into a real pane"
  export TMUX_TMPDIR="$W"; tmux -L ia -f /dev/null new-session -d -s ia -x 120 -y 40 "/bin/bash $REPO/ade setup --top; sleep 30"
  wait_for() { local _; for _ in $(seq 1 40); do tmux -L ia capture-pane -p -t ia > "$W/screen.tmux"; grep -q "$1" "$W/screen.tmux" && return 0; sleep 0.5; done; cat "$W/screen.tmux"; fail "never saw: $1"; }
  wait_for "Pick one"; tmux -L ia send-keys -t ia 3 Enter
  wait_for "hidden"; tmux -L ia send-keys -t ia -l "$KEY"; tmux -L ia send-keys -t ia Enter
  wait_for "everything agent: deepseek"; tmux -L ia kill-server
  leaks tmux
else echo "no tmux here"; fi
echo; echo "e2e interactive: ok"
