#!/bin/bash
cd "$(dirname "$0")" || exit 1; rc=0
echo "bash $(bash -c 'echo "$BASH_VERSION"') ($(command -v bash))"
for t in ${ADE_TESTS:-test_*.sh}; do   # ADE_TESTS: a subset (the coverage job skips the hostile table)
  if out=$(bash "$t" 2>&1) && [ "$(echo "$out" | tail -1)" = ok ]; then echo "ok    $t"; else echo "FAIL  $t"; echo "$out" | tail -5; rc=1; fi; done
exit $rc
