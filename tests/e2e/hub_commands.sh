#!/bin/bash
# story C1: every hub command ade passes through (run_hub), against a hub made from the real ade-brain template. Only
# offline forms: no Claude (fake_claude), no Telegram, no key, no network after the template clone; sync pushes to a
# local bare remote. Each step runs ade <cmd> and, where it compares, the hub's bin/<script> directly: same exit, same output.
. "$(dirname "$0")/lib.sh"
export ADE_NO_UPDATE_CHECK=1   # no daily release fetch from these commands
step "install from this checkout"; bash "$REPO/install.sh" "$W/prefix" > /dev/null || fail "install"
export PATH="$W/prefix/bin:$PATH"; fake_claude
step "ade hub new --no-github (real ade-brain template)"
ade hub new e2e --no-github --dir "$W/hubs" --persona devops-sre --client Example --owner owner1 < /dev/null || fail "hub new"
H="$W/hubs/e2e"; [ -f "$H/hub.conf" ] || fail "hub.conf"; cd "$W" || exit 1

# same <script> <ade command> [args]: ade's exit and output are the hub script's own, run directly; the output is in $W/out
same() {
  local s="$1" c="$2" a d; shift 2
  ade "$c" "$@" < /dev/null > "$W/out" 2>&1; a=$?
  HUB="$H" "$H/bin/$s" "$@" < /dev/null > "$W/direct" 2>&1; d=$?
  echo "ade $c $*: exit $a (bin/$s: $d)"; head -6 "$W/out" | sed 's/^/  /'
  [ "$a" = "$d" ] || fail "ade $c $* exited $a, bin/$s $d"
  diff "$W/direct" "$W/out" > /dev/null || { diff "$W/direct" "$W/out"; fail "ade $c $*: output differs from bin/$s"; }
  return "$a"
}

step "real_method: ade method check"
same method method check; rc=$?; [ "$rc" -le 1 ] || fail "method check is not a check (exit $rc)"

step "real_models: ade models, then ade models set focus haiku"
same models models || fail "models"
grep -Eq '^focus +HUB_MODEL ' "$W/out" || fail "models shows the focus scope"
ade models set focus haiku || fail "models set"
grep -qx "HUB_MODEL=haiku" "$H/hub.conf" || fail "hub.conf has HUB_MODEL=haiku"
ade models | grep -Eq '^focus +HUB_MODEL +haiku ' || fail "the next ade models shows haiku"

step "real_roles: ade roles"
same roles roles; rc=$?; [ "$rc" -le 1 ] || fail "roles: a bad table (exit $rc)"
for r in routine triage reviewer architect builder; do
  grep -Eq "^$r +([a-z0-9-]+:[^ ]+|\(none usable\))" "$W/out" || fail "roles lists $r with its pick"; done

step "real_context: ade context, and one folder with its rules"
same context context || fail "context"
grep -q "^# .*: every folder" "$W/out" || fail "context heading"
same context context ops/e2e --rules || fail "context --rules"
grep -q "^## Shared rules" "$W/out" || fail "the hub's rules heading"

step "real_sync: ade sync to a local bare remote"
git init -q --bare "$W/remote.git" || fail "bare remote"
git -C "$H" remote add origin "$W/remote.git" && git -C "$H" push -q -u origin HEAD || fail "first push"
echo "- e2e: a memory line (story C1)" >> "$H/memory/MEMORY.md"
ade sync > "$W/out" 2>&1 || { cat "$W/out"; fail "sync review"; }
grep -q "memory/MEMORY.md" "$W/out" && grep -q "bin/sync --yes" "$W/out" || { cat "$W/out"; fail "sync review lists the change"; }
ade sync --yes || fail "sync --yes"
br="$(git -C "$H" symbolic-ref --short HEAD)" || fail "hub branch"   # the bare remote's own HEAD follows init.defaultBranch
[ "$(git -C "$H" rev-parse HEAD)" = "$(git -C "$W/remote.git" rev-parse "refs/heads/$br")" ] || fail "pushed to the remote"
[ "$(ade sync)" = "nothing to sync" ] || fail "nothing left uncommitted"

step "real_notify_chat: ade notify, ade chat status"
same notify notify --from main main "hello from e2e" || fail "notify"
ev="$(find "$HOME/.agent-hub" -name events.jsonl | head -1)"; [ -n "$ev" ] || fail "no event log"
[ "$(grep -c "hello from e2e" "$ev")" = 2 ] || fail "both notes (ade and bin/notify) in $ev"
same chat chat status; rc=$?; [ "$rc" -le 1 ] || fail "chat status (exit $rc)"
grep -q "^telegram: not paired yet" "$W/out" || fail "chat status says telegram is not set up"

step "real_dispatch_agent_run: ade dispatch --list, ade agent-run (usage: bin/agent has no --help)"
same dispatch dispatch --list || fail "dispatch --list"
same agent agent-run --help; rc=$?; [ "$rc" = 2 ] || fail "agent-run --help is usage (exit $rc)"
grep -q "^usage: bin/agent " "$W/out" || fail "agent usage line"

echo; echo "e2e hub_commands: ok"
