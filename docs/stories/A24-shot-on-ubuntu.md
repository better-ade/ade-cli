# A24: ade shot works on Ubuntu 23.10+, and says why when Chromium will not start

Status: **Ready** (owner chose this fix, 2026-11-25). Risk: medium (a browser's sandbox flag; no secret, no account).
Found by: ade-drill #10 CI: the golden path's "a picture arrives" fails on ubuntu-latest for ade 0.2.10 and main
("ade: the browser closed before it answered; nothing saved"); the same drill passes on macOS.
Verification: `bash tests/run.sh`.

## Today and the gap
`ade shot` starts Playwright's Chromium with its sandbox on when `unshare -U true` succeeds (ade, Chrome class,
around line 5636). On Ubuntu 23.10+ AppArmor (`kernel.apparmor_restrict_unprivileged_userns=1`) lets `unshare -U`
succeed but the namespace has no rights, so Chromium's sandbox fails and Chromium exits at once. Its stderr goes to
/dev/null, so the person (and the drill) see only "the browser closed before it answered". Real Ubuntu 24.04 users hit
this too.

## Goal
On Linux, a Chromium that exits before answering is started once more with `--no-sandbox` (the choice ade already
makes where no user namespace can be made); its stderr is kept (a file in ade's state, the last lines in the error) so
any other failure says why.

## Acceptance criteria (tests in `tests/test_shot.sh`, fake Chromium)
1. Linux, `unshare` succeeds, a fake Chromium that exits at once without `--no-sandbox` and works with it: the shot is
   saved, started twice, the second time with `--no-sandbox`.
2. A fake Chromium that always exits at once: the error names the last lines it wrote to stderr; nothing saved.
3. macOS: no retry, no `--no-sandbox` (unchanged).
4. The ade-drill golden path on ubuntu-latest (ade main) passes "a picture arrives" (recorded in the PR from an
   ade-drill run with `GOLDEN_ADE_REF` at this branch).

## Out of scope
An AppArmor profile for Chromium; system browsers.
