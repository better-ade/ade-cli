# A19: `ade web`, a read-only view of agents and logs

Status: In review (2026-11-23). Risk: high (it serves logs that can hold customer code and context, over HTTP).
Depends on A1 (the hub is found as for every command). Owner's intent (2026-11-23): "is there a way we can run a web
view and show the logs?", then yes to (1) `ade web`, a read-only page on 127.0.0.1, and (2) the same page on the
owner's Tailscale network only, so their phone can open it. Not a Telegram Mini App, no public address, no tunnel.
Verification command: `bash tests/run.sh`. Design note: `docs/notes/A19-web-view.md`.

## Goal
- **`ade web [--port N]`**: a read-only page served by python3's standard library (no pip, no node), bound to
  127.0.0.1 only, on port 8765 when it is free, else a free one; it prints the address and runs in the foreground until
  Ctrl-C. The same inside an ADE Computer (the desktop's own browser). `ade` opens no browser.
- **The page** (one HTML document; no external script, font or CDN; fits a phone): the hub's agents and their state
  (the hub's `bin/sessions`, every 3 s), the picked agent's recent log (its events and its `STATE.md`), today's and
  yesterday's journal (UTC), the chat log. Live updates by polling.
- **Only the named files:** `<hub>/journal/<UTC date>.md` for two dates, `<state>/logs/chat.log`,
  `<state>/events.jsonl`, `<hub>/<folder>/STATE.md` for a folder `bin/sessions` listed. A path from the request never
  opens a file: the page names an agent from the list, the server maps the name to the paths it chose.
- **Redaction:** every line passes the hub's `bin/chat logs` rule (escape sequences and control characters removed, then
  Telegram bot tokens, `<id>.<secret>` keys, `sk-`-style keys, long opaque runs hidden), then ade's additions: `sk_`
  keys, GitHub tokens, `Authorization:` headers, bearer tokens, and the value after `password`, `passwd`, `secret`,
  `token` or `api key` plus `=` or `:`. Text reaches the page as JSON and is inserted as text, never as HTML.
- **Read-only:** GET only (anything else 405); no endpoint changes, starts or stops anything; the only hub command run
  is `bin/sessions`, as `ade status` runs it.
- **Access:** a random token in the printed address (`http://127.0.0.1:8765/?k=<random>`), kept as an HttpOnly,
  SameSite=Strict cookie from the first visit; without it 403 and no data. The Host header must be the address served
  (`127.0.0.1:<port>` or `localhost:<port>`); no CORS headers.
- **`ade web --tailnet`**: binds only to this machine's Tailscale IPv4 address (`tailscale ip -4`, which must be in
  100.64.0.0/10), never 0.0.0.0; the Host header must be that address or the machine's MagicDNS name
  (`tailscale status --json`, `Self.DNSName`). Refused, with how to get there, when Tailscale is missing or not signed
  in. It says plainly that anyone on the tailnet with the link can read these logs and that the link changes every
  start. `ade` never installs Tailscale or signs in to it.
- **`ade web --print-link`**: the running server's address (a 0600 file in `~/.config/ade`, removed on exit), else
  nothing and exit 1. For the hub's Telegram `/status` later.

## Acceptance criteria (`tests/test_web.sh`; fakes for `bin/sessions` and `tailscale`, a fixture hub with logs and a journal)
| AC | Criterion | Test |
|---|---|---|
| 1 | `ade web` prints `http://127.0.0.1:<port>/?k=<token>`, listens on 127.0.0.1 only (the listening socket is checked), takes 8765 or a free port, and `--port N` that port; a busy `--port` and a bad argument are refused | `t_local` |
| 2 | The token is required: `?k=<token>` gives the page and an HttpOnly, SameSite=Strict cookie; the cookie alone then works; a missing or wrong token or cookie is 403 with no data | `t_token` |
| 3 | A Host header other than `127.0.0.1:<port>` or `localhost:<port>` is 403; no response carries a CORS header | `t_host` |
| 4 | POST, PUT, DELETE, PATCH, OPTIONS and HEAD are 405; no request changes the fixture hub or its state folder (compared before and after) | `t_readonly` |
| 5 | The page is one document with no external address; the API lists the fake `bin/sessions` agents, an agent's events and `STATE.md`, today's and yesterday's journal and the chat log | `t_page` |
| 6 | Each secret pattern (built at run time from parts) is hidden in every section, the words around it kept | `t_redact` |
| 7 | Escape sequences and control characters never reach the browser; HTML in a log arrives as JSON text and the page inserts text only | `t_escapes` |
| 8 | An agent name not in the list, `../`, an absolute path and an unknown route are 404, and the server opens no file for them (its open trace is unchanged) | `t_paths` |
| 9 | `--tailnet` binds only to the fake Tailscale address and accepts only that address or the MagicDNS name as Host; refused when `tailscale` is missing, not signed in, or prints an address outside 100.64.0.0/10 | `t_tailnet` |
| 10 | `--print-link` prints the running server's address and exits 0, else prints nothing and exits 1; the link file is 0600 and gone after the server stops on a signal, the port free again | `t_link` |

## Out of scope
- A live copy of what an agent's terminal shows (focus sessions write no log file in the hub or its state folder;
  Claude's own transcripts are outside both). The agent's log is its events and its `STATE.md`.
- Any write, any control (start, stop, message), HTTPS, a public address, a tunnel, a Telegram Mini App.
- Adding Tailscale to `ade setup --tools`: `ade web --tailnet` says how to install and sign in instead.
