# A22: a raw Ubuntu machine installs and sets up ADE with no surprises

Status: In review (2026-11-24). Risk: high (it runs `sudo apt-get` on the person's machine).
Owner's intent (2026-11-24): "it needs to be seamless in a raw ubuntu server ... ubuntu desktop ... if someone bought a
mini pc with ubuntu, they can just install this without any issues."

Evidence: ade-drill D4 (`drills/raw-ubuntu.sh`) on a bare `ubuntu:24.04`, server and desktop, with ade v0.2.8:
1. Server, the one-line install: `install: the release.json of ade v0.2.8 is not valid (); nothing installed`. The
   cause: install.sh reads release.json with `python3`, the image has none, and the error is swallowed, so the empty
   answer reads as an invalid manifest.
2. `bash: git: command not found`, then `E: Unable to locate package git`: the README lists no prerequisites, and
   nothing says `apt-get update`.
3. `ade setup`: `line 4097: curl: command not found` while installing bun; curl is not one of the required tools.
4. The hub's first save stops with "git has no name and email yet", and the guide stops at "What now?".

## Goal
With only the README's own lines, a person on a raw Ubuntu 24.04 server or desktop gets from install to a working
`ade setup` without hitting any of these. The one-line install works with what Ubuntu ships (the desktop has wget and
python3 but no curl or git; the server has neither); every missing tool is found up front, named in one plain line,
and installed after a yes with `sudo apt-get update && sudo apt-get install -y`; the guide asks for the git name and
email in its own flow; the README lists what Ubuntu needs.

## Acceptance criteria (`tests/test_ubuntu.sh`: fakes for apt-get, sudo, curl and wget, a file:// release, no network; AC6 in `tests/test_guide.sh`, with the guide's fakes and no git identity)
| AC | Criterion | Test |
|---|---|---|
| 1 | The one-line install downloads with wget when there is no curl (Ubuntu Desktop): it installs the release, sha256 checked, and never says curl is needed | `install_with_wget` |
| 2 | Before any download, install.sh names in one plain line each tool it lacks (curl or wget, python3); a missing python3 is never reported as an invalid release.json | `install_names_missing_first` |
| 3 | At a terminal on apt, install.sh asks once and, after a yes, runs `sudo apt-get update`, then `sudo apt-get install -y <them>`, then installs ade; a no, no terminal or no apt runs nothing, names the command and installs nothing | `install_apt_after_yes` |
| 4 | curl is a required tool: `ade setup --tools` and the guide name it with the others in one line and install it before bun, so bun's download never meets a missing curl | `curl_is_required` |
| 5 | ade's apt installs say and run `sudo apt-get update && sudo apt-get install -y <packages>` (no sudo as root); without sudo it names the root command and runs nothing; a failed update or install is one plain line | `apt_update_then_install` |
| 6 | When git has no name or email, the guide asks for both before the hub step (an email must look like one), sets them with `git config --global`, and the hub's first save goes through; with an identity already it asks nothing | `guide_asks_git_identity` |
| 7 | The README's Install section lists what Ubuntu needs (`sudo apt-get update && sudo apt-get install -y curl git python3`) and a `wget` one-line install with the same URL as the `curl` one | `readme_lists_ubuntu` |

## Out of scope
Relaying the terminal-only steps to Telegram (a separate story). The tzdata time-zone question apt asks when it
pulls tzdata into a bare container. Other package managers than apt and Homebrew. ade-drill's own changes (it parses
`This runs: apt-get install` and reads only the README's `curl` line).
