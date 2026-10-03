#!/bin/sh
# prolog-polycall: build the SWI-Prolog foreign library against the installed
# core (pkg-config) and run the PlUnit suite against the REAL core.
#
#   sh tests/run-real-core.sh
#
# Needs swipl (SWI-Prolog >= 9 with plunit, process, json), make, a C
# compiler, pkg-config and the core (POLYCALL_PREFIX, default
# /opt/polycall). Exit: 0 pass, 1 failure, 77 SKIPPED (a missing toolchain
# is never reported as success).
set -u
cd "$(dirname "$0")/.." || exit 1
REPO=$(pwd)
SWIPL=${SWIPL:-swipl}
command -v "$SWIPL" >/dev/null 2>&1 || { echo "SKIP: swipl not found on PATH"; exit 77; }
command -v make >/dev/null 2>&1 || { echo "SKIP: make not found"; exit 77; }
command -v pkg-config >/dev/null 2>&1 || { echo "SKIP: pkg-config not found"; exit 77; }
. tests/real-core-env.sh
pkg-config --exists polycall || pc_skip "polycall.pc not found (PKG_CONFIG_PATH)"

make SWIPL="$SWIPL" || { echo "FAIL: build"; exit 1; }
# a second build without RUNPATH, for the "core missing" check
make SWIPL="$SWIPL" FOREIGN="$POLYCALL_TEST_TMP/norpath/prolog_polycall.so" POLYCALL_LIBDIR= >/dev/null \
  || { echo "FAIL: norpath build"; exit 1; }
PROLOG_POLYCALL_NORPATH_DIR="$POLYCALL_TEST_TMP/norpath"
PROLOG_POLYCALL_REPO="$REPO"
export PROLOG_POLYCALL_NORPATH_DIR PROLOG_POLYCALL_REPO
"$SWIPL" --version
"$SWIPL" -p foreign="$REPO/lib" -g run_polycall_tests -t halt tests/prolog_polycall_tests.pl
