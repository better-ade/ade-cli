#!/bin/bash
cd "$(dirname "$0")"; rc=0
for t in test_*.sh; do if out=$(bash "$t" 2>&1) && [ "$(echo "$out" | tail -1)" = ok ]; then echo "ok    $t"; else echo "FAIL  $t"; echo "$out" | tail -5; rc=1; fi; done
exit $rc
