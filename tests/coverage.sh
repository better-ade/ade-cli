#!/bin/bash
# story A8 layer 8: line coverage of ade over the suite (bash 4.1+, so Linux CI). Every bash that runs this repo's ade
# traces it (BASH_ENV: PS4 carries the line, BASH_XTRACEFD a per-process file, never the test's own output); the
# executed lines are compared with ade's executable lines. Writes $1 (default coverage/): coverage.json, a line report,
# the raw traces. Fails when the suite fails or the percentage drops below tests/coverage-floor.
# (kcov, the story's first choice, needed one kcov per ade call here, which took over 25 minutes for one test file.)
set -u; cd "$(dirname "$0")/.." || exit 1; out="${1:-$PWD/coverage}"
case "$out" in */coverage) rm -rf -- "$out" ;; esac; mkdir -p "$out/traces"
env_file="$out/bash_env"
cat > "$env_file" <<E
# sourced by every non-interactive bash of the suite: trace only $PWD/ade, into its own file
if [ "\$0" = "$PWD/ade" ] && [ -z "\${ADE_COV_ON:-}" ]; then
  ADE_COV_ON=1; exec {ADE_COV_FD}>>"$out/traces/\$\$.\$RANDOM"; BASH_XTRACEFD=\$ADE_COV_FD
  PS4='+ADECOV:\${LINENO}: '; set -x
fi
E
BASH_ENV="$env_file" bash tests/run.sh; rc=$?
[ "$rc" = 0 ] || { echo "coverage: the suite failed while traced (exit $rc)" >&2; exit 1; }
pct="$(python3 - "$PWD/ade" "$out" <<'PY'
import glob, json, os, re, sys
src, out = sys.argv[1], sys.argv[2]
lines = open(src, encoding="utf-8").read().split("\n")
exe, here = set(), None
for i, l in enumerate(lines, 1):
    s = l.strip()
    if here is not None:
        if s == here: here = None
        continue
    m = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", l)
    if s and not s.startswith("#") and not re.fullmatch(r"(\}|fi|done|esac|;;|else|then|do|\{|\)|in)", s) \
       and not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*\(\)\s*\{.*", s) and not re.fullmatch(r"[^()]*\)\s*", s):
        exe.add(i)
    if m and "<<<" not in l: here = m.group(1)
hit = set()
for f in glob.glob(os.path.join(out, "traces", "*")):
    for t in open(f, encoding="utf-8", errors="replace"):
        m = re.match(r"\++ADECOV:(\d+): ", t)
        if m: hit.add(int(m.group(1)))
covered = exe & hit; pct = 100.0 * len(covered) / max(1, len(exe))
json.dump({"file": "ade", "executable_lines": len(exe), "covered_lines": len(covered), "percent_covered": round(pct, 2),
           "missed": sorted(exe - hit)}, open(os.path.join(out, "coverage.json"), "w"), indent=1)
with open(os.path.join(out, "report.txt"), "w") as r:
    for i in sorted(exe):
        r.write("%s %5d  %s\n" % ("+" if i in hit else "-", i, lines[i - 1]))
print("%.2f" % pct)
PY
)" || { echo "coverage: could not compute the figure" >&2; exit 1; }
floor="$(tr -d ' \n' < tests/coverage-floor)"
echo "coverage of ade: $pct% of its executable lines (floor $floor%); report in $out/report.txt"
python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)' "$pct" "$floor" || { echo "coverage: below the floor" >&2; exit 1; }
