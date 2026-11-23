#!/bin/bash
# story A21: `ade project add | add --scan | list`. A fixture hub (its bin/new, bin/brain, bin/sessions and bin/work are
# fakes; its lib.sh holds the hub's own repos_of, and templates/ACCESS.md is the hub's), a fake gh, and a git whose
# network clone is faked (every other git call is the real one). Local repos are made here. Answers come from files.
. "$(dirname "$0")/helpers.sh"

proj_fixture() {
  fresh; make_method_repo
  H="$T/hub"; F="$T/fakebin"; mkdir -p "$H/bin" "$H/templates" "$H/projects" "$F" "$T/cwd" "$T/ghconf"
  echo "HUB_NAME=acme" > "$H/hub.conf"
  export FT="$T" GH_CONFIG_DIR="$T/ghconf" REAL_GIT; REAL_GIT="$(command -v git)"
  cat > "$H/bin/lib.sh" <<'LIB'
hub_root() { if [ -n "${HUB:-}" ]; then echo "$HUB"; else (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); fi; }
# repos_of: the hub's own, word for word (ai-agent-hub-template bin/lib.sh)
repos_of() {
  local a; a="$(hub_root)/$1/ACCESS.md"; [ -f "$a" ] || return 0
  awk -F'|' '/^\|/{c=$3; gsub(/^[ \t]+|[ \t]+$/,"",c); if(c ~ /^[\/~]/)print c}' "$a" |
    while IFS= read -r r; do r="${r/#\~/$HOME}"; [ -d "$r" ] && echo "$r"; done
}
LIB
  cat > "$H/templates/ACCESS.md" <<'TPL'
# Access: {{NAME}}

Names and locations only. Never a key, token or password.

## Code
| Repo | Checkout | Default branch | Who merges | CI |
|---|---|---|---|---|

## Machines
| Name | Host / how to reach | What runs there | Safe read-only commands |
|---|---|---|---|

## Undo
| Live change | Rollback command |
|---|---|
TPL
  printf '# State: {{NAME}}\n\nUpdated: (UTC date and time, by whom)\n' > "$H/templates/STATE.md"
  cat > "$H/bin/new" <<'STUB'
#!/bin/bash
# the hub's bin/new, cut down: a folder from templates/, never overwriting
. "$(dirname "$0")/lib.sh"; H="$(hub_root)"; F="${1:-}"
[[ "$F" =~ ^(projects|ops)/[a-z0-9-]+$ ]] || { echo "usage: bin/new projects/<name>" >&2; exit 2; }
echo "new $*" >> "$FT/new.log"
[ ! -f "$FT/new.fail" ] || { echo "new: the templates are missing" >&2; exit 1; }
for f in ACCESS.md STATE.md; do
  if [ -e "$H/$F/$f" ]; then echo "kept $F/$f"; continue; fi
  mkdir -p "$H/$F"; sed "s/{{NAME}}/${F#*/}/" "$H/templates/$f" > "$H/$F/$f"; echo "made $F/$f"
done
STUB
  cat > "$H/bin/brain" <<'STUB'
#!/bin/bash
. "$HUB/hub.conf"; echo "brain $* paths=[${HUB_BRAIN_PATHS:-}]" >> "$FT/brain.log"
[ ! -f "$FT/brain.fail" ] || { echo "brain: no sqlite" >&2; exit 1; }
echo "indexed 2 changed file(s)"
STUB
  cat > "$H/bin/sessions" <<'STUB'
#!/bin/bash
printf '%-16s %-26s %-8s %-8s %-21s %-10s %-6s %-20s %s\n' NAME FOLDER PID PARENT STARTED ROLE STATUS LAST ENGINE
[ ! -f "$FT/sessions.rows" ] || cat "$FT/sessions.rows"
STUB
  cat > "$H/bin/work" <<'STUB'
#!/bin/bash
echo "work $*" >> "$FT/work.log"
STUB
  cat > "$H/bin/repos" <<'STUB'
#!/bin/bash
. "$(dirname "$0")/lib.sh"; repos_of "$1"
STUB
  # git: a clone from the network is faked (logged, then a small repo with that remote); everything else is real git
  cat > "$F/git" <<'STUB'
#!/bin/bash
n=$#; url=""; dest=""; clone=0
for a in "$@"; do [ "$a" = clone ] && clone=1; done
if [ "$clone" = 1 ] && [ "$n" -ge 3 ]; then url="${*:n-1:1}"; dest="${*:n:1}"; fi
case "$url" in
  *://*|*@*:*)   # anything that is not a local path: never the network
    echo "git clone $url $dest" >> "$FT/net.log"
    [ ! -f "$FT/clone.fail" ] || { echo "fatal: repository not found" >&2; exit 128; }
    "$REAL_GIT" init -q "$dest" && "$REAL_GIT" -C "$dest" symbolic-ref HEAD refs/heads/main && "$REAL_GIT" -C "$dest" remote add origin "$url" &&
      echo "# cloned" > "$dest/README.md" && "$REAL_GIT" -C "$dest" add -A && "$REAL_GIT" -C "$dest" commit -qm cloned; exit $? ;;
esac
exec "$REAL_GIT" "$@"
STUB
  # gh: signed in only when $FT/gh.signed is there; repo clone is logged and makes a small repo; never a token
  cat > "$F/gh" <<'STUB'
#!/bin/bash
echo "gh $*" >> "$FT/gh.log"
case "$1 $2" in
  "auth status") [ -f "$FT/gh.signed" ]; exit $? ;;
  "repo clone") "$REAL_GIT" init -q "$4" && "$REAL_GIT" -C "$4" symbolic-ref HEAD refs/heads/main && "$REAL_GIT" -C "$4" remote add origin "$3" &&
      echo "# gh" > "$4/README.md" && "$REAL_GIT" -C "$4" add -A && "$REAL_GIT" -C "$4" commit -qm cloned; exit $? ;;
