# Tests

- `run-real-core.sh` — the real-core runner. Sources `real-core-env.sh`
  (locates the installed core, builds the loader-failure fixtures, starts a
  `polycall start` runtime, sets a random `POLYCALL_DEV_TOKEN`), runs `make`,
  builds a second copy without RUNPATH (for the "core missing" check) and
  runs PlUnit (`run_polycall_tests`, exit 1 on any failure). Exit 77 =
  SKIPPED (no swipl / make / pkg-config / core), never success.
- `prolog_polycall_tests.pl` — units `library` (version, ABI, strerror,
  per-thread last_error, missing core / old core / ABI 2 in child swipl
  processes), `config`, `call`, `peer` (both directions, payload matrix,
  registry ownership, duplicate id, auth, dead peer, timeout, too-small
  buffer, cancel / close waking blocked receivers in threads, handle
  lifecycle, invalid ids, 8 concurrent sender threads with backpressure
  retries) and `interop` (`polycall peer serve` C node both directions, CLI
  `register` / `health`, `call` parity with the CLI client).
- `fixtures/fake_polycall.c` — loader-failure fixture only (old core, ABI 2).
- `package.test.js` — npm / binding-manifest metadata (no Prolog).
