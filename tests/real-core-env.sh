# Shared setup for the real-core test runners (sourced, POSIX sh).
#
# Locates the installed core (POLYCALL_PREFIX, default /opt/polycall, or a
# `polycall` already on PATH), builds the loader-failure fixtures, starts a
# `polycall start` runtime and a `polycall daemon` for polycall_call tests,
# and exports:
#   POLYCALL_CLI, POLYCALL_LIBRARY, POLYCALL_DEV_TOKEN (random test value),
#   POLYCALL_TEST_RPC_ENDPOINT, POLYCALL_TEST_DAEMON_ENDPOINT,
#   POLYCALL_TEST_FAKE_OLD, POLYCALL_TEST_FAKE_ABI2,
#   POLYCALL_TEST_TMP
# A missing core or compiler is a SKIP (exit 77), never a pass.

pc_skip() { echo "SKIP: $*"; exit 77; }

PREFIX=${POLYCALL_PREFIX:-/opt/polycall}
if [ -x "$PREFIX/bin/polycall" ]; then
  PATH="$PREFIX/bin:$PATH"
  LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  export PATH LD_LIBRARY_PATH PKG_CONFIG_PATH
fi
POLYCALL_CLI=$(command -v polycall 2>/dev/null) || pc_skip "polycall CLI not found (install the core or set POLYCALL_PREFIX)"
export POLYCALL_CLI
if [ -z "${POLYCALL_LIBRARY:-}" ] && [ -e "$PREFIX/lib/libpolycall.so.1" ]; then
  POLYCALL_LIBRARY="$PREFIX/lib/libpolycall.so.1"
fi
[ -n "${POLYCALL_LIBRARY:-}" ] && [ -e "$POLYCALL_LIBRARY" ] || pc_skip "libpolycall.so.1 not found (set POLYCALL_LIBRARY)"
export POLYCALL_LIBRARY
CC=${CC:-cc}
command -v "$CC" >/dev/null 2>&1 || CC=gcc
command -v "$CC" >/dev/null 2>&1 || pc_skip "no C compiler for the loader-failure fixtures"

export POLYCALL_TELEMETRY=off
POLYCALL_DEV_TOKEN="qa-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
export POLYCALL_DEV_TOKEN

POLYCALL_TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/polycall-test.XXXXXX")
export POLYCALL_TEST_TMP
PC_RT_PID=""
PC_DAEMON_DIR=""
pc_cleanup() {
  [ -n "$PC_RT_PID" ] && kill "$PC_RT_PID" 2>/dev/null
  [ -n "$PC_RT_PID" ] && wait "$PC_RT_PID" 2>/dev/null
  [ -n "$PC_DAEMON_DIR" ] && "$POLYCALL_CLI" daemon stop --state-dir "$PC_DAEMON_DIR/state" \
    "$PC_DAEMON_DIR/Polycallfile" >/dev/null 2>&1
  rm -rf "$POLYCALL_TEST_TMP"
}
trap pc_cleanup EXIT INT TERM

PC_FIXTURE=$(dirname "$0")/fixtures/fake_polycall.c
mkdir -p "$POLYCALL_TEST_TMP/fake-old" "$POLYCALL_TEST_TMP/fake-abi2"
"$CC" -shared -fPIC -Wl,-soname,libpolycall.so.1 -DFAKE_OLD_CORE "$PC_FIXTURE" \
  -o "$POLYCALL_TEST_TMP/fake-old/libpolycall.so.1" || { echo "FAIL: building fixture"; exit 1; }
"$CC" -shared -fPIC -Wl,-soname,libpolycall.so.1 -DFAKE_ABI=2 "$PC_FIXTURE" \
  -o "$POLYCALL_TEST_TMP/fake-abi2/libpolycall.so.1" || { echo "FAIL: building fixture"; exit 1; }
POLYCALL_TEST_FAKE_OLD="$POLYCALL_TEST_TMP/fake-old/libpolycall.so.1"
POLYCALL_TEST_FAKE_ABI2="$POLYCALL_TEST_TMP/fake-abi2/libpolycall.so.1"
export POLYCALL_TEST_FAKE_OLD POLYCALL_TEST_FAKE_ABI2

"$POLYCALL_CLI" start --endpoint 127.0.0.1:0 --endpoint-file "$POLYCALL_TEST_TMP/rt.ep" \
  >"$POLYCALL_TEST_TMP/runtime.log" 2>&1 &
PC_RT_PID=$!
pc_i=0
while [ ! -s "$POLYCALL_TEST_TMP/rt.ep" ] && [ $pc_i -lt 100 ]; do sleep 0.1; pc_i=$((pc_i + 1)); done
[ -s "$POLYCALL_TEST_TMP/rt.ep" ] || { echo "FAIL: polycall start did not bind: $(cat "$POLYCALL_TEST_TMP/runtime.log")"; exit 1; }
POLYCALL_TEST_RPC_ENDPOINT=$(tr -d '\r\n' <"$POLYCALL_TEST_TMP/rt.ep")
export POLYCALL_TEST_RPC_ENDPOINT

# a `polycall daemon` (background, private state dir, ephemeral port, auth
# token from POLYCALL_DEV_TOKEN -- which guards its control actions)
PC_DAEMON_DIR="$POLYCALL_TEST_TMP/daemon"
mkdir -p "$PC_DAEMON_DIR"
printf 'log_level=info\n' >"$PC_DAEMON_DIR/Polycallfile"
"$POLYCALL_CLI" daemon start --endpoint 127.0.0.1:0 --state-dir "$PC_DAEMON_DIR/state" \
  --auth-token-env POLYCALL_DEV_TOKEN "$PC_DAEMON_DIR/Polycallfile" >"$POLYCALL_TEST_TMP/daemon.out" 2>&1 \
  || { echo "FAIL: polycall daemon start: $(cat "$POLYCALL_TEST_TMP/daemon.out")"; exit 1; }
POLYCALL_TEST_DAEMON_ENDPOINT=$(sed -n 's/.*"endpoint":"\([^"]*\)".*/\1/p' "$PC_DAEMON_DIR/state/daemon.json")
[ -n "$POLYCALL_TEST_DAEMON_ENDPOINT" ] || { echo "FAIL: no daemon endpoint in daemon.json"; exit 1; }
export POLYCALL_TEST_DAEMON_ENDPOINT
echo "core: $("$POLYCALL_CLI" --version) at $POLYCALL_LIBRARY; runtime at $POLYCALL_TEST_RPC_ENDPOINT; daemon at $POLYCALL_TEST_DAEMON_ENDPOINT"