esac
exit 1
STUB
  chmod +x "$H"/bin/new "$H"/bin/brain "$H"/bin/sessions "$H"/bin/work "$H"/bin/repos "$F"/git "$F"/gh
  export PATH="$F:$PATH" ADE_HUB="$H"; : > "$T/none"
}
# mkrepo <path> [remote]: a local repo on branch main with a README and docs/
mkrepo() {
  mkdir -p "$1/docs"; git init -q "$1"; git -C "$1" symbolic-ref HEAD refs/heads/main
  echo "# readme" > "$1/README.md"; echo "# guide" > "$1/docs/guide.md"
  [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"
  commit_tag "$1" first
}
# run <answers file> <ade args...>: ade in $T/cwd, its answers from that file; the lines in $T/out, the code in RC
run() { local in="$1"; shift; (cd "$T/cwd" && bash "$ADE" "$@" < "$in") > "$T/out" 2>&1; RC=$?; }
row_of() { grep -F "| $2 |" "$H/projects/$1/ACCESS.md" 2> /dev/null | head -1; }
is() { [ "$RC" = "$1" ] || { cat "$T/out"; fail "$2: exit $RC, want $1"; }; }

adds_local_repo() {   # AC1: a path inside a repo, its top level, the row from the repo
  proj_fixture; R="$T/src/My App"; mkrepo "$R" "git@github.com:acme/my-app.git"
  mkdir -p "$R/.github/workflows"; : > "$R/.github/workflows/ci.yml"; : > "$R/.github/workflows/release.yaml"; : > "$R/.github/workflows/bad name.yml"
  git -C "$R" update-ref refs/remotes/origin/develop HEAD; git -C "$R" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
  run "$T/none" project add "$R/docs" --no-init; is 0 "a local repo"
  assert_contains "$T/new.log" "new projects/my-app" "the hub's bin/new made the folder"
  assert_eq "$(row_of my-app "$R")" "| https://github.com/acme/my-app | $R | develop | (owner) | GitHub Actions (ci.yml, release.yaml, 1 more) |" "the Code row"
  [ "$(grep -n "^| https" "$H/projects/my-app/ACCESS.md" | cut -d: -f1)" = 8 ] || fail "the row sits at the end of the Code table"
  assert_contains "$H/projects/my-app/ACCESS.md" "## Machines" "the rest of ACCESS.md is kept"
  assert_contains "$T/out" "projects/my-app" "the summary names it"
  assert_contains "$T/out" "start it later: ade work projects/my-app" "no terminal: the command to start it"
  [ ! -e "$R/.ade" ] || fail "--no-init copies nothing"
  [ ! -f "$T/work.log" ] || fail "nothing starts without a terminal"
}

adds_two() {   # AC1: several at once; CI and a repo with no remote
  proj_fixture; mkrepo "$T/src/one"; : > "$T/src/one/.gitlab-ci.yml"; mkrepo "$T/src/two" "https://example.com/g/two.git"; mkdir "$T/src/two/.circleci"
  : > "$T/src/two/.gitlab-ci.yml"; git -C "$T/src/two" checkout -q --detach
  run "$T/none" project add "$T/src/one" "$T/src/two" --no-init; is 0 "two repos"
  assert_eq "$(row_of one "$T/src/one")" "| (no remote) | $T/src/one | main | (owner) | GitLab CI |" "no remote, GitLab CI"
  assert_eq "$(row_of two "$T/src/two")" "| https://example.com/g/two | $T/src/two | (detached) | (owner) | GitLab CI; CircleCI |" "a detached head, two CIs"
  [ "$(grep -c "added" "$T/out")" = 2 ] || fail "one summary line per project"
  # a hub folder whose ACCESS.md has no Code table still gets a row repos_of reads
  mkrepo "$T/src/three"; printf '# Access\n\n' > "$H/templates/ACCESS.md"
  run "$T/none" project add "$T/src/three" --no-init; is 0 "no Code table in the template"
  assert_contains "$H/projects/three/ACCESS.md" "## Code" "a Code table is added"
  assert_eq "$(HUB="$H" "$H/bin/repos" projects/three)" "$T/src/three" "and its row is read"
  assert_contains "$H/projects/three/ACCESS.md" "| none found |" "no CI seen"
}

repos_of_reads_row() {   # AC1: the hub's own repos_of reads the checkout back, ~ and all
  proj_fixture; mkrepo "$HOME/Project/api"
  run "$T/none" project add "$HOME/Project/api" --no-init; is 0 "a repo under home"
  assert_contains "$H/projects/api/ACCESS.md" "| (no remote) | ~/Project/api | main | (owner) | none found |" "the checkout is written with ~"
  assert_eq "$(HUB="$H" "$H/bin/repos" projects/api)" "$HOME/Project/api" "repos_of reads the checkout"
}

adds_url() {   # AC2: a URL is cloned into the code folder, never the hub; gh when it is signed in and the host is GitHub
  proj_fixture; mkdir -p "$HOME/Project"
  run "$T/none" project add https://github.com/acme/widget.git --no-init; is 0 "an https URL"
  assert_contains "$T/net.log" "git clone https://github.com/acme/widget.git $HOME/Project/widget" "git clones it into ~/Project"
  assert_contains "$H/projects/widget/ACCESS.md" "| https://github.com/acme/widget | ~/Project/widget | main | (owner) | none found |" "its row"
  [ -z "$(find "$H" -name .git)" ] || fail "nothing is cloned into the hub"
  : > "$T/gh.signed"
  run "$T/none" project add acme/tool --no-init; is 0 "owner/repo"
  assert_contains "$T/gh.log" "gh repo clone https://github.com/acme/tool $HOME/Project/tool" "gh clones a GitHub repo when it is signed in"
  [ -d "$H/projects/tool" ] || fail "owner/repo made projects/tool"
  run "$T/none" project add git@gitlab.example.com:grp/svc.git ssh://git@host.example:2222/grp/x.git --no-init; is 0 "ssh forms"
  assert_contains "$T/net.log" "git clone git@gitlab.example.com:grp/svc.git $HOME/Project/svc" "another host is cloned with git"
  assert_contains "$H/projects/svc/ACCESS.md" "| https://gitlab.example.com/grp/svc |" "git@ is stored in its https form"
  assert_contains "$H/projects/x/ACCESS.md" "| https://host.example/grp/x |" "ssh:// with a port too"
  # the clone is already there: used as it is; a folder of that name that is something else fails
  rm -rf "$H/projects/widget"; n="$(wc -l < "$T/net.log")"
  run "$T/none" project add https://github.com/acme/widget --no-init; is 0 "an existing clone"
  assert_contains "$T/out" "already cloned" "says the clone is there"
  assert_eq "$(wc -l < "$T/net.log")" "$n" "and does not clone again"
  mkdir "$HOME/Project/other"
  run "$T/none" project add https://github.com/acme/other --no-init; is 1 "a folder in the way"
  assert_contains "$T/out" "is already there and is not a clone" "says why"
  : > "$T/clone.fail"; rm -f "$T/gh.signed"
  run "$T/none" project add https://github.com/acme/gone https://github.com/acme/..; is 1 "a clone that fails"
  assert_contains "$T/out" "could not clone https://github.com/acme/gone: fatal: repository not found" "git's last line"
  assert_contains "$T/out" "no folder name can be read" "a URL with no name"
  [ ! -e "$H/projects/gone" ] || fail "no folder for a failed clone"
}

code_folder() {   # AC2: ADE_CODE_DIR, else ~/Project, else ~/code made after saying so; never in the hub
  proj_fixture
  run "$T/none" project add https://github.com/acme/a --no-init; is 0 "no ~/Project"
  assert_contains "$T/out" "making your code folder: ~/code" "says it before making it"
  [ -d "$HOME/code/a/.git" ] || fail "cloned into ~/code"
  ADE_CODE_DIR="$T/mine" run "$T/none" project add https://github.com/acme/b --no-init; is 0 "ADE_CODE_DIR"
  [ -d "$T/mine/b/.git" ] || fail "cloned into ADE_CODE_DIR"
  ADE_CODE_DIR="$H/code" run "$T/none" project add https://github.com/acme/c --no-init; is 1 "a code folder in the hub"
  assert_contains "$T/out" "inside the hub" "refused"
  [ ! -e "$H/code/c" ] || fail "nothing cloned into the hub"
  ADE_CODE_DIR="rel/path" run "$T/none" project add https://github.com/acme/d --no-init; is 1 "a relative code folder"
  mkrepo "$H/projects/inner"; rm -f "$H/projects/inner/ACCESS.md"
  run "$T/none" project add "$H/projects/inner" --no-init; is 1 "a repo inside the hub"
  assert_contains "$T/out" "is the hub or a folder in it" "refused"
}

existing_name_kept() {   # AC3: a hub folder of that name, or a repo the hub already lists, is left as it is
  proj_fixture; mkrepo "$T/src/api"; mkdir -p "$H/projects/api"; echo mine > "$H/projects/api/ACCESS.md"
  run "$T/none" project add "$T/src/api" --no-init; is 0 "an existing folder is not a failure"
  assert_contains "$T/out" "projects/api is already in the hub: left as it is (another name: --name)" "says so"
  assert_eq "$(cat "$H/projects/api/ACCESS.md")" mine "never overwritten"
  [ ! -f "$T/new.log" ] || fail "bin/new is not run for it"
  run "$T/none" project add "$T/src/api" --name api-2 --no-init; is 0 "--name"
  assert_contains "$H/projects/api-2/ACCESS.md" "| $T/src/api |" "made under the other name"
  run "$T/none" project add "$T/src/api" --name api-3 --no-init; is 0 "the same repo again"
  assert_contains "$T/out" "already in the hub as projects/api-2: left as it is" "a repo the hub already lists"
  [ ! -e "$H/projects/api-3" ] || fail "not added twice"
}

name_rules() {   # AC3: the hub's folder rules, and the usage refusals
  proj_fixture; mkrepo "$T/src/My_App.v2"; mkrepo "$T/src/---"; mkrepo "$T/src/b"
  run "$T/none" project add "$T/src/My_App.v2" --no-init; is 0 "a name to sanitise"
  [ -d "$H/projects/my-app-v2" ] || fail "My_App.v2 becomes my-app-v2"
  run "$T/none" project add "$T/src/---" --no-init; is 1 "no name left"
  assert_contains "$T/out" "pass --name" "says to pass --name"
  run "$T/none" project add "$T/src/b" --name Bad_Name; is 2 "a bad --name"
  run "$T/none" project add "$T/src/b" "$T/src/---" --name x; is 2 "--name with two repos"
  run "$T/none" project add; is 2 "no repo"
  run "$T/none" project add --name; is 2 "--name alone"
  run "$T/none" project add --scan; is 2 "--scan alone"
  run "$T/none" project add --scan "$T/nope"; is 2 "--scan a missing folder"
  run "$T/none" project add --scan "$T/src" "$T/src/b"; is 2 "--scan with a repo"
  run "$T/none" project add --bogus "$T/src/b"; is 2 "an unknown option"
  [ ! -e "$H/projects/b" ] && [ ! -e "$H/projects/x" ] || fail "a refused command adds nothing"
}

credentials_stripped() {   # AC4: a remote with user:token@ is shown and stored without it
  proj_fixture; mkdir -p "$HOME/Project"
  mkrepo "$T/src/priv" "https://alice:ghp_SECRETTOKEN1234567890@github.com/acme/priv.git"
  run "$T/none" project add "$T/src/priv" "https://bob:tok_HIDDENVALUE99@github.com/acme/priv2.git" "https://ghp_TOKENALONE12345@github.com/acme/p3" \
    "bob:tok_NOTAURL77@nowhere" --no-init; is 1 "three repos and one that is not a repo"
  assert_contains "$H/projects/priv/ACCESS.md" "| https://github.com/acme/priv | $T/src/priv |" "the stored remote has no credentials"
  assert_contains "$H/projects/priv2/ACCESS.md" "| https://github.com/acme/priv2 |" "a URL given with them"
  assert_contains "$H/projects/p3/ACCESS.md" "| https://github.com/acme/p3 |" "a token alone"
  assert_contains "$T/out" "that URL is used without its credentials or query" "says so"
  for s in SECRETTOKEN HIDDENVALUE TOKENALONE NOTAURL; do
    ! grep -rqF "$s" "$T/out" "$H" "$HOME" "$T/net.log" || fail "$s was printed, stored or cloned with"
  done
  assert_contains "$T/net.log" "git clone https://github.com/acme/priv2.git " "cloned without them"
}

credential_forms() {   # AC4 (review B2): every form a credential can take in a remote; inputs from a file, secrets built here
  proj_fixture; mkdir -p "$HOME/Project"; K="FAKE$(printf '%s' pw)$$"; n=0
  printf '%s\n' "HTTPS://user:${K}@host.example/o/r1" "https://user:pa/ss${K}@host.example/o/r2.git" "https://user:p@ss${K}@host.example/o/r3.git" \
    "user:${K}@host.example:o/r4.git" "ssh://user:${K}@host.example:22/o/r5.git" "https://${K}@host.example/o/r6" \
    "Git+SSH://user:${K}@host.example/o/r7" "https://host.example/o/r8.git?token=${K}" "https://host.example/o/r9#${K}" > "$T/remotes"
  # each as a local repo's configured remote: stored and shown without it
  while IFS= read -r u; do n=$((n + 1)); mkrepo "$T/src/l$n"; git -C "$T/src/l$n" config remote.origin.url "$u"
    run "$T/none" project add "$T/src/l$n" --no-init; is 0 "a local repo whose remote is line $n"
    ! grep -rqF "$K" "$T/out" "$H" "$HOME" || { grep -rF "$K" "$T/out" "$H" | head -3; fail "line $n: the credential was printed or stored"; }
    r="$(awk -F'|' -v c="$T/src/l$n" '{ x = $3; gsub(/^ +| +$/, "", x) } x == c { y = $2; gsub(/^ +| +$/, "", y); print y }' "$H/projects/l$n/ACCESS.md")"
    case "$r" in "https://host.example/o/r$n"|"(remote hidden: it held a credential)") ;; *) fail "line $n: the stored remote is [$r]" ;; esac
    case "$r" in *@*) fail "line $n: a userinfo is left in [$r]" ;; esac
  done < "$T/remotes"
  assert_contains "$H/projects/l1/ACCESS.md" "| https://host.example/o/r1 |" "an uppercase scheme"
  assert_contains "$H/projects/l2/ACCESS.md" "| https://host.example/o/r2 |" "a / in the password"
  assert_contains "$H/projects/l3/ACCESS.md" "| https://host.example/o/r3 |" "an @ in the password"
  assert_contains "$H/projects/l4/ACCESS.md" "| https://host.example/o/r4 |" "scp-like with a password"
  assert_contains "$H/projects/l8/ACCESS.md" "| https://host.example/o/r8 |" "a query"
  # each given as the URL to clone: cloned without it (no userinfo password, no query), or refused with one line
  : > "$T/net.log"; n=0
  while IFS= read -r u; do n=$((n + 1))
    run "$T/none" project add "$u" --no-init
    ! grep -rqF "$K" "$T/out" "$H" "$HOME" "$T/net.log" || { grep -rF "$K" "$T/out" "$T/net.log" | head -3; fail "line $n as a URL: the credential was printed, stored or cloned with"; }
  done < "$T/remotes"
  assert_not_contains "$T/net.log" "?" "no clone carries a query"
  assert_contains "$T/net.log" "/o/r8.git $HOME/Project/r8" "the query is dropped before the clone"
  assert_contains "$T/net.log" "git clone user@host.example:o/r4.git $HOME/Project/r4" "scp-like: its user name only"
  assert_contains "$T/net.log" "git clone ssh://user@host.example:22/o/r5.git $HOME/Project/r5" "ssh: its user name only"
  [ "$(wc -l < "$T/net.log" | tr -d ' ')" = 9 ] || fail "each of the nine is cloned once"
  [ -d "$H/projects/r1" ] && [ -d "$H/projects/r3" ] && [ -d "$H/projects/r4" ] && [ -d "$H/projects/r8" ] || { cat "$T/out"; fail "the URLs are still cloned and added"; }
  # last line of defence: a remote that still looks like it holds a userinfo is hidden, never written
  mkrepo "$T/src/odd"; git -C "$T/src/odd" config remote.origin.url "weird;user:${K}@[host]:x"
  run "$T/none" project add "$T/src/odd" --no-init; is 0 "a remote ade cannot read"
  ! grep -rqF "$K" "$T/out" "$H" || fail "an unreadable remote's credential was printed or stored"
  assert_contains "$H/projects/odd/ACCESS.md" "| (remote hidden: it held a credential) | $T/src/odd |" "hidden"
}

