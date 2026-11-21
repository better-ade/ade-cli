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
  fresh; make_method_repo; P="$T/proj"; mkdir -p "$P"; git init -q "$P"
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
  fresh; make_method_repo; P="$T/proj"; mkdir -p "$P/.ade"; git init -q "$P"; echo "mine" > "$P/.ade/rules.md"
  (cd "$P" && bash "$ADE" init) > "$T/out" 2>&1 || { cat "$T/out"; fail "init exit"; }
  assert_eq "$(cat "$P/.ade/rules.md")" "mine" "existing rules kept"
  assert_contains "$T/out" "kept .ade/rules.md" "listed as kept"
  assert_eq "$(cat "$P/docs/standards.md")" "standards" "the rest still copied"
}

agent_list_and_add() {   # AC7
  fresh; make_registry_repo; P="$T/proj"; mkdir -p "$P"; git init -q "$P"; cd "$P"
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
  bash "$ADE" help > "$T/out"; for c in work status dispatch notify chat method keys models roles doctor sync context agent-run orchestrator hub claude setup ui dash init agent skills open version help; do
    grep -qE "^  $c( |$)" "$T/out" || fail "help lists $c"; done
}

exports_hub() {   # review: a stale HUB in the caller's environment never points the hub's scripts at another hub
  fresh; make_hub "$T/hub" hub; printf '#!/bin/bash\necho "HUB=$HUB"\n' > "$T/hub/bin/work"
  out=$(HUB=/stale/hub ADE_HUB="$T/hub" bash "$ADE" work); assert_eq "$out" "HUB=$T/hub" "HUB exported"
}

not_executable() {   # review: a script without the exec bit is named as such, not as missing
  fresh; make_hub "$T/hub" hub; chmod -x "$T/hub/bin/sessions"
  ADE_HUB="$T/hub" bash "$ADE" status > "$T/out" 2>&1; rc=$?; assert_eq "$rc" 2 "exit"
  assert_contains "$T/out" "bin/sessions is not executable" "message"; assert_not_contains "$T/out" "has no bin/sessions" "not missing"
}

config_file_hub() {   # review: ~/.config/ade/hub expands a leading ~, trims spaces and CR, and names a bad path
  fresh; make_hub "$HOME/cfghub" cfghub; mkdir -p "$HOME/.config/ade" "$T/elsewhere"
  printf '  ~/cfghub \r\n' > "$HOME/.config/ade/hub"
  out=$(cd "$T/elsewhere" && bash "$ADE" work | head -1); assert_eq "$out" "cfghub work" "expanded and trimmed"
  echo "$T/nothub" > "$HOME/.config/ade/hub"
  (cd "$T/elsewhere" && bash "$ADE" work) > "$T/out" 2>&1; rc=$?; assert_eq "$rc" 2 "bad path exit"
  assert_contains "$T/out" "~/.config/ade/hub points to $T/nothub, which is not a hub" "bad path message"
}

init_rerun_new_tag() {   # review: a re-run at a new tag that keeps files leaves the old record; copy failures exit 1
  fresh; make_method_repo; git -C "$M" tag v2.1.0; P="$T/proj"; mkdir -p "$P"; git init -q "$P"
  (cd "$P" && bash "$ADE" init) > /dev/null 2>&1 || fail "first init"
  (cd "$P" && ADE_METHOD_REF=v2.1.0 bash "$ADE" init) > "$T/out" 2>&1 || { cat "$T/out"; fail "re-run exit"; }
  assert_eq "$(cat "$P/.ade/method-version")" "v2.0.0" "old record left"
  assert_contains "$T/out" ".ade/method-version left at v2.0.0" "says so"
  Q="$T/proj2"; mkdir -p "$Q"; git init -q "$Q"; : > "$Q/docs"   # docs/ cannot be made: the copy fails
  (cd "$Q" && bash "$ADE" init) > "$T/out" 2>&1; rc=$?; assert_eq "$rc" 1 "copy failure exit"
  [ ! -e "$Q/.ade/method-version" ] || fail "no record after a failed copy"
}

project_root() {   # review: init and agent add write at the git top level; outside git only with --here
  fresh; make_method_repo; make_registry_repo; P="$T/proj"; mkdir -p "$P/src"; git init -q "$P"
  (cd "$P/src" && bash "$ADE" init && bash "$ADE" agent add frontend) > "$T/out" 2>&1 || { cat "$T/out"; fail "from src/"; }
  [ -f "$P/.ade/rules.md" ] && [ -f "$P/.ade/agents/frontend.md" ] || fail "written at the top level"
  [ ! -e "$P/src/.ade" ] || fail "nothing under src/"
  N="$T/plain"; mkdir -p "$N"
  (cd "$N" && bash "$ADE" init) > "$T/out" 2>&1; rc=$?; assert_eq "$rc" 2 "outside git exit"
  assert_contains "$T/out" "--here" "names --here"; [ ! -e "$N/.ade" ] || fail "nothing written outside git"
  (cd "$N" && bash "$ADE" agent add frontend) > /dev/null 2>&1; assert_eq "$?" 2 "agent add outside git exit"
  (cd "$N" && bash "$ADE" init --here && bash "$ADE" agent add frontend --here) > "$T/out" 2>&1 || { cat "$T/out"; fail "--here"; }
  [ -f "$N/.ade/rules.md" ] && [ -f "$N/.ade/agents/frontend.md" ] || fail "--here writes in place"
}

fetch_errors() {   # review: git's error is shown and the temp checkout is removed
  fresh; make_method_repo; P="$T/proj"; mkdir -p "$P" "$T/tmp"; git init -q "$P"
  (cd "$P" && TMPDIR="$T/tmp" ADE_METHOD_REF=v9.9.9 bash "$ADE" init) > "$T/out" 2>&1; rc=$?
  assert_eq "$rc" 1 "exit"; assert_contains "$T/out" "could not fetch $M at v9.9.9" "names repo and ref"
  assert_contains "$T/out" "v9.9.9 not found" "shows git's error"
  assert_eq "$(ls -A "$T/tmp")" "" "temp dir removed"
}

symlinked_version() {   # review: a symlinked dev install finds VERSION beside the real script
  fresh; mkdir -p "$T/bin"; ln -s "$REPO/ade" "$T/bin/ade"
  assert_eq "$("$T/bin/ade" version)" "ade $(cat "$REPO/VERSION")" "version through a symlink"
}

ALL="finds_hub passes_args_to_hub status_and_missing_script no_hub init_copies_method init_never_overwrites agent_list_and_add skills_add_calls_claude open_inside_ade_only install_and_version exports_hub not_executable config_file_hub init_rerun_new_tag project_root fetch_errors symlinked_version"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
