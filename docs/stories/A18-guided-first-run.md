# A18: the guided first run, an interactive guide in the terminal

Status: Ready for development (2026-11-22). Risk: medium (it runs the same commands a person would; it adds no new
access). Depends on A3 (`ade hub new`) and A5 (`ade setup`). Owner's intent (2026-11-22): "we need a guide for the user
so they can set this up", "an interactive cli", and "we need to require the github but we need to make it easy for
users to sign in". Verification command: `bash tests/run.sh`.

## What the owner's first test showed (2026-11-22, in a fresh computer)
- `ade` said only `no hub yet: run ade hub new <name>`; nothing led to `ade setup`.
- `ade hub new alvin` printed GitHub's own two lines about signing in, then `ade: gh could not create alvin`.
- The persona question wanted the exact name: `staff software engineer` was refused, the hub was left half made, and
  the message was a command with `<p> <c> <o>` in it.
- The update notice wrapped over three rows.

## Goal
A person who has never seen ADE types `ade` and is walked from nothing to a working hub: a list of steps with their
state, one step at a time, each said in a sentence or two, each checked before the next. A wrong answer is asked
again, never a failure. They can stop and come back.

## Acceptance criteria (`tests/test_guide.sh`, driven through a pseudo-terminal, with fakes for `claude`, `gh` and the hub; no network)
| AC | Criterion | Test |
|---|---|---|
| 1 | `ade` with no hub, at a terminal, prints the steps with each one's state (Claude Code, sign in to Claude, sign in to GitHub, your hub, your first project, Telegram: optional) and asks `Set up now? [Y/n]`; Enter starts the guide. Without a terminal it prints the same list and the command, and asks nothing | `guide_offers` |
| 2 | The guide (`ade setup`) starts at the first step that is not done, says before each step what it is and what it will change, and after it a line that it checked; run again, it resumes there | `guide_resumes` |
| 3 | Every question that has choices numbers them and accepts the number, the exact name, the name ignoring case, spaces, hyphens and underscores, or a prefix only one choice has. Anything else is asked again with one line saying what is accepted; Enter takes the default shown in brackets; end of input stops cleanly and says how to come back | `guide_choices_forgive` |
| 4 | GitHub is required, and signing in is one step of the guide: when `gh` is missing it offers to install it (after a yes); when it is not signed in it says in two lines why a hub needs GitHub (a private repo that keeps the hub's memory and lets it be restored) and runs GitHub's own browser sign-in on the person's terminal (`gh auth login` with the web flow: a one-time code to type at a GitHub address, on this machine or any other device), waits, checks who is signed in and says so by account name. It never asks for a password or a token and never reads one. If the sign-in does not finish, the guide stops there with one line saying how to come back; it never ends in GitHub's own error text and never offers a hub without GitHub | `guide_github_sign_in` |
| 5 | `ade hub new <name>` asks its questions the same forgiving way, runs the same GitHub sign-in step when it is needed (the `--no-github` flag stays for tests and is no longer offered in any message or in the help text), and cannot leave a half-made hub: when the hub's own set-up does not finish, running `ade hub new <name>` again picks up where it stopped, and the message says that in one line with no placeholders | `hub_new_forgives_and_resumes` |
| 6 | The update notice is one line that fits 80 columns: the version that is out, the one installed, and `ade update` | `notice_one_line` |
| 7 | In an ADE Computer (the image says so with a marker file the contract names) the first line names the guide, the GitHub step says the sign-in stays in this computer's home and offers to open the GitHub address in the computer's own browser, and the one-time code is shown large enough to copy by hand | `guide_in_computer` |
| 8 | The whole first run with fakes, from `ade` to a working hub, matches a recorded transcript at 80 columns | `guide_happy_path` |
| 9 | Answers are data: control characters, escape sequences, very long lines and a leading `-` are refused and asked again; added to the hostile-input table | `guide_hostile` |

## Out of scope
Connecting tools (A16 adds that step when it lands). Changing what `ade setup`'s later steps do (providers, the
guided Claude session). The questions inside the hub's own `bin/init` (ade-brain H3).