init_offered_never_overwrites() {   # AC5: one yes/no per repo; ade init never overwrites
  proj_fixture; mkrepo "$T/src/a"; mkrepo "$T/src/b"; mkrepo "$T/src/c"; mkdir "$T/src/a/.ade"; echo mine > "$T/src/a/.ade/rules.md"
  printf 'y\nn\n' > "$T/in"
  run "$T/in" project add "$T/src/a" "$T/src/b" "$T/src/c"; is 0 "init offered"
  [ "$(grep -c "copy the ADE method into it (ade init; nothing is overwritten)? \[y/N\]" "$T/out")" = 3 ] || fail "asked once per repo"
  assert_eq "$(cat "$T/src/a/.ade/rules.md")" mine "an existing file is kept"
  assert_contains "$T/out" "kept .ade/rules.md (already there)" "and said so"
  assert_eq "$(cat "$T/src/a/.ade/agents/developer.md")" "developer role" "the rest is copied"
  [ ! -e "$T/src/b/.ade" ] || fail "n copies nothing"
  [ ! -e "$T/src/c/.ade" ] || fail "no answer is no"
  [ -d "$H/projects/c" ] || fail "and the project is still added"
  # an ade init that cannot finish does not undo the project
  mkrepo "$T/src/d"; printf 'y\n' > "$T/in"
  ADE_METHOD_REPO="$T/no-such-repo" run "$T/in" project add "$T/src/d"; is 0 "init fails"
  assert_contains "$T/out" "ade init did not finish there" "says so"
  [ -d "$H/projects/d" ] || fail "the project is added all the same"
}

