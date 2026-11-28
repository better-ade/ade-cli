#!/bin/bash
# story A1: the `ade` command. Fixtures only: local hubs, local tagged repos, a fake claude; never the network.
. "$(dirname "$0")/helpers.sh"

finds_hub() {   # AC1: $ADE_HUB, then walking up, then ~/.config/ade/hub
  fresh; stub_claude; make_hub "$T/envhub" envhub; make_hub "$T/walkhub" walkhub; make_hub "$T/cfghub" cfghub
  mkdir -p "$T/walkhub/repos/deep" "$T/elsewhere" "$HOME/.config/ade"; echo "$T/cfghub" > "$HOME/.config/ade/hub"
  out=$(cd "$T/walkhub/repos/deep" && ADE_HUB="$T/envhub" bash "$ADE" work | head -1); assert_eq "$out" "envhub work" "ADE_HUB first"
  out=$(cd "$T/walkhub/repos/deep" && bash "$ADE" work | head -1); assert_eq "$out" "walkhub work" "walk up second"
  out=$(cd "$T/elsewhere" && bash "$ADE" work | head -1); assert_eq "$out" "cfghub work" "config file third"
}

passes_args_to_hub() {   # AC2
  fresh; stub_claude; make_hub "$T/hub" hub
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
  assert_eq "$(cat "$P/.ade/method-version")" "v2.2.0" "tag recorded (default pin v2.2.0)"
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
  fresh; stub_claude; make_skills_repo; P="$T/proj"; mkdir -p "$P"; cd "$P"
  bash "$ADE" skills add notes > "$T/out" 2>&1 || { cat "$T/out"; fail "skills add exit"; }
  bash "$ADE" skills add browser > "$T/out" 2>&1 || { cat "$T/out"; fail "second skills add exit"; }
  assert_contains "$CLAUDE_LOG" "plugin marketplace add $K" "marketplace added (from ADE_SKILLS_REPO)"
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
  fresh; stub_claude; make_hub "$T/hub" hub; printf '#!/bin/bash\necho "HUB=$HUB"\n' > "$T/hub/bin/work"
  out=$(HUB=/stale/hub ADE_HUB="$T/hub" bash "$ADE" work); assert_eq "$out" "HUB=$T/hub" "HUB exported"
}

not_executable() {   # review: a script without the exec bit is named as such, not as missing
  fresh; make_hub "$T/hub" hub; chmod -x "$T/hub/bin/sessions"
  ADE_HUB="$T/hub" bash "$ADE" status > "$T/out" 2>&1; rc=$?; assert_eq "$rc" 2 "exit"
  assert_contains "$T/out" "bin/sessions is not executable" "message"; assert_not_contains "$T/out" "has no bin/sessions" "not missing"
}

config_file_hub() {   # review: ~/.config/ade/hub expands a leading ~, trims spaces and CR, and names a bad path
  fresh; stub_claude; make_hub "$HOME/cfghub" cfghub; mkdir -p "$HOME/.config/ade" "$T/elsewhere"
  printf '  ~/cfghub \r\n' > "$HOME/.config/ade/hub"
  out=$(cd "$T/elsewhere" && bash "$ADE" work | head -1); assert_eq "$out" "cfghub work" "expanded and trimmed"
  echo "$T/nothub" > "$HOME/.config/ade/hub"
  (cd "$T/elsewhere" && bash "$ADE" work) > "$T/out" 2>&1; rc=$?; assert_eq "$rc" 2 "bad path exit"
  assert_contains "$T/out" "~/.config/ade/hub points to $T/nothub, which is not a hub" "bad path message"
}

