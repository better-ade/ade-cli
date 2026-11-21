#!/bin/bash
# story A8 layer 2: shellcheck at warning level over ade, install.sh and the e2e scripts, then a self-test that a
# planted warning really fails it. CI pins the shellcheck version (.github/workflows/ci.yml).
set -u; cd "$(dirname "$0")/.." || exit 1
command -v shellcheck > /dev/null || { echo "lint: shellcheck is not installed" >&2; exit 2; }
echo "shellcheck $(shellcheck --version | sed -n 's/^version: //p')"
shellcheck -S warning ade install.sh tests/e2e/*.sh || { echo "lint: warnings above" >&2; exit 1; }
p="$(mktemp -d)"; printf '#!/bin/bash\ncd /tmp\nrm -rf "$1"/*\n' > "$p/planted.sh"   # SC2164: cd without || exit
if shellcheck -S warning "$p/planted.sh" > /dev/null 2>&1; then rm -rf "$p"; echo "lint: self-test failed (a planted warning passed)" >&2; exit 1; fi
rm -rf "$p"; echo "lint: ok (and a planted warning fails)"
