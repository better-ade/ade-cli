#!/bin/bash
cd "$(dirname "$0")" || exit 1; rc=0
echo "bash $(bash -c 'echo "$BASH_VERSION"') ($(command -v bash))"
# the real ~/.config/ade must not change while the suite runs (every test has its own HOME): a file that changes it fails
real_conf="$HOME/.config/ade"
conf_sum() { { find "$real_conf" -exec ls -ld {} + 2> /dev/null; find "$real_conf" -type f -exec cksum {} + 2> /dev/null; } | LC_ALL=C sort | cksum; }
for t in ${ADE_TESTS:-test_*.sh}; do   # ADE_TESTS: a subset (the coverage job skips the hostile table)
  before="$(conf_sum)"
  if out=$(bash "$t" 2>&1) && [ "$(echo "$out" | tail -1)" = ok ]; then echo "ok    $t"; else echo "FAIL  $t"; echo "$out" | tail -5; rc=1; fi
  [ "$(conf_sum)" = "$before" ] || { echo "FAIL  $t changed the real $real_conf (a test must use its own HOME)"; rc=1; }; done
exit $rc