no_init_and_yes() {   # AC5: --no-init never offers; --yes is yes to every offer, and still never overwrites
  proj_fixture; mkrepo "$T/src/a"; mkrepo "$T/src/b"; mkdir "$T/src/b/.ade"; echo mine > "$T/src/b/.ade/rules.md"
  printf 'y\n' > "$T/in"
  run "$T/in" project add "$T/src/a" --no-init; is 0 "--no-init"
  assert_not_contains "$T/out" "ade init" "no offer"
  [ ! -e "$T/src/a/.ade" ] || fail "--no-init copies nothing"
  run "$T/none" project add "$T/src/b" --yes; is 0 "--yes"
  assert_eq "$(cat "$T/src/b/.ade/rules.md")" mine "--yes never overwrites"
  [ -f "$T/src/b/.ade/agents/reviewer.md" ] || fail "--yes ran ade init"
  assert_not_contains "$T/out" "[y/N]" "--yes asks nothing"
  [ ! -f "$T/work.log" ] || fail "--yes without a terminal starts nothing"
}

memory_indexed() {   # AC6: README.md and docs/ into HUB_BRAIN_PATHS, then bin/brain index; skipped with one line and why
  proj_fixture; mkrepo "$HOME/Project/api"; mkrepo "$HOME/Project/my app"; mkrepo "$HOME/Project/bare"; rm -rf "$HOME/Project/bare/README.md" "$HOME/Project/bare/docs"
  echo "HUB_BRAIN_PATHS='~/notes'" >> "$H/hub.conf"
  run "$T/none" project add "$HOME/Project/api" --no-init; is 0 "indexed"
  assert_contains "$H/hub.conf" "HUB_BRAIN_PATHS='~/notes ~/Project/api/README.md ~/Project/api/docs'" "added to what was there"
  assert_contains "$T/brain.log" "brain index paths=[~/notes ~/Project/api/README.md ~/Project/api/docs]" "bin/brain index ran with them"
  assert_contains "$T/out" "memory: README.md and docs/ indexed" "one line"
  run "$T/none" project add "$HOME/Project/my app" "$HOME/Project/bare" --no-init; is 0 "paths the list cannot hold"
  assert_contains "$T/out" "skipped (HUB_BRAIN_PATHS cannot hold a space or a special character)" "a path with a space"
  assert_contains "$T/out" "memory: skipped (no README.md or docs/ to index)" "nothing to index"
  [ "$(grep -c "api/docs" "$H/hub.conf")" = 1 ] || fail "hub.conf is not written again"
  mkrepo "$HOME/Project/two"; : > "$T/brain.fail"
  run "$T/none" project add "$HOME/Project/two" --no-init; is 0 "an index that fails"
  assert_contains "$T/out" "not indexed (bin/brain index failed: brain: no sqlite)" "says why"
  mkrepo "$HOME/Project/three"; rm "$H/bin/brain"
  run "$T/none" project add "$HOME/Project/three" --no-init; is 0 "no bin/brain"
  assert_contains "$T/out" "memory: skipped (this hub has no bin/brain)" "says why"
  assert_not_contains "$H/hub.conf" "three" "and hub.conf is left alone"
  mkrepo "$HOME/Project/four"; : > "$H/bin/brain"; chmod +x "$H/bin/brain"; chmod a-w "$H"
  run "$T/none" project add "$HOME/Project/four" --no-init; chmod u+w "$H"; is 0 "a hub.conf that cannot be written"
  [ "$(id -u)" = 0 ] || assert_contains "$T/out" "memory: skipped (hub.conf could not be written)" "says why (root can always write)"
}

