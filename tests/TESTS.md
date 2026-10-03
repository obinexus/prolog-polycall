# Tests

- `run-real-core.sh` — the real-core runner. Sources `real-core-env.sh`
  (locates the installed core, builds the loader-failure fixtures, starts a
  `polycall start` runtime and a `polycall daemon` on ephemeral ports, sets a random `POLYCALL_DEV_TOKEN`), runs `make`,
  builds a second copy without RUNPATH (for the "core missing" check) and
  runs PlUnit (`run_polycall_tests`, exit 1 on any failure). Exit 77 =
  SKIPPED (no swipl / make / pkg-config / core), never success.
- `run-memcheck.sh asan|valgrind` — the same suite with the foreign library
  built with `-fsanitize=address,undefined` (ASan runtime preloaded into
  swipl), or the whole suite under valgrind memcheck; any sanitizer report,
  or a valgrind error / definite leak with a frame in `prolog_polycall` or
  `libpolycall`, fails the run.
- `prolog_polycall_tests.pl` — units `library` (version, ABI, strerror,
  per-thread last_error, missing core / old core / ABI 2 in child swipl
  processes), `config`, `call`, `peer` (both directions, payload matrix,
  registry ownership, duplicate id, auth, dead peer, timeout, too-small
  buffer, cancel / close waking blocked receivers in threads, handle
  lifecycle, invalid ids, 8 concurrent sender threads with backpressure
  retries), `interop` (`polycall peer serve` C node both directions, CLI
  `register` / `health`, `call` parity with the CLI client) and `boundaries`
  (timeouts outside `uint32`, capacity bounds and clamping, `int32` handles,
  NUL in text arguments, a non-ASCII configuration path). The entry point
  `run_polycall_tests` exits 77 without the runner environment and 1 unless
  every test ran and passed.
- `fixtures/fake_polycall.c` — loader-failure fixture only (old core, ABI 2).
- `run-package.sh` — `npm pack` (no compiled objects allowed), the tarball
  installed into a clean npm project, the JS entry point loaded, the foreign
  library built from the INSTALLED package with its Makefile, and the
  packaged examples plus a `polycall_call` run against the real core.
- `package.test.js` — npm / binding-manifest metadata (no Prolog).
