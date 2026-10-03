#!/bin/sh
# prolog-polycall: npm package check against the REAL installed core.
#
#   sh tests/run-package.sh
#
# npm pack, install the tarball into a clean temporary npm project, load its
# JS entry point, build the foreign library FROM THE INSTALLED PACKAGE with
# its Makefile and run the packaged examples with swipl. Needs npm/node,
# swipl, make, pkg-config, a C compiler and the core (POLYCALL_PREFIX,
# default /opt/polycall). Exit: 0 pass, 1 failure, 77 SKIPPED.
set -u
cd "$(dirname "$0")/.." || exit 1
for tool in npm node swipl make pkg-config; do
  command -v "$tool" >/dev/null 2>&1 || { echo "SKIP: $tool not found on PATH"; exit 77; }
done
[ -n "${LC_ALL:-}${LANG:-}" ] || { LANG=C.UTF-8; export LANG; }
. tests/real-core-env.sh
fail() { echo "FAIL: $*"; exit 1; }

PACKDIR="$POLYCALL_TEST_TMP/npm-pack"
mkdir -p "$PACKDIR"
TARBALL=$(npm pack --silent --pack-destination "$PACKDIR" | tail -1) || fail "npm pack"
tar -tzf "$PACKDIR/$TARBALL" | sed 's/^/  /'
if tar -tzf "$PACKDIR/$TARBALL" | grep -E -q '\.(so|dll|dylib|o)$'; then
  fail "the package contains compiled objects"
fi
NPROJ="$POLYCALL_TEST_TMP/npm-project"
mkdir -p "$NPROJ"
(cd "$NPROJ" && npm init -y >/dev/null && npm install --no-audit --no-fund "$PACKDIR/$TARBALL") || fail "npm install"
PKG="$NPROJ/node_modules/@obinexusltd/prolog-polycall"
(cd "$NPROJ" && node -e '
const b = require("@obinexusltd/prolog-polycall");
if (b.packageName !== "@obinexusltd/prolog-polycall") process.exit(1);
for (const f of [b.prologModule, b.foreignSource, b.makefile, b.config]) require("fs").accessSync(f);
console.log("npm entry point:", b.prologModule);') || fail "npm entry point"

make -C "$PKG" || fail "make in the installed package"
[ -f "$PKG/lib/prolog_polycall.so" ] || fail "no foreign library built in the installed package"
cd "$PKG" || exit 1
swipl -p foreign=lib examples/basic.pl prolog-polycallrc || fail "packaged examples/basic.pl"
swipl -p foreign=lib examples/peer.pl || fail "packaged examples/peer.pl"
swipl -p foreign=lib -g "use_module('src/prolog_polycall'),
    getenv('POLYCALL_TEST_RPC_ENDPOINT', EP),
    polycall_call(EP, inventory, get, '{\"item_id\":\"widget-a\"}', 2000, Out),
    ( Out == \"{\\\"item_id\\\":\\\"widget-a\\\",\\\"quantity\\\":42,\\\"in_stock\\\":true}\" -> true ; halt(1) ),
    format('installed package call: ~w~n', [Out])" -t halt || fail "polycall_call from the installed package"
echo "package checks: PASS"