non_repo_fails_alone() {   # AC7: a failure for one does not stop the others
  proj_fixture; mkdir "$T/plain"; : > "$T/file"; mkrepo "$T/src/good"; mkrepo "$T/src/pipe|d"
  run "$T/none" project add "$T/plain" "$T/nope" "$T/file" "" "$T/src/pipe|d" "$T/src/good" --no-init; is 1 "five bad, one good"
  assert_contains "$T/out" "plain is not in a git repository" "a folder that is not a repo"
  assert_contains "$T/out" "nope is not a folder here, nor a git URL or owner/repo" "a path that is not there"
  assert_contains "$T/out" "file is a file, not a repo" "a file"
  assert_contains "$T/out" "an empty name is not a repo" "an empty argument"
  assert_contains "$T/out" "its path has a |" "a path the table cannot hold"
  assert_contains "$T/out" "5 of 6 failed; the rest are done" "the count"
  assert_contains "$H/projects/good/ACCESS.md" "| $T/src/good |" "the good one is added"
  [ "$(grep -c " failed   " "$T/out")" = 5 ] || fail "the summary names each failure"
  assert_not_contains "$T/out" "What now?" "no question without a terminal"
  # the hub's bin/new fails, makes nothing, or is not there
  mkrepo "$T/src/n1"; : > "$T/new.fail"
  run "$T/none" project add "$T/src/n1" --no-init; is 1 "bin/new fails"
  assert_contains "$T/out" "the hub's bin/new projects/n1 failed: new: the templates are missing" "its last line"
  rm "$T/new.fail"; printf '#!/bin/bash\nexit 0\n' > "$H/bin/new"
  run "$T/none" project add "$T/src/n1" --no-init; is 1 "bin/new makes nothing"
  assert_contains "$T/out" "made no projects/n1/ACCESS.md" "says so"
  mkdir -p "$H/projects/n2"; ln -s "$T/elsewhere" "$H/projects/n2/ACCESS.md"; : > "$T/elsewhere"; mv "$H/projects/n2" "$T/n2"
  printf '#!/bin/bash\nmv "%s" "$HUB/projects/n2"\n' "$T/n2" > "$H/bin/new"
  run "$T/none" project add "$T/src/n1" --name n2 --no-init; is 1 "an ACCESS.md that is a link"
  assert_contains "$T/out" "its ACCESS.md Code row could not be written" "nothing is written through a link"
  [ ! -s "$T/elsewhere" ] || fail "the link's target was written"
  rm "$H/bin/new"
  run "$T/none" project add "$T/src/n1" --name n3 --no-init; is 1 "no bin/new"
  assert_contains "$T/out" "this hub has no bin/new; update it" "says to update the hub"
}

