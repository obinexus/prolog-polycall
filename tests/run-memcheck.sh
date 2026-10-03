#!/bin/sh
# prolog-polycall: run the real-core PlUnit suite with memory tooling on the
# C foreign library (src/prolog_polycall.c).
#
#   sh tests/run-memcheck.sh asan       # -fsanitize=address,undefined shim, ASan preloaded
#   sh tests/run-memcheck.sh valgrind   # whole suite under valgrind memcheck
#
# Same prerequisites and exit codes as tests/run-real-core.sh (0 pass,
# 1 failure or sanitizer report, 77 SKIPPED when a tool is missing).
set -u
case "${1:-asan}" in
  asan | valgrind) ;;
  *) echo "usage: sh tests/run-memcheck.sh [asan|valgrind]"; exit 2 ;;
esac
POLYCALL_TEST_SANITIZE=${1:-asan}
export POLYCALL_TEST_SANITIZE
exec sh "$(dirname "$0")/run-real-core.sh"
