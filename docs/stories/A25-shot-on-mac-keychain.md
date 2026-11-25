# A25: ade shot on macOS never waits on the login Keychain

Status: **Ready** (owner asked for the macOS fix in ade-cli, 2026-11-25). Risk: medium (a browser start flag; no
secret, no account).
Found by: ade-drill golden path on macos-latest (ade 0.2.10): "ade: the browser did not answer in time (Page.navigate);
nothing saved". ade-drill #11 (closed) showed it is not a slow first start: Chromium started in 3 s, then the page
load stalled.
Verification: `bash tests/run.sh`.

## Today and the gap
`ade shot` starts Playwright's Chromium (ade, Chrome class, around line 5630) without `--use-mock-keychain`. On macOS
Chromium then asks the login Keychain for its storage key when the page load starts its network side. Measured on a
Mac with a fresh HOME, the pane shot takes 5.6 s and 5.8 s without the flag and 0.9 s with it. On a machine where the
Keychain is locked or cannot answer (a CI runner, a session over SSH), the load waits until ade shot's time limit
runs out. Playwright itself always passes `--use-mock-keychain` on macOS.

## Goal
On macOS, ade shot starts Chromium with `--use-mock-keychain` and `--password-store=basic`, so a shot never touches the
person's Keychain (it holds nothing a shot needs: a fresh profile, no sign-ins).

## Acceptance criteria (tests in `tests/test_shot.sh`, fake Chromium that records its arguments)
1. macOS: the arguments include `--use-mock-keychain` and `--password-store=basic`.
2. Linux: neither flag is passed (unchanged).
3. The ade-drill golden path on macos-latest (ade main) passes "a picture arrives" (recorded in the PR from an ade-drill
   run with `GOLDEN_ADE_REF` at this branch).

## Out of scope
The Linux sandbox failure (A24); a longer time limit.
