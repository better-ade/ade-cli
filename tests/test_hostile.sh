#!/bin/bash
# story A8 layer 3: one table of hostile inputs against every command that takes a name. Each run must refuse
# (exit 2) or treat the input as data (a hub script receives it as one intact argument); nothing in it ever runs.
. "$(dirname "$0")/helpers.sh"

hostile_fixture() {
  make_method_repo; make_registry_repo; make_skills_repo; stub_claude
  H="$T/hub"; make_hub "$H" hub; echo "HUB_NAME=acme" > "$H/hub.conf"; mkdir -p "$H/projects/api" "$T/cwd"
  export ARGS="$T/args"; local s
  for s in work sessions dispatch notify chat method keys models roles doctor sync context agent; do
    printf '#!/bin/bash\nprintf "%%s\\0" "$@" > "$ARGS"\n' > "$H/bin/$s"; chmod +x "$H/bin/$s"; done
  cp "$H/bin/work" "$T/hook"; export ADE_HUB="$H" ADE_HOOK_BIN="$T/hook"
  mkdir -p "$T/fakebin"; printf '#!/bin/bash\nprintf "%%s\\0" "$@" >> "$T/tmux.args"\nexit 0\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
  export PATH="$T/fakebin:$PATH"
  TPL="$T/template"; mkdir -p "$TPL/bin"; git init -q "$TPL"; : > "$TPL/bin/lib.sh"
  printf '#!/bin/bash\n[ "$1" = --list ] && { echo "p  P"; exit 0; }\nprintf "%%s\\0" "$@" > "$ARGS"\n: > hub.conf\n' > "$TPL/bin/init"
  chmod +x "$TPL/bin/init"; commit_tag "$TPL" t; export ADE_HUB_TEMPLATE_URL="$TPL"
  git init -q "$T/cwd"
}
# got_arg <x>: the last hub script (or hook) received x as one whole argument
# argc_is <n>: the last hub script (or hook) received exactly n arguments
argc_is() { [ -f "$ARGS" ] && [ "$(python3 -c 'import sys; print(open(sys.argv[1],"rb").read().count(b"\0"))' "$ARGS")" = "$1" ]; }
got_arg() { [ -f "$ARGS" ] && X="$1" python3 -c 'import os,sys; sys.exit(0 if os.environb[b"X"] in open(sys.argv[1],"rb").read().split(b"\0") else 1)' "$ARGS"; }

# The table: one row per ade help command. R = must exit 2; D = data (a hub script gets X intact); S = search-like
# data (exit 0 or 1); A = an answer typed to a question (A18): asked again, then the end of input (exit 1), or taken
# as data that reaches bin/init intact (exit 0); none = takes no name. X is the hostile input.
table() {
  case "$1" in
    work|dispatch|notify|chat|method|keys|models|roles|doctor|sync|context|agent-run|status) echo "D1|$1 X" ;;
    open) echo "D2|open X" ;;
    orchestrator) echo "R|orchestrator new X --hub $H"; echo "R|orchestrator start X"; echo "R|orchestrator stop X"
      echo "R|orchestrator logs X"; echo "R|orchestrator remove X" ;;
    hub) echo "R|hub new X --no-github --persona p --client c --owner o"; echo "R|hub use X"
      echo "A|hub new okname --no-github --dir $T/ah --client c --owner o"; echo "A|hub new okname --no-github --dir $T/ah --persona p --owner o" ;;
    claude) echo "D1|claude X"; echo "R|claude -- --resume X --dangerously-skip-permissions"
      echo "R|orchestrator new okname --hub $H --channel X" ;;
    setup) echo "R|setup --test X"; echo "R|setup --tools X" ;;
    ui) echo "R|ui --tab-name X"; echo "R|ui --menu role X"; echo "S|ui --preview X"; echo "F|ui --menu new"
      echo "R|ui --menu links X"; echo "R|ui --links X" ;;
    files) echo "R|files X"; echo "R|files --act open X"; echo "R|files --act url X" ;;
    view) echo "R|view X"; echo "R|view --cwd X x" ;;
    agent) echo "R|agent add X" ;;
    skills) echo "R|skills add X"; echo "R|skills enable X"; echo "R|skills disable X"; echo "S|skills search X" ;;
    clean) echo "R|clean X" ;;
    home) echo "R|home X" ;;
    web) echo "R|web X"; echo "R|web --port X"; echo "R|web --tailnet X"; echo "R|web --print-link X" ;;
    shot) echo "R|shot X"; echo "R|shot url X"; echo "R|shot agent X"; echo "R|shot screen X"; echo "R|shot url https://example.test/ --width X" ;;
    update) echo "R|update X" ;;
    restore) echo "R|restore X"; echo "S|restore --label X" ;;
    reset) echo "R|reset X"; echo "R|reset --hub X"; echo "R|reset --keys --hub X" ;;
    uninstall) echo "R|uninstall X"; echo "R|uninstall --hub X" ;;
    project) echo "S|project X"; echo "R|project list X"; echo "R|project add --name X /nonexistent"; echo "R|project add --scan X"
      echo "S|project add X"; echo "S|project add --no-init X" ;;
    init|dash|version|help) echo none ;;
    *) return 1 ;;
  esac
}