init_rerun_new_tag() {   # review: a re-run at a new tag that keeps files leaves the old record; copy failures exit 1
  fresh; make_method_repo; git -C "$M" tag v2.3.0; P="$T/proj"; mkdir -p "$P"; git init -q "$P"
  (cd "$P" && bash "$ADE" init) > /dev/null 2>&1 || fail "first init"
  (cd "$P" && ADE_METHOD_REF=v2.3.0 bash "$ADE" init) > "$T/out" 2>&1 || { cat "$T/out"; fail "re-run exit"; }
  assert_eq "$(cat "$P/.ade/method-version")" "v2.2.0" "old record left"
  assert_contains "$T/out" ".ade/method-version left at v2.2.0" "says so"
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

init_installs_templates() {   # ade.json install_templates are copied (never overwritten) and the commit template is set
  fresh; make_method_repo; P="$T/proj"; mkdir -p "$P"; git init -q "$P"
  (cd "$P" && bash "$ADE" init) > "$T/out" 2>&1 || { cat "$T/out"; fail "init exit"; }
  assert_eq "$(cat "$P/.github/pull_request_template.md")" "## Overview" "PR template in .github/"
  assert_eq "$(cat "$P/.ade/commit-template.txt")" "<type>(<scope>): <summary>" "commit template in .ade/"
  assert_eq "$(git -C "$P" config --local commit.template)" "$P/.ade/commit-template.txt" "commit.template set in that repo, absolute"
  Q="$T/proj2"; mkdir -p "$Q/.github"; git init -q "$Q"; echo mine > "$Q/.github/pull_request_template.md"
  git -C "$Q" config commit.template my-template.txt
  (cd "$Q" && bash "$ADE" init) > "$T/out" 2>&1 || { cat "$T/out"; fail "second init exit"; }
  assert_eq "$(cat "$Q/.github/pull_request_template.md")" "mine" "existing PR template kept"
  assert_eq "$(git -C "$Q" config --local commit.template)" "my-template.txt" "an existing commit.template is kept"
  assert_contains "$T/out" "kept commit.template (my-template.txt)" "and listed as kept"
  R="$T/proj3"; mkdir -p "$R" "$T/tmp"; git init -q "$R"
  (cd "$R" && TMPDIR="$T/tmp" bash "$ADE" init) > "$T/out" 2>&1 || fail "third init"
  assert_not_contains "$T/out" "unbound variable" "clean exit"; assert_eq "$(ls -A "$T/tmp")" "" "temp checkout removed"
  N="$T/plain"; mkdir -p "$N"; (cd "$N" && bash "$ADE" init --here) > "$T/out" 2>&1 || { cat "$T/out"; fail "--here outside git"; }
  [ -f "$N/.ade/commit-template.txt" ] || fail "--here copies the templates"
  assert_contains "$T/out" "not a git repository: commit.template not set" "outside git it says so"
  G="$T/proj4"; mkdir -p "$G"; git init -q "$G"; git config --global commit.template "$HOME/my-global.txt"
  (cd "$G" && bash "$ADE" init) > "$T/out" 2>&1 || fail "fourth init"
  assert_eq "$(git -C "$G" config --local commit.template)" "" "a global commit.template is respected"
  assert_contains "$T/out" "kept your global commit.template" "and said so"
}

install_templates_guard() {   # review: a destination outside the project, or with a tab or newline, is refused (exit 1)
  for bad in '../x' '/etc/x' 'a/../../x' "$(printf 'a\tb')" "$(printf 'a\nb')"; do
    fresh; make_method_repo
    BAD="$bad" python3 - "$M/ade.json" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1])); d["install_templates"] = {"templates/commit-template.txt": os.environ["BAD"]}
json.dump(d, open(sys.argv[1], "w"))
PY
    commit_tag "$M" bad; git -C "$M" tag -f v2.2.0 > /dev/null 2>&1
    P="$T/proj"; mkdir -p "$P/sub"; git init -q "$P"
    (cd "$P/sub" && bash "$ADE" init) > "$T/out" 2>&1; assert_eq "$?" 1 "refused: [$bad]"
    [ ! -e "$T/x" ] && [ ! -e "$P/x" ] || fail "nothing written for [$bad]"
  done
}