failure_asks_at_terminal() {   # AC7: at a terminal, the shared question (try again, skip, stop)
  proj_fixture; mkdir "$T/plain"; mkrepo "$T/src/good"
  (cd "$T/cwd" && pty_run 'skip\nn\n' bash "$ADE" project add "$T/plain" "$T/src/good" --no-init) > "$T/out" 2>&1; RC=$?; is 1 "skip"
  assert_contains "$T/out" "What now?" "the shared question"
  assert_contains "$T/out" "skip this one and go on with the rest" "its choices"
  [ -d "$H/projects/good" ] || fail "skip goes on with the rest"
  rm -rf "$H/projects/good"
  (cd "$T/cwd" && pty_run 'retry\nstop\n' bash "$ADE" project add "$T/plain" "$T/src/good" --no-init) > "$T/out" 2>&1; RC=$?; is 1 "retry, then stop"
  [ "$(grep -c "What now?" "$T/out")" = 2 ] || fail "retry asks again when it fails again"
  [ ! -d "$H/projects/good" ] || fail "stop stops"
  assert_contains "$T/out" "to come back, run ade project add" "how to come back"
}

start_refused_in_agent_session() {   # AC8: no start offer in an agent session, or without a terminal
  proj_fixture; mkrepo "$T/src/a"
  (cd "$T/cwd" && CLAUDECODE=1 pty_run 'y\ny\n' bash "$ADE" project add "$T/src/a" --no-init) > "$T/out" 2>&1; RC=$?; is 0 "an agent session"
  assert_not_contains "$T/out" "start focus agents" "not asked"
  assert_contains "$T/out" "start it later: ade work projects/a" "the command instead"
  [ ! -f "$T/work.log" ] || fail "nothing starts in an agent session"
  mkrepo "$T/src/b"
  (cd "$T/cwd" && CLAUDE_CODE_SESSION_ID=x pty_run '' bash "$ADE" project add "$T/src/b" --no-init --yes) > "$T/out" 2>&1; RC=$?; is 0 "--yes in an agent session"
  [ ! -f "$T/work.log" ] || fail "--yes starts nothing in an agent session"
}

