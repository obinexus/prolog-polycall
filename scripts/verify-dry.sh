#!/usr/bin/env sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if grep -E -n 'fopen|open\(|CreateFile|sscanf|strtok|socket\(|connect\(' \
    "$root/src/prolog_polycall.c" "$root/src/prolog_polycall_foreign.c" \
    "$root/src/prolog_polycall.pl"; then
    echo "prolog-polycall must not parse configuration or implement runtime logic" >&2
    exit 1
fi

grep -F -q 'polycall_ffi_run_config(config_path, 1)' \
    "$root/src/prolog_polycall.c"
grep -F -q 'REP_UTF8' "$root/src/prolog_polycall_foreign.c"
grep -F -q 'polycall_error(Status)' "$root/src/prolog_polycall.pl"

echo "prolog-polycall thin-adapter check: PASS"
