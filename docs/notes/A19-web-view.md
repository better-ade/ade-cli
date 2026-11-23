# A19 design note: `ade web`

- **Shape.** `cmd_web` (bash) reads the options, finds the hub as every command does, asks `tailscale` when `--tailnet`
  is given, and `exec`s `python3 -I -c` with the server (`web_py`, standard library only: `http.server`). The server
  picks the port, makes the token, writes the link file, prints the address and serves until a signal.
- **What an agent's log is.** A focus session writes no log file in the hub or its state folder (its transcript is
  Claude's own, outside both). So the log is what the hub does record about it: its lines in `<state>/events.jsonl`
  (from it, to it, to `all`) and its folder's `STATE.md`. The terminal's live text is not shown (out of scope).
- **Files.** One function opens files (`tail`): the last 256 KB of a regular file whose real path is under the hub
  (journal, `STATE.md`) or the state folder (`chat.log`, `events.jsonl`); a link that leaves the folder reads as
  empty. The paths are built by the server: two UTC dates, two fixed names, and `<hub>/<folder>/STATE.md` where the
  folder is a `projects/<name>` or `ops/<name>` that `bin/sessions` printed. The request gives only an agent's name,
  looked up in the current list; an unknown name is 404 before any path exists. `bin/sessions` is the only command run
  (at most every 2 s, 10 s limit); as with `ade status`, it prunes entries whose launcher is gone.
- **Redaction.** `send_json` is the only way data leaves and passes every string through `hide()`: the hub's rule
  copied from `bin/agent.py` (`ESCAPES`, then `HIDE`; `bin/lib.sh redact`, used by `bin/chat logs`), then ade's
  additions. The hub's rule runs first and unchanged, so whatever `bin/chat logs` hides is hidden here. It over-hides
  on purpose (any run of 32 letters and digits, such as a commit id; the value after `token:` or `key:`).
- **Fix round (adversarial review).** (1) The hub's `[A-Za-z0-9]{16,}\.[A-Za-z0-9_-]{8,}` is quadratic on one long
  run, and Python's `re` keeps the interpreter lock for a whole call: a 250,000-character line held every request and
  the signal handler for over a minute. A line is now cut to 4096 characters before any pattern runs (the piece of a
  word at the cut is dropped, the line ends in `[line cut]`), every repeat in ade's own patterns is bounded, and a
  hidden line is remembered (`lru_cache`, 2048 lines), since a log's last lines are mostly those of the request
  before. The worst file (256 KB of 4094-character runs) costs about 1.5 s once, in calls of about 20 ms each, so
  other requests and a stop get the lock in between. (2) Added: AWS access key ids, the user and password of a URL,
  names ending in `key` (so `aws_secret_access_key =`, `"privateKey":`, `?key=`), a quoted value to its closing
  quote, and private key blocks: `hide_lines` keeps the BEGIN/END state across the lines of one file, and an END
  whose BEGIN is above what was read takes the base64 lines before it too. (3) `ADE_WEB_OPENED` is removed: the
  server writes no file but its link file. "No file opened" is now shown by what is served: canary files the
  requests name, and files behind a folder or a link that leaves the hub, never appear in an answer. (4) Any cookie
  of the name may be the right one, so a planted `ade_web_<port>` cookie cannot lock the page.
- **Text, not HTML.** Answers are JSON with `<` written as `<`, `nosniff`, and a content security policy that
  allows only the page's own script and style (a nonce) and requests to itself. The page builds its nodes with
  `textContent`.
- **Polling, not server-sent events.** The page asks every 3 s (journal and chat log every 6 s) while it is in view.
  Each request is short and checked on its own (Host, cookie); nothing is held open, so Ctrl-C ends at once, a phone
  that sleeps and wakes just asks again, and there is no stream to re-authorise. The cost is a delay of up to 3 s.
- **Access.** 127.0.0.1 is reachable by every program and every browser tab on the machine, so the address carries a
  256-bit random token. `/?k=<token>` returns the page and a second random value as an HttpOnly, SameSite=Strict
  cookie (`ade_web_<port>`); the page then drops the token from the address bar. Every other route needs the cookie;
  the token itself opens nothing but `/`. The page is returned directly, not by a redirect, so a link opened from
  another site still works (a redirect would lose a Strict cookie). Host must be the served address (DNS rebinding);
  an API request a browser marks as cross-site is refused; no CORS header is ever sent. Not answered: another local
  server on `127.0.0.1` receives the cookie too (cookies ignore the port); it is a value only this server accepts and
  it is gone at the next start.
- **Tailnet.** The address comes from `tailscale ip -4` and must be one address in 100.64.0.0/10 (checked in bash and
  again in Python); the server binds that address and nothing else. `tailscale status --json` must say `Running`; its
  `Self.DNSName` is a second accepted Host. Plain HTTP: Tailscale encrypts between devices. Shared nodes, Funnel and
  ACLs are the owner's Tailscale settings; the message says anyone on the tailnet with the link can read.
- **Test switch.** A test has no tailnet address to bind, so `ADE_WEB_TEST_TAILNET_LOOPBACK=1` lets `--tailnet`
  accept a loopback address from the (fake) `tailscale`. It can only narrow where the server listens.
- **Link file.** `~/.config/ade/web`, 0600 in the 0700 folder: the server's pid, then the address. Removed on
  Ctrl-C, SIGTERM and SIGHUP. `--print-link` trusts it only while the pid lives and the address accepts a
  connection; otherwise it removes it. One `ade web` per user at a time.
- **Left out.** Tailscale in `ade setup --tools` (the message says how instead); the hub's Telegram `/status` using
  `--print-link` (a hub story); other files of `<state>/logs/`.