start_at_terminal() {   # AC8: the offer, then ade work projects/<name> for each
  proj_fixture; mkrepo "$T/src/a"; mkrepo "$T/src/b"; mkrepo "$T/src/c"; mkrepo "$T/src/d"
  (cd "$T/cwd" && pty_run '\n' bash "$ADE" project add "$T/src/a" --no-init) > "$T/out" 2>&1; RC=$?; is 0 "Enter"
  assert_contains "$T/out" "start focus agents on them now? [y/N]" "the offer"
  [ ! -f "$T/work.log" ] || fail "Enter is no"
  (cd "$T/cwd" && pty_run 'y\n' bash "$ADE" project add "$T/src/b" "$T/src/c" --no-init) > "$T/out" 2>&1; RC=$?; is 0 "yes"
  assert_eq "$(cat "$T/work.log")" "work projects/b
work projects/c" "ade work for each"
  (cd "$T/cwd" && pty_run '' bash "$ADE" project add "$T/src/d" --no-init --yes) > "$T/out" 2>&1; RC=$?; is 0 "--yes at a terminal"
  assert_contains "$T/work.log" "work projects/d" "--yes starts them"
  rm "$H/bin/work"; mkrepo "$T/src/e"
  (cd "$T/cwd" && pty_run 'y\n' bash "$ADE" project add "$T/src/e" --no-init) > "$T/out" 2>&1; RC=$?; is 0 "a start that fails"
  assert_contains "$T/out" "projects/e did not start; later: ade work projects/e" "says so, and the project stays added"
}

