# M2: `ade web` asks for an auth code before it shows anything

Status: **Approved** (owner, 2026-11-27: "Approve m2"). Risk: **high** (sign-in to a page that shows hub data).
Found by: the owner (2026-11-27): "the web needs to have an auth code"; then chose "a code on this computer" (asked
every time the page is opened, shown in ade's terminal) over remote sign-in or a saved passcode.
Verification: `bash tests/run.sh`.
Depends on: M1 (merged).

## Today
`ade web` serves on 127.0.0.1 (or, with `--tailnet`, this machine's Tailscale address). Whoever has the link (its
random `?k=` token) can read the dashboard. ade opens the link in your browser itself, but the link can leak: browser
history or sync, a screen share, `--print-link`, or (with `--tailnet`) a phone it was sent to.

## Goal
The link alone is no longer enough. Each start of `ade web` prints a short auth code in its own terminal, and the page
shows a code prompt until it is typed in. The prompt is styled as a terminal line, like the rest of the page. Only the
link plus the code opens the dashboard.

## Acceptance criteria (each named by its test in tests/test_web.sh)
1. **code_required**: with the right link but no code, the page shows only the code prompt. Every `/api/*` route
   answers 401, and no hub command runs.
2. **code_unlocks**: posting the right code (POST `/login`, the only non-GET route) gives a session cookie. The
   dashboard and the API then work as in M1, and the M1 token and Origin checks still apply.
3. **code_shown_on_terminal_only**: the code is written to the controlling terminal (`/dev/tty`), never to stdout,
   stderr, a log, a file or a command line. It is 8 characters from an alphabet with no look-alikes (no 0/O, 1/l/I),
   made by a cryptographic random source, and compared in constant time. With no terminal (piped, or in an agent
   session), `ade web` refuses to start and says why (exit 2).
4. **code_new_each_start**: every start makes a new code. A cookie from an earlier run is refused.
5. **code_lockout**: after 5 wrong codes the code is used up. Every login is refused until the owner presses Enter in
   ade's terminal, which prints a fresh code. Wrong tries are counted per run, not per client.
6. **code_session_ends**: the session cookie is HttpOnly, SameSite=Strict, kept to the page's path, and expires after
   12 hours or when the server stops, whichever comes first. A `q`-style "lock" key on the page drops it.
7. **code_tailnet_too**: `--tailnet` asks for the code in the same way. Its start message says that the code is needed
   as well as the link.
8. **code_page_premium**: the prompt is a terminal line (`ade web · enter the code shown in your terminal: █`),
   keyboard first, in both themes and at phone width. A wrong code shows `✖ wrong code (n of 5 left)`; after a
   lockout it shows `locked: press Enter in ade's terminal for a new code`. Screenshots (dark, light, phone) are saved
   for the owner.
9. **code_no_hub_writes**: the M1 rule still holds: a whole test run leaves the hub, its state folder and the real
   `~/.config/ade` unchanged.

## Out of scope
- Sign-in from outside this machine and the tailnet, accounts, or a saved passcode (the owner chose against it).
- Acting from the page.
- The terminal `ade dash`.
