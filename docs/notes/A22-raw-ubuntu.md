# A22 design note: a raw Ubuntu machine installs and sets up ADE

Story: [A22](../stories/A22-raw-ubuntu.md). Risk: high (sudo apt-get on the person's machine). Contract:
`.ade/context/hub-interface.md`, the Tools lines.

## Cause of the server's "release.json ... is not valid ()"
install.sh reads release.json with `python3 -c ... 2> /dev/null || true`. On a bare `ubuntu:24.04` there is no
python3, so the command fails, the error is swallowed, `want` is empty, and the empty answer falls into the
"not valid" branch with nothing in the brackets. The manifest itself was fine.

## Shape
- install.sh: `fetch` (curl, else wget) for the three downloads; `need_tools curl python3` before the first one (curl
  counts as there when wget is). A missing tool is named in one line; with apt at a terminal one question shows the
  whole command, and a yes runs `apt-get update`, then `apt-get install -y`, with sudo unless root, from /dev/tty (the
  script itself is on stdin). No apt, no sudo, no terminal or a no: the command is named and nothing is installed.
  The checkout install needs neither, so it is unchanged.
- ade: curl joins the required tools (before bun, which bun_fetch downloads with it). `pkgs_install` on apt always runs
  `apt-get update` first and says so in its one question; a failed update stops before the install, in one line. The
  old "run apt-get update first" advice is gone because the update has already run.
- The guide: `guide_git_identity` runs before the hub step only when a hub is about to be made. It asks for what git
  lacks (name, email; the email is asked again until it looks like one) and sets it with `git config --global`. Known
  means in git's config, or in both GIT_AUTHOR_* and GIT_COMMITTER_* (what the suite sets); git's own user@host guess
  is not counted, so a raw machine is always asked.
- README: the Ubuntu line (`sudo apt-get update && sudo apt-get install -y curl git python3`) and a wget one line. The
  curl line stays first, where the drill reads it.

## Not here
The tzdata time-zone question apt asks in a bare container (a real Ubuntu has tzdata). The second apt question on a
server (install.sh asks for curl and python3; `ade setup --tools` for the rest), kept so install.sh does not copy
ade's tool list. Relaying terminal-only steps to Telegram.
