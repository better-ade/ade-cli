#!/bin/bash
# story A8 layer 8: line coverage of ade over the suite (bash 4.1+, so Linux CI). Every bash that runs this repo's ade,
# or a copy of it, traces it (BASH_ENV: PS4 carries the line and the file it is in, BASH_XTRACEFD a per-process file,
# never the test's own output); the executed lines are compared with ade's executable lines. A copy is an installed or
# downloaded ade (install.sh, ade update, its .ade.prev) that is this repo's ade byte for byte once its stamped
# ADE_VERSION="x.y.z" is put back to ADE_VERSION="": the stamp is made in place, so its line numbers are ade's. Anything
# else (another version, a fake, a cut-short file) is not traced. Lines run from a file ade sources (hub.conf) are not
# ade's and are not counted. Writes $1 (default coverage/): coverage.json, a line report, the raw traces. Fails when the
# suite fails, when install.sh's stamped copy is no longer recognised as a copy, or when the percentage drops below
# tests/coverage-floor.
# (kcov, the story's first choice, needed one kcov per ade call here, which took over 25 minutes for one test file.)
set -u; cd "$(dirname "$0")/.." || exit 1; out="${1:-$PWD/coverage}"
case "$out" in */coverage) rm -rf -- "$out" ;; esac; mkdir -p "$out/traces"
env_file="$out/bash_env"
# a copy's version stamp put back (install.sh and ade update both stamp ADE_VERSION="" in place, on its own line)
unstamp_sed='s/^ADE_VERSION="[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"/ADE_VERSION=""/'
unstamp() { sed "$unstamp_sed" "$1"; }
{ IFS= read -r l1; IFS= read -r l2; } < ade
# the check the copies rely on: install.sh's stamped ade must come back to this ade, line for line
mkdir -p "$out/stamp-check"; ADE_CLI_REF="" bash install.sh "$out/stamp-check" > /dev/null || { echo "coverage: install.sh failed" >&2; exit 1; }
grep -q '^ADE_VERSION="[0-9]' "$out/stamp-check/bin/ade" || { echo "coverage: install.sh no longer stamps ADE_VERSION" >&2; exit 1; }
unstamp "$out/stamp-check/bin/ade" | cmp -s - ade || { echo "coverage: an installed ade no longer maps line for line to ade; update unstamp" >&2; exit 1; }
rm -rf -- "$out/stamp-check"
cat > "$env_file" <<E
# sourced by every non-interactive bash of the suite: trace $PWD/ade, or a stamped copy of it, into its own file
if [ -z "\${ADE_COV_ON:-}" ] && [ "\${BASH_VERSINFO[0]}\${BASH_VERSINFO[1]}" -ge 41 ] 2> /dev/null; then
  ADE_COV_KIND=""
  if [ "\$0" = "$PWD/ade" ]; then ADE_COV_KIND=repo
  elif [ -f "\$0" ] && { IFS= read -r ADE_COV_L1; IFS= read -r ADE_COV_L2; } < "\$0" 2> /dev/null &&
       [ "\$ADE_COV_L1" = $(printf '%q' "$l1") ] && [ "\$ADE_COV_L2" = $(printf '%q' "$l2") ] &&
       sed '$unstamp_sed' "\$0" 2> /dev/null | cmp -s - "$PWD/ade"; then
    ADE_COV_KIND=copy
  fi
  if [ -n "\$ADE_COV_KIND" ]; then
    ADE_COV_ON=1; exec {ADE_COV_FD}>>"$out/traces/\$ADE_COV_KIND.\$\$.\$RANDOM"; BASH_XTRACEFD=\$ADE_COV_FD
    printf 'ADECOV-SELF:%s\\n' "\$0" >&\$ADE_COV_FD
    PS4='+ADECOV:\${LINENO}:\${BASH_SOURCE[0]-}: '; set -x
  fi
  unset ADE_COV_KIND ADE_COV_L1 ADE_COV_L2
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
hit, by, runs = set(), {"repo": set(), "copy": set()}, {"repo": 0, "copy": 0}
for f in glob.glob(os.path.join(out, "traces", "*")):
    kind = os.path.basename(f).split(".")[0]; fh = open(f, encoding="utf-8", errors="replace")
    head = fh.readline()
    if kind not in by or not head.startswith("ADECOV-SELF:"): sys.exit("coverage: unexpected trace file " + f)
    self_path = head[len("ADECOV-SELF:"):].rstrip("\n"); runs[kind] += 1
    pre = re.compile(r"\++ADECOV:(\d+):" + re.escape(self_path) + ": ")   # a line of the traced file, not one it sourced
    for t in fh:
        m = pre.match(t)
        if m:
            n = int(m.group(1))
            if n > len(lines): sys.exit("coverage: line %d past the end of ade in %s" % (n, f))
            hit.add(n); by[kind].add(n)
covered = exe & hit; pct = 100.0 * len(covered) / max(1, len(exe))
json.dump({"file": "ade", "executable_lines": len(exe), "covered_lines": len(covered), "percent_covered": round(pct, 2),
           "traced_runs": runs, "covered_only_by_copies": len((exe & by["copy"]) - by["repo"]),
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
