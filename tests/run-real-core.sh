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
# SWI-Prolog maps file names through the locale: the non-ASCII path test
# needs a UTF-8 locale (C.UTF-8 is built into glibc >= 2.35)
[ -n "${LC_ALL:-}${LANG:-}" ] || { LANG=C.UTF-8; export LANG; }
SWIPL=${SWIPL:-swipl}
command -v "$SWIPL" >/dev/null 2>&1 || { echo "SKIP: swipl not found on PATH"; exit 77; }
command -v make >/dev/null 2>&1 || { echo "SKIP: make not found"; exit 77; }
command -v pkg-config >/dev/null 2>&1 || { echo "SKIP: pkg-config not found"; exit 77; }
. tests/real-core-env.sh
pkg-config --exists polycall || pc_skip "polycall.pc not found (PKG_CONFIG_PATH)"

# always rebuild: a lib/ left over from another SWI-Prolog version would
# otherwise be loaded as is (foreign ABI mismatch)
make -B SWIPL="$SWIPL" || { echo "FAIL: build"; exit 1; }
# a second build without RUNPATH, for the "core missing" check
make SWIPL="$SWIPL" FOREIGN="$POLYCALL_TEST_TMP/norpath/prolog_polycall.so" POLYCALL_LIBDIR= >/dev/null \
  || { echo "FAIL: norpath build"; exit 1; }
PROLOG_POLYCALL_NORPATH_DIR="$POLYCALL_TEST_TMP/norpath"
PROLOG_POLYCALL_REPO="$REPO"
export PROLOG_POLYCALL_NORPATH_DIR PROLOG_POLYCALL_REPO
"$SWIPL" --version
SUITE="-g run_polycall_tests -t halt tests/prolog_polycall_tests.pl"

# POLYCALL_TEST_SANITIZE (tests/run-memcheck.sh sets it):
#   asan      the foreign library built with -fsanitize=address,undefined,
#             the ASan runtime preloaded into swipl (which is not
#             instrumented); any ASan or UBSan report fails the run
#   valgrind  the whole suite under valgrind memcheck; any memory error or
#             definite leak with a frame in prolog_polycall or libpolycall
#             fails the run
case "${POLYCALL_TEST_SANITIZE:-}" in
  "")
    # shellcheck disable=SC2086
    "$SWIPL" -p foreign="$REPO/lib" $SUITE
    ;;
  asan)
    ASAN_DIR="$POLYCALL_TEST_TMP/asan"
    make SWIPL="$SWIPL" FOREIGN="$ASAN_DIR/prolog_polycall.so" \
      CFLAGS="-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize-recover=undefined" \
      || { echo "FAIL: ASan build"; exit 1; }
    ASAN_RT=$("$CC" -print-file-name=libasan.so)
    [ -e "$ASAN_RT" ] || pc_skip "libasan.so not found for $CC"
    LOG="$POLYCALL_TEST_TMP/asan.log"
    # shellcheck disable=SC2086
    LD_PRELOAD="$ASAN_RT" ASAN_OPTIONS="detect_leaks=0:use_sigaltstack=0:halt_on_error=1:abort_on_error=1" \
      UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=1" \
      "$SWIPL" -p foreign="$ASAN_DIR" $SUITE >"$LOG" 2>&1
    rc=$?
    cat "$LOG"
    if grep -E -q "ERROR: AddressSanitizer: |runtime error: " "$LOG"; then
      echo "FAIL: AddressSanitizer / UBSan report"; exit 1
    fi
    [ "$rc" = 0 ] || { echo "FAIL: suite exit $rc under ASan"; exit 1; }
    echo "ASan+UBSan: no reports"
    ;;
  valgrind)
    command -v valgrind >/dev/null 2>&1 || pc_skip "valgrind not found"
    LOG="$POLYCALL_TEST_TMP/valgrind.log"
    VG_PRELOAD=${LD_PRELOAD:-}
    if ldd "$(command -v "$SWIPL")" 2>/dev/null | grep -q tcmalloc; then
      # Distribution swipl builds (e.g. Debian) link tcmalloc and call its
      # MallocExtension_* hooks; with valgrind's malloc those hooks touch
      # uninitialised tcmalloc state and crash swipl. Stub the hooks out.
      printf '%s\n' '#include <stddef.h>' \
        'void MallocExtension_MarkThreadBusy(void) {}' \
        'void MallocExtension_MarkThreadIdle(void) {}' \
        'void MallocExtension_MarkThreadTemporarilyIdle(void) {}' \
        'void MallocExtension_ReleaseFreeMemory(void) {}' \
        'int MallocExtension_GetNumericProperty(const char *n, size_t *v) { (void)n; (void)v; return 0; }' \
        'int MallocExtension_SetNumericProperty(const char *n, size_t v) { (void)n; (void)v; return 0; }' \
        >"$POLYCALL_TEST_TMP/notcmalloc.c"
      "$CC" -shared -fPIC -o "$POLYCALL_TEST_TMP/notcmalloc.so" "$POLYCALL_TEST_TMP/notcmalloc.c" \
        || { echo "FAIL: building the tcmalloc hook stub"; exit 1; }
      VG_PRELOAD="$POLYCALL_TEST_TMP/notcmalloc.so"
    fi
    # shellcheck disable=SC2086
    LD_PRELOAD="$VG_PRELOAD" valgrind --tool=memcheck --leak-check=full --show-leak-kinds=definite \
      --soname-synonyms='somalloc=*tcmalloc*' \
      --num-callers=40 --log-file="$LOG" \
      "$SWIPL" -p foreign="$REPO/lib" $SUITE
    rc=$?
    cat "$LOG"
    # memory-error and definite-leak records with a frame in the binding or the core
    ours=$(awk '
      function flush() { if (inrec && rec ~ /prolog_polycall\.(so|c)|libpolycall\.so/) n++; inrec = 0; rec = "" }
      /^==[0-9]+== [^ ]/ {
        flush()
        inrec = ($0 ~ /== (Invalid|Conditional jump|Use of uninitialised|Syscall param|Mismatched|Source and destination|Argument|Process terminating)/ || $0 ~ /are definitely lost/)
        rec = $0; next
      }
      /^==[0-9]+== *$/ { flush(); next }
      { if (inrec) rec = rec "\n" $0 }
      END { flush(); print n + 0 }' "$LOG")
    grep -E "ERROR SUMMARY|definitely lost:" "$LOG" | tail -2
    [ "$rc" = 0 ] || { echo "FAIL: suite exit $rc under valgrind"; exit 1; }
    [ "$ours" = 0 ] || { echo "FAIL: $ours valgrind record(s) involving prolog_polycall / libpolycall"; exit 1; }
    echo "valgrind memcheck: no errors or definite leaks involving prolog_polycall / libpolycall"
    ;;
  *) echo "FAIL: unknown POLYCALL_TEST_SANITIZE=$POLYCALL_TEST_SANITIZE"; exit 1 ;;
esac
