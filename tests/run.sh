#!/bin/bash
cd "$(dirname "$0")" || exit 1; rc=0
echo "bash $(bash -c 'echo "$BASH_VERSION"') ($(command -v bash))"
for t in test_*.sh; do if out=$(bash "$t" 2>&1) && [ "$(echo "$out" | tail -1)" = ok ]; then echo "ok    $t"; else echo "FAIL  $t"; echo "$out" | tail -5; rc=1; fi; done
exit $rc