symlinked_version() {   # review: a symlinked dev install finds VERSION beside the real script
  fresh; mkdir -p "$T/bin"; ln -s "$REPO/ade" "$T/bin/ade"
  assert_eq "$("$T/bin/ade" version)" "ade $(cat "$REPO/VERSION")" "version through a symlink"
}

tests_clean_up() {   # review: every test's folder is removed when it ends (the disk filled from leaked folders)
  T=""; t1="$(fresh; echo "$T")"; [ -n "$t1" ] && [ ! -e "$t1" ] || fail "a test's folder is removed on exit"
  t2="$(fresh; a="$T"; fresh; [ ! -e "$a" ] && echo "$T")"; [ -n "$t2" ] && [ ! -e "$t2" ] || fail "a second fresh removes the first folder"
}

suite_guard() {   # review: tests/run.sh fails a test file that changes ~/.config/ade, and never reads a file's content there
  fresh; local c="$HOME/.config/ade"; mkdir -p "$c"; echo "secret-one" > "$c/key"; chmod 600 "$c/key"
  printf '#!/bin/bash\necho added > "$HOME/.config/ade/new"; echo ok\n' > "$T/test_adds.sh"
  ADE_TESTS="$T/test_adds.sh" bash "$REPO/tests/run.sh" > "$T/out" 2>&1; assert_eq "$?" 1 "a change fails the run"
  assert_contains "$T/out" "FAIL  the real $c changed while $T/test_adds.sh ran" "says which file ran"; assert_contains "$T/out" "        $c/new" "names what changed"
  assert_not_contains "$T/out" "        $c/key" "only what changed"; assert_not_contains "$T/out" "secret-one" "no content shown"
  cat > "$T/test_same.sh" <<'F'
#!/bin/bash
python3 -I -c 'import os, sys
p = sys.argv[1]; st = os.stat(p); open(p, "w").write("secret-two\n")
os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))' "$HOME/.config/ade/key"; echo ok
F
  rm "$c/new"; ADE_TESTS="$T/test_same.sh" bash "$REPO/tests/run.sh" > "$T/out" 2>&1 || { cat "$T/out"; fail "same name, mode, size and time: not compared further"; }
  assert_contains "$T/out" "ok    $T/test_same.sh" "the content is never read"
}


# conflict_lines <folder>: the tracked text files' lines that are a merge conflict marker (file:line:text)
conflict_lines() { git -C "$1" grep -nIE '^(<<<<<<<( |$)|=======$|>>>>>>>( |$))' -- . 2> /dev/null; }
no_conflict_markers() {   # a merge left unresolved never ships: no marker line in any tracked text file
  fresh
  if git -C "$REPO" rev-parse --git-dir > /dev/null 2>&1; then
    hits="$(conflict_lines "$REPO")"; [ -z "$hits" ] || { printf '%s\n' "$hits" | cut -c1-120 | head -10; fail "merge conflict markers are committed"; }
  fi
  # the check itself: a planted marker of each kind fails it, and a file without one passes
  git init -q "$T/m"; printf 'a\n<<<<<<< HEAD\nb\n' > "$T/m/one.md"; printf 'a\n=======\nb\n' > "$T/m/two.md"
  printf 'a\n>>>>>>> origin/main\n' > "$T/m/three.md"; printf 'a ======= b\n== <<<<<<< ==\n' > "$T/m/fine.md"; git -C "$T/m" add -A
  assert_eq "$(conflict_lines "$T/m" | cut -d: -f1 | sort | tr '\n' ' ')" "one.md three.md two.md " "each planted marker is found, and only those"
}

ALL="no_conflict_markers suite_guard tests_clean_up finds_hub passes_args_to_hub status_and_missing_script no_hub init_copies_method init_never_overwrites agent_list_and_add skills_add_calls_claude open_inside_ade_only install_and_version exports_hub not_executable config_file_hub init_rerun_new_tag project_root fetch_errors init_installs_templates install_templates_guard symlinked_version"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
