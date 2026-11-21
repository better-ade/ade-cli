#!/bin/bash
# story A1: the `ade` command. Fixtures only: local hubs, local tagged repos, a fake claude; never the network.
. "$(dirname "$0")/helpers.sh"

finds_hub() {   # AC1: $ADE_HUB, then walking up, then ~/.config/ade/hub
  fresh; make_hub "$T/envhub" envhub; make_hub "$T/walkhub" walkhub; make_hub "$T/cfghub" cfghub
  mkdir -p "$T/walkhub/repos/deep" "$T/elsewhere" "$HOME/.config/ade"; echo "$T/cfghub" > "$HOME/.config/ade/hub"
  out=$(cd "$T/walkhub/repos/deep" && ADE_HUB="$T/envhub" bash "$ADE" work | head -1); assert_eq "$out" "envhub work" "ADE_HUB first"
  out=$(cd "$T/walkhub/repos/deep" && bash "$ADE" work | head -1); assert_eq "$out" "walkhub work" "walk up second"
  out=$(cd "$T/elsewhere" && bash "$ADE" work | head -1); assert_eq "$out" "cfghub work" "config file third"
}

passes_args_to_hub() {   # AC2
  fresh; make_hub "$T/hub" hub
  ADE_HUB="$T/hub" bash "$ADE" work x --role builder "two words" > "$T/out"
  assert_eq "$(cat "$T/out")" "hub work
arg:x
arg:--role
arg:builder
arg:two words" "arguments intact"
}

status_and_missing_script() {   # AC3
  fresh; make_hub "$T/hub" hub; export ADE_HUB="$T/hub"
  out=$(bash "$ADE" status --all); assert_eq "$out" "hub sessions
arg:--all" "status runs bin/sessions"
  bash "$ADE" dispatch a > "$T/out" 2>&1; rc=$?
  assert_eq "$rc" 2 "missing script exit"; assert_contains "$T/out" "this hub has no bin/dispatch; update it" "missing script message"
  bash "$ADE" agent-run a > "$T/out" 2>&1; assert_contains "$T/out" "this hub has no bin/agent; update it" "agent-run maps to bin/agent"
}

no_hub() {   # AC4
  fresh; mkdir -p "$T/nowhere"
  (cd "$T/nowhere" && bash "$ADE" work) > "$T/out" 2>&1; rc=$?
  assert_eq "$rc" 2 "no hub exit"
  assert_contains "$T/out" "ADE_HUB" "names ADE_HUB"; assert_contains "$T/out" "inside a hub" "names walking up"
  assert_contains "$T/out" "~/.config/ade/hub" "names the config file"
}

init_copies_method() {   # AC5
  fresh; make_method_repo; P="$T/proj"; mkdir -p "$P"
  (cd "$P" && bash "$ADE" init) > "$T/out" 2>&1 || { cat "$T/out"; fail "init exit"; }
  assert_eq "$(cat "$P/.ade/rules.md")" "rules at v2" "rules at the pin, not later"
  assert_eq "$(cat "$P/.ade/agents/developer.md")" "developer role" "agents copied"; [ -f "$P/.ade/agents/reviewer.md" ] || fail "all agents"
  assert_eq "$(cat "$P/_bmad/custom/bmad-build.toml")" "[build]" "bmad custom copied"
  assert_eq "$(cat "$P/.ade/context/decisions/README.md")" "adrs" "context templates copied"
  assert_eq "$(cat "$P/docs/standards.md")" "standards" "standards copied"
  assert_eq "$(cat "$P/.ade/method-version")" "v2.0.0" "tag recorded"
  [ ! -e "$P/.ade/ade.json" ] && [ ! -e "$P/.ade/templates" ] || fail "only the listed files are copied"
}

init_never_overwrites() {   # AC6
  fresh; make_method_repo; P="$T/proj"; mkdir -p "$P/.ade"; echo "mine" > "$P/.ade/rules.md"
  (cd "$P" && bash "$ADE" init) > "$T/out" 2>&1 || { cat "$T/out"; fail "init exit"; }
  assert_eq "$(cat "$P/.ade/rules.md")" "mine" "existing rules kept"
  assert_contains "$T/out" "kept .ade/rules.md" "listed as kept"
  assert_eq "$(cat "$P/docs/standards.md")" "standards" "the rest still copied"
}

agent_list_and_add() {   # AC7
  fresh; make_registry_repo; P="$T/proj"; mkdir -p "$P"; cd "$P"
  bash "$ADE" agent list > "$T/out" 2>&1 || { cat "$T/out"; fail "list exit"; }
  assert_contains "$T/out" "frontend" "lists frontend"; assert_contains "$T/out" "UI work: components, states, accessibility." "lists description"
  assert_contains "$T/out" "backend" "lists backend"
  bash "$ADE" agent add frontend > "$T/out" 2>&1 || { cat "$T/out"; fail "add exit"; }
  assert_eq "$(cat "$P/.ade/agents/frontend.md")" "# Frontend v1.1" "copied at the pin"
  bash "$ADE" agent add nosuch > "$T/out" 2>&1; rc=$?; assert_eq "$rc" 2 "unknown name exit"
  [ ! -e "$P/.ade/agents/nosuch.md" ] || fail "unknown name copies nothing"
}

skills_add_calls_claude() {   # AC8
  fresh; stub_claude; P="$T/proj"; mkdir -p "$P"; cd "$P"
  bash "$ADE" skills add notes > "$T/out" 2>&1 || { cat "$T/out"; fail "skills add exit"; }
  bash "$ADE" skills add browser > "$T/out" 2>&1 || { cat "$T/out"; fail "second skills add exit"; }
  assert_contains "$CLAUDE_LOG" "plugin marketplace add better-ade/ade-skills" "marketplace added"
  assert_eq "$(grep -c 'marketplace add' "$CLAUDE_LOG")" 1 "marketplace added once"
  assert_contains "$CLAUDE_LOG" "plugin install notes@ade-skills --scope project" "project-scope install"
  assert_contains "$CLAUDE_LOG" "plugin install browser@ade-skills --scope project" "second install"
}

open_inside_ade_only() {   # AC9
  fresh; printf '#!/bin/bash\nfor a in "$@"; do echo "hook:$a"; done\n' > "$T/hook"; chmod +x "$T/hook"
  out=$(ADE_HOOK_BIN="$T/hook" bash "$ADE" open a "b c"); assert_eq "$out" "hook:open
hook:a
hook:b c" "execs the hook"
  bash "$ADE" open a > "$T/out" 2>&1; rc=$?; assert_eq "$rc" 2 "outside ADE exit"
  assert_contains "$T/out" "ade open works inside the ADE app" "outside ADE message"
}

install_and_version() {   # AC10
  fresh; bash "$REPO/install.sh" "$T/prefix" > "$T/out" 2>&1 || { cat "$T/out"; fail "install exit"; }
  [ -x "$T/prefix/bin/ade" ] || fail "ade installed into the prefix"
  assert_eq "$(cd "$T" && "$T/prefix/bin/ade" version)" "ade $(cat "$REPO/VERSION")" "installed version"
  assert_eq "$(bash "$ADE" version)" "ade $(cat "$REPO/VERSION")" "repo version"
  bash "$ADE" help > "$T/out"; for c in work status dispatch notify chat method keys models roles doctor sync context agent-run init agent skills open version help; do
    grep -qE "^  $c( |$)" "$T/out" || fail "help lists $c"; done
}

ALL="finds_hub passes_args_to_hub status_and_missing_script no_hub init_copies_method init_never_overwrites agent_list_and_add skills_add_calls_claude open_inside_ade_only install_and_version"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
