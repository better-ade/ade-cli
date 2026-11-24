#!/bin/bash
cd "$(dirname "$0")" || exit 1; rc=0
echo "bash $(bash -c 'echo "$BASH_VERSION"') ($(command -v bash))"
# the real ~/.config/ade must not change while the suite runs (every test has its own HOME). Compared: names, modes,
# sizes and modification times, never a file's content (it may hold a secret); a change fails the file that ran
real_conf="$HOME/.config/ade"
conf_list() { python3 -I -c '
import os, sys
for root, dirs, files in os.walk(sys.argv[1]):
    for n in dirs + files:
        p = os.path.join(root, n)
        try: st = os.lstat(p)
        except OSError: continue
        print("%s\t%o\t%d\t%d" % (p, st.st_mode, st.st_size, st.st_mtime_ns))' "$real_conf" 2> /dev/null | LC_ALL=C sort; }
for t in ${ADE_TESTS:-test_*.sh}; do   # ADE_TESTS: a subset (the coverage job skips the hostile table)
  before="$(conf_list)"
  if out=$(bash "$t" 2>&1) && [ "$(echo "$out" | tail -1)" = ok ]; then echo "ok    $t"; else echo "FAIL  $t"; echo "$out" | tail -5; rc=1; fi
  after="$(conf_list)"
  if [ "$after" != "$before" ]; then rc=1
    echo "FAIL  the real $real_conf changed while $t ran (a test must use its own HOME); changed:"
    printf '%s\n%s\n' "$before" "$after" | LC_ALL=C sort | uniq -u | cut -f1 | LC_ALL=C sort -u | sed '/^$/d; s/^/        /'
  fi
done
exit $rc