scan_picks() {   # AC9: the repos directly under a folder, those in the hub marked, the numbered choice
  proj_fixture; S="$T/scan"; for r in r1 r2 r3 r4 r5; do mkrepo "$S/$r"; done; mkdir -p "$S/plain" "$S/r2/sub"; : > "$S/file"
  run "$T/none" project add "$S/r1" --no-init; is 0 "one first"
  printf '9\n1 3\n' > "$T/in"
  run "$T/in" project add --scan "$S" --no-init; is 0 "a numbered pick"
  assert_contains "$T/out" "-  r1  already in the hub (projects/r1)" "marks the one in the hub"
  assert_contains "$T/out" "1) r2" "numbers the others"; assert_contains "$T/out" "4) r5" "all four"
  assert_not_contains "$T/out" "plain" "a folder that is not a repo is not listed"
  assert_contains "$T/out" "accepted:" "an answer that is not in the list is asked again"
  [ -d "$H/projects/r2" ] && [ -d "$H/projects/r4" ] || fail "1 3 adds r2 and r4"
  [ ! -d "$H/projects/r3" ] && [ ! -d "$H/projects/r5" ] || fail "and only those"
  run "$T/none" project add --scan "$S" --no-init; is 0 "no answer"
  assert_contains "$T/out" "nothing added" "the end of input adds nothing"
  printf 'all\n' > "$T/in"
  run "$T/in" project add --scan "$S" --no-init; is 0 "all"
  [ -d "$H/projects/r3" ] && [ -d "$H/projects/r5" ] || fail "all adds the rest"
  run "$T/none" project add --scan "$S"; is 0 "nothing new"
  assert_contains "$T/out" "nothing new to add" "says so"
  # a range, a name, and two repos whose names come out the same
  S2="$T/scan2"; for r in x1 x2 x3 "My App" my-app; do mkrepo "$S2/$r"; done
  printf '2-3, x2\n' > "$T/in"
  run "$T/in" project add --scan "$S2" --no-init; is 0 "a range and a name"
  [ -d "$H/projects/x1" ] && [ -d "$H/projects/x2" ] || fail "2-3 and x2 add x1 (the third) and x2"
  [ -d "$H/projects/my-app" ] || fail "2-3 adds the second (one of the two my-app)"
  [ ! -d "$H/projects/x3" ] || fail "x3 was not picked"
  run "$T/none" project add --scan "$S2" --no-init --yes; is 0 "--yes"
  [ -d "$H/projects/x3" ] || fail "--scan --yes adds every new one"
  assert_contains "$T/out" "is already in the hub: left as it is (another name: --name)" "the second my-app is left, with the way out"
  # subfolders of one repo are not repos of their own; an empty folder
  mkrepo "$T/mono"; mkdir -p "$T/mono/pkg1" "$T/empty"
  run "$T/none" project add --scan "$T/mono"; is 0 "inside a repo"
  assert_contains "$T/out" "no git repos directly under" "their top levels only"
  run "$T/none" project add --scan "$T/empty"; is 0 "an empty folder"
}

lists_projects() {   # AC10: name, checkout, branch, agent, Updated
  proj_fixture; mkrepo "$HOME/Project/api"; mkrepo "$T/src/web"; git -C "$T/src/web" checkout -q -b feature
  run "$T/none" project add "$HOME/Project/api" "$T/src/web" --no-init; is 0 "two projects"
  printf '# State: api\n\nUpdated: 2026-11-23 10:00 UTC, by the owner\n' > "$H/projects/api/STATE.md"; mkdir "$H/projects/empty"
  printf '%s\n' "api              projects/api               4242     -        2026-11-23T10:00:00Z  builder    busy   2026-11-23T10:01:00Z claude" \
    "web              projects/web               4243     -        2026-11-23T10:00:00Z  -          -      -                    claude" > "$T/sessions.rows"
  run "$T/none" project list; is 0 "project list"
  assert_contains "$T/out" "NAME" "a header"
  grep -Eq "^api +~/Project/api +main +busy +2026-11-23 10:00 UTC, by the owner$" "$T/out" || { cat "$T/out"; fail "api's line"; }
  grep -Eq "^web +$T/src/web +feature +running +\(UTC date and time, by whom\)$" "$T/out" || { cat "$T/out"; fail "web's line"; }
  grep -Eq "^empty +- +- +- +-$" "$T/out" || { cat "$T/out"; fail "a folder with nothing in it"; }
  rm "$H/bin/sessions"; run "$T/none" project list; is 0 "a hub without bin/sessions"
  grep -Eq "^api +~/Project/api +main +- " "$T/out" || fail "no agent column without bin/sessions"
  run "$T/none" project list extra; is 2 "project list takes nothing"
}

project_help() {   # AC10: ade project alone prints the help
  proj_fixture
  run "$T/none" project; is 0 "ade project"
  assert_contains "$T/out" "ade project add <path-or-git-url>... [--name N] [--no-init] [--yes]" "the help"
  assert_contains "$T/out" "ade project add --scan <folder>" "scan"; assert_contains "$T/out" "ade project list" "list"
  run "$T/none" project help; is 0 "ade project help"
  run "$T/none" project bogus; is 2 "an unknown subcommand"
  run "$T/none" help; assert_contains "$T/out" "  project     ade project add" "ade help lists it"
  unset ADE_HUB; (cd "$T/cwd" && bash "$ADE" project list < "$T/none") > "$T/out" 2>&1; assert_eq "$?" 2 "no hub: exit 2"
  (cd "$T/cwd" && bash "$ADE" project add "$T/cwd" < "$T/none") > "$T/out" 2>&1; assert_eq "$?" 2 "no hub: nothing added"
}

ALL="adds_local_repo adds_two repos_of_reads_row adds_url code_folder existing_name_kept name_rules credentials_stripped credential_forms
init_offered_never_overwrites no_init_and_yes memory_indexed non_repo_fails_alone failure_asks_at_terminal
start_refused_in_agent_session start_at_terminal scan_picks lists_projects project_help"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
