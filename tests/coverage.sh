#!/bin/bash
# story A8 layer 8: line coverage of ade with kcov over tests/run.sh (Linux). Writes the report to $1 (default
# coverage/) and fails when the percentage drops below tests/coverage-floor.
set -u; cd "$(dirname "$0")/.." || exit 1; out="${1:-coverage}"; rm -rf "$out"
command -v kcov > /dev/null || { echo "coverage: kcov is not installed" >&2; exit 2; }
# kcov must get the script itself (its bash engine), not `bash script` (that traces the bash binary)
kcov --include-pattern=/ade --bash-handle-sh-invocation --bash-method=DEBUG "$out" tests/run.sh; rc=$?
[ "$rc" = 0 ] || { echo "coverage: the suite failed under kcov (exit $rc)" >&2; exit 1; }
pct="$(python3 - "$out" <<'PY'
import glob, json, os, sys
best = None
for f in glob.glob(os.path.join(sys.argv[1], "**", "coverage.json"), recursive=True):
    for e in json.load(open(f)).get("files", []):
        if os.path.basename(e.get("file", "")) == "ade":
            v = float(e.get("percent_covered", 0)); best = v if best is None else max(best, v)
print("" if best is None else "%.2f" % best)
PY
)"
[ -n "$pct" ] || { echo "coverage: no figure for ade in $out; files kcov saw:" >&2
  python3 -c 'import glob,json,sys; [print("  ", e.get("file"), e.get("percent_covered")) for f in glob.glob(sys.argv[1] + "/**/coverage.json", recursive=True) for e in json.load(open(f)).get("files", [])]' "$out" >&2; exit 1; }
floor="$(tr -d ' \n' < tests/coverage-floor)"
echo "coverage of ade: $pct% (floor $floor%)"
python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)' "$pct" "$floor" || { echo "coverage: below the floor" >&2; exit 1; }