every_command_in_table() {   # AC3: a command missing from the table fails
  fresh; hostile_fixture
  bash "$ADE" help | awk '/^  [a-z][a-z-]* / { print $1 }' | sort -u > "$T/cmds"
  [ "$(wc -l < "$T/cmds")" -ge 20 ] || fail "help lists the commands"
  while read -r c; do table "$c" > /dev/null || fail "command $c is not in the hostile-input table"; done < "$T/cmds"
}

hostile_inputs() {   # each input against each row
  fresh; hostile_fixture; local long; long="$(printf 'a%.0s' $(seq 1 300))"
  set -- "a b" "it's" 'say "hi"' "\$(touch $T/pwned)" "\`touch $T/pwned\`" ";touch $T/pwned" "|touch $T/pwned" "-rf" \
    "--dangerously-skip-permissions" "héllo" "a
b" "$long" "../../etc" ""
  local x c row kind cmd rc
  for c in $(cat "$T/cmds" 2>/dev/null || bash "$ADE" help | awk '/^  [a-z][a-z-]* / { print $1 }' | sort -u); do
    table "$c" | while IFS='|' read -r kind cmd; do
      [ "$kind" = none ] && continue
      for x in "$@"; do
        rm -f "$ARGS"; read -ra words <<< "$cmd"; argv=(); for w in "${words[@]}"; do if [ "$w" = X ]; then argv+=("$x"); else argv+=("$w"); fi; done
        if [ "$kind" = F ]; then   # a folder named x in the hub: listed or skipped, never run
          case "$x" in ""|*/*|.|..) continue ;; esac; mkdir -p "$H/projects/$x" 2> /dev/null || continue; fi
        if [ "$kind" = A ]; then case "$x" in *"
"*) continue ;; esac   # an answer is one line
          (cd "$T/cwd" && printf '%s\n' "$x" | bash "$ADE" "${argv[@]}") > "$T/out" 2>&1; rc=$?
        else (cd "$T/cwd" && bash "$ADE" "${argv[@]}" < /dev/null) > "$T/out" 2>&1; rc=$?; fi
        case "$kind" in
          R) [ "$rc" = 2 ] || { cat "$T/out"; fail "[$cmd] with [$x]: exit $rc, want 2"; }
             [ ! -s "$HOME/.config/ade/orchestrators" ] || fail "[$cmd] with [$x] registered something" ;;
          S) [ "$rc" = 0 ] || [ "$rc" = 1 ] || [ "$rc" = 2 ] || fail "[$cmd] with [$x]: exit $rc" ;;
          D*) n="${kind#D}"
             if [ "$c" = claude ] && [ "$x" = --dangerously-skip-permissions ]; then [ "$rc" = 2 ] || fail "claude refuses [$x]"
             else [ "$rc" = 0 ] || { cat "$T/out"; fail "[$cmd] with [$x]: exit $rc, want 0"; }; got_arg "$x" || fail "[$cmd] with [$x]: not passed intact"
               argc_is "$n" || fail "[$cmd] with [$x]: not exactly $n argument(s)"; fi ;;
          F) [ "$rc" = 0 ] || fail "[$cmd] with a folder [$x]: exit $rc"; rm -rf -- "$H/projects/$x" ;;
          A) case "$x" in ""|-*|*[[:cntrl:]]*|"$long") [ "$rc" = 1 ] && [ ! -f "$ARGS" ] || { cat "$T/out"; fail "[$cmd] answered [$x]: refused, exit $rc"; } ;;
               *) if [ "$rc" = 0 ]; then got_arg "$x" || fail "[$cmd] answered [$x]: not passed intact"; else [ "$rc" = 1 ] && [ ! -f "$ARGS" ] || fail "[$cmd] answered [$x]: exit $rc"; fi ;; esac
             rm -rf -- "$T/ah" ;;
        esac
        [ ! -e "$T/pwned" ] || fail "[$cmd] with [$x] ran the input"
        rm -f "$HOME/.config/ade/orchestrators"   # the --channel row registers okname each time
      done
    done || exit 1
  done
  [ ! -e "$T/pwned" ] || fail "an input ran"
  ls "$HOME/hubs" 2>/dev/null | grep -q . && fail "no hub was made from a hostile name"
  [ ! -s "$HOME/.config/ade/orchestrators" ] || fail "no orchestrator registered"
  return 0
}

ALL="every_command_in_table hostile_inputs"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
