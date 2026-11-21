#!/bin/bash
# story A8 layer 8: line coverage of ade with kcov over the suite (Linux). Every `bash <ade>` the tests run goes through
# a bash wrapper that runs that one ade call under kcov (its own clean trace); the runs are merged into $1 (default
# coverage/). Fails when the suite fails or ade's line coverage drops below tests/coverage-floor.
set -u; cd "$(dirname "$0")/.." || exit 1; out="${1:-$PWD/coverage}"; rm -rf "$out"; mkdir -p "$out/runs"
command -v kcov > /dev/null || { echo "coverage: kcov is not installed" >&2; exit 2; }
real="$(command -v bash)"; kc="$(command -v kcov)"   # absolute: some tests narrow PATH
wrap="$(mktemp -d "${TMPDIR:-/tmp}/ade-cov.XXXXXX")" || exit 1
trap 'case "$wrap" in */ade-cov.?*) rm -rf -- "$wrap" ;; esac' EXIT
cat > "$wrap/bash" <<W
#!$real
# coverage wrapper: bash <this repo's ade> ... runs under kcov; anything else is plain bash
if [ -z "\${ADE_KCOV_INSIDE:-}" ] && [ "\${1:-}" = "$PWD/ade" ]; then
  shift; ADE_KCOV_INSIDE=1; export ADE_KCOV_INSIDE
  exec "$kc" --include-pattern=/ade "$out/runs/\$\$-\$RANDOM" "$PWD/ade" "\$@"
fi
exec "$real" "\$@"
W
chmod +x "$wrap/bash"
# the hostile-input table (hundreds of calls that stop at the first check) adds little coverage and most of the time
subset=""; for t in tests/test_*.sh; do t="${t#tests/}"; [ "$t" = test_hostile.sh ] || subset="$subset $t"; done
ADE_TESTS="$subset" PATH="$wrap:$PATH" "$real" tests/run.sh; rc=$?
[ "$rc" = 0 ] || { echo "coverage: the suite failed under kcov (exit $rc)" >&2; exit 1; }
kcov --merge "$out" "$out"/runs/* > /dev/null || { echo "coverage: kcov could not merge the runs" >&2; exit 1; }
pct="$(python3 - "$out/kcov-merged/coverage.json" <<'PY'
import json, os, sys
for e in json.load(open(sys.argv[1])).get("files", []):
    if os.path.basename(e.get("file", "")) == "ade":
        print(e.get("percent_covered", "")); break
PY
)"
[ -n "$pct" ] || { echo "coverage: no figure for ade in $out/kcov-merged" >&2; exit 1; }
floor="$(tr -d ' \n' < tests/coverage-floor)"
echo "coverage of ade: $pct% (floor $floor%, $(ls "$out/runs" | wc -l | tr -d ' ') ade runs merged)"
python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)' "$pct" "$floor" || { echo "coverage: below the floor" >&2; exit 1; }
