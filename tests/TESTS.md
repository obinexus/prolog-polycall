# Tests

- `prolog_polycall_adapter_test.c` verifies exact path forwarding, validation
  mode `1`, null handling, and unchanged statuses without libpolycall.
- `prolog_polycall_tests.pl` exercises default/explicit paths, raw statuses,
  and structured `polycall_error(Status)` terms through SWI-Prolog's foreign
  interface when `swipl` and `swipl-ld` are present.
- `package.test.js` validates npm metadata and every published directory.
