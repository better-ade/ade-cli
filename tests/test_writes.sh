#!/bin/bash
# fix-record-writes: every file ade writes inside a project or hub checkout goes through one helper (ade_write): a temp
# file made with O_EXCL in the same folder, fsync, one rename; a target or a dot-folder (.ade, .claude) that is a link
# or not a regular file or folder is refused; a lock on the folder around read, check and write. A cloned repository
# is data: a link it commits never makes ade write outside it.
. "$(dirname "$0")/helpers.sh"

writes_fixture() {
  make_skills_repo; stub_claude; P="$T/proj"; mkdir -p "$P/.ade" "$P/.claude/skills/bmad-x"; git init -q "$P"
  echo "# x" > "$P/.claude/skills/bmad-x/SKILL.md"; echo '{}' > "$P/.claude/settings.json"
  echo keep > "$T/outside"; cd "$P" || fail "cd"
}
outside_kept() { assert_eq "$(cat "$T/outside")" keep "$1: the file outside the checkout is untouched"; }
regular() { [ -f "$1" ] && [ ! -L "$1" ] || fail "$2: $1 is a regular file"; }

connections_temp_link() {   # the reviewer's case for .ade/connections.json
  fresh; writes_fixture; ln -s "$T/outside" "$P/.ade/connections.json.ade-tmp"
  bash "$ADE" skills add notes > "$T/out" 2>&1 || { cat "$T/out"; fail "skills add"; }
  outside_kept "a planted temp link"; regular "$P/.ade/connections.json" "the record"
  grep -q '"notes"' "$P/.ade/connections.json" || fail "recorded"
}

connections_record_link() {   # the record itself a link: refused, nothing written through it
  fresh; writes_fixture; ln -s "$T/outside" "$P/.ade/connections.json"
  bash "$ADE" skills add notes > "$T/out" 2>&1
  outside_kept "a linked record"; [ -L "$P/.ade/connections.json" ] || fail "the link is left as it is"
  assert_contains "$T/out" "is not a regular file" "says why"
}

ade_folder_link() {   # .ade a link to a folder elsewhere: nothing is written there
  fresh; writes_fixture; rm -rf "$P/.ade"; mkdir "$T/elsewhere"; ln -s "$T/elsewhere" "$P/.ade"
  bash "$ADE" skills add notes > "$T/out" 2>&1
  [ -z "$(ls -A "$T/elsewhere")" ] || fail "nothing written into the linked folder"; assert_contains "$T/out" "is a symbolic link" "says why"
}

settings_temp_link() {   # .claude/settings.json (story A7)
  fresh; writes_fixture; ln -s "$T/outside" "$P/.claude/settings.json.ade-tmp"
  bash "$ADE" skills disable bmad-x > "$T/out" 2>&1 || { cat "$T/out"; fail "disable"; }
  outside_kept "a planted settings temp link"; regular "$P/.claude/settings.json" "settings"
  rm "$P/.claude/settings.json"; ln -s "$T/outside" "$P/.claude/settings.json"
  bash "$ADE" skills disable bmad-x > "$T/out" 2>&1; [ "$?" != 0 ] || fail "a linked settings file is refused"; outside_kept "a linked settings file"
  rm "$P/.claude/settings.json"; mv "$P/.claude" "$T/realclaude"; ln -s "$T/realclaude" "$P/.claude"; cp "$T/outside" "$T/before"
  bash "$ADE" skills disable bmad-x > "$T/out" 2>&1; [ "$?" != 0 ] || fail "a linked .claude is refused"
  [ ! -e "$T/realclaude/settings.json" ] || fail "nothing written into the linked .claude"
}

hub_settings_temp_link() {   # the hub's .claude/settings.json (ade claude, story A4)
  fresh; make_hub "$T/hub" hub; mkdir -p "$T/hub/.claude" "$T/fakebin"; echo keep > "$T/outside"
  printf '#!/bin/bash\nexit 0\n' > "$T/fakebin/claude"; chmod +x "$T/fakebin/claude"; export PATH="$T/fakebin:$PATH" ADE_HUB="$T/hub"
  ln -s "$T/outside" "$T/hub/.claude/settings.json.ade-tmp"
  bash "$ADE" claude > "$T/out" 2>&1 || { cat "$T/out"; fail "ade claude"; }
  outside_kept "the hub settings temp link"; regular "$T/hub/.claude/settings.json" "hub settings"
}

init_links() {   # ade init copies into the project: a committed link (dangling or not) or a linked .ade is refused
  fresh; make_method_repo; P="$T/proj"; mkdir -p "$P/.ade"; git init -q "$P"; cd "$P" || fail "cd"
  ln -s "$T/created-outside" "$P/.ade/rules.md"
  bash "$ADE" init > "$T/out" 2>&1; [ "$?" != 0 ] || fail "a dangling link is refused"
  [ ! -e "$T/created-outside" ] || fail "nothing created through the link"
  rm "$P/.ade/rules.md"; rmdir "$P/.ade"; mkdir "$T/elsewhere"; ln -s "$T/elsewhere" "$P/.ade"
  bash "$ADE" init > "$T/out" 2>&1; [ "$?" != 0 ] || fail "a linked .ade is refused"
  [ -z "$(ls -A "$T/elsewhere")" ] || fail "nothing written into the linked .ade"
  rm "$P/.ade"; bash "$ADE" init > "$T/out" 2>&1 || { cat "$T/out"; fail "a clean init"; }
  regular "$P/.ade/rules.md" "rules"; regular "$P/.ade/method-version" "method-version"
}

parallel_writers() {   # forty writers at once lose nothing
  fresh; writes_fixture
  python3 - "$K/.claude-plugin/marketplace.json" <<'PY'
import json, sys
json.dump({"name": "ade-skills", "plugins": [{"name": "p%d" % i, "description": "x"} for i in range(40)]}, open(sys.argv[1], "w"))
PY
  git -C "$K" commit -qam forty && git -C "$K" tag -f v0.1.0 > /dev/null
  local i; for i in $(seq 0 39); do bash "$ADE" skills add "p$i" > "$T/out.$i" 2>&1 & done; wait
  assert_eq "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["plugins"]))' "$P/.ade/connections.json")" 40 "every plugin recorded"
  [ -z "$(find "$P/.ade" -name '*ade-tmp*')" ] || fail "no temp file left"
}

fetch_never_prompts() {   # a fetch of a pinned repo never asks for a password nor reaches a credential helper
  fresh; mkdir -p "$T/fakebin"; export GIT_LOG="$T/git.log"
  printf '#!/bin/bash\nprintf "%%s\\n" "GIT_TERMINAL_PROMPT=${GIT_TERMINAL_PROMPT-unset}" "$@" >> "$GIT_LOG"\nexit 1\n' > "$T/fakebin/git"; chmod +x "$T/fakebin/git"
  P="$T/proj"; mkdir -p "$P"; cd "$P" || fail "cd"
  ADE_METHOD_REPO=https://example.invalid/r PATH="$T/fakebin:$PATH" bash "$ADE" init --here > "$T/out" 2>&1
  assert_contains "$GIT_LOG" "GIT_TERMINAL_PROMPT=0" "no password prompt"; assert_contains "$GIT_LOG" "credential.helper=" "no credential helper"
}

ALL="connections_temp_link connections_record_link ade_folder_link settings_temp_link hub_settings_temp_link init_links parallel_writers fetch_never_prompts"
for t in ${1:-$ALL}; do ( $t ) || exit 1; done
echo ok
