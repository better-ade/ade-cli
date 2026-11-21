# ade-cli

`ade`: one command for ADE in any terminal. See docs/stories/A1-ade-command.md.

## Install

```
bash install.sh            # installs ~/.local/bin/ade
bash install.sh /usr/local # or into another prefix
```

## Usage

```
ade help                     # every command, one line each
ade work <task> --role <r>   # hub commands run the hub's bin/ scripts (status runs bin/sessions)
ade init [--here]            # copy ade-method (pinned tag) into the git top level (or here); never overwrites
ade agent list               # specialists in ade-agent-registry
ade agent add frontend       # copy one into .ade/agents/
ade skills add notes         # install an ade-skills plugin for this project
ade open ...                 # inside the ADE app only
```

The hub is `$ADE_HUB`, else the nearest folder above with `bin/lib.sh` and `hub.conf`, else the path in
`~/.config/ade/hub`. Pins: `ADE_METHOD_REF` (default `v2.0.0`), `ADE_REGISTRY_REF` (default `v1.1.0`); repos via
`ADE_METHOD_REPO` and `ADE_REGISTRY_REPO`. Tests: `bash tests/run.sh`.
