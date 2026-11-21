# A3 design note: `ade hub new`, the curl install and `ade` alone

- Every refusal (bad name, existing folder, `gh` missing without `--no-github`) happens before anything is created.
- `--dir` is made absolute against the current folder; the hub is `<dir>/<name>`. `--no-github` clones the template
  (`ADE_HUB_TEMPLATE_URL`, default `https://github.com/better-ade/ade-brain`) and removes `origin`.
- The default is saved only after `bin/init` succeeded and wrote `hub.conf`; a failed `bin/init` says how to re-run it.
- `ade` alone: no hub prints the `ade hub new` hint and exits 0; a broken `ADE_HUB` or config path is also shown on
  stderr. With a hub: its name, `bin/sessions`, three next commands.
- `install.sh` keeps the checkout mode (tests, dev) and adds the piped mode; `ADE_CLI_BASE` (tests: a `file://` tree)
  and `ADE_CLI_REF` (a given release tag) override the source. The new binary is written beside the old one and moved
  over it, so a failed download leaves the old one.
- ade-brain's `bin/init` is not interactive: it needs `--persona`, `--client` and `--owner`. `ade hub new` takes them as
  flags and asks for the missing ones (listing `bin/init --list` first), then runs `bin/init --persona P --client C
  --owner O --name <name>`. Checked by hand against the real template: the hub initializes and becomes the default.
