# TODO — prolog-polycall

Status: SWI-Prolog foreign library over the Polycall binding ABI v1 (libpolycall >= 1.1.0).

- [x] `src/prolog_polycall.c` includes the real `<polycall.h>`; linked via pkg-config, `-z now`
- [x] `run_config/2` keeps `polycall_ffi_run_config(Path, 1)`; `polycall_call/6`; `peer_*`
- [x] `error(polycall_error(Status, Name, Detail), _)`; ABI mismatch gate
- [x] PlUnit suite against the real core (Linux, swipl 10.1.16) incl. interop with the C CLI peer
- [x] Argument bounds (uint32 timeouts, int32 handles, capacity, NUL in text) as Prolog errors
- [x] ASan + UBSan and valgrind memcheck runs of the suite (tests/run-memcheck.sh)
- [ ] Windows build (MinGW + libswipl) and run
- [ ] Optionally package as an SWI-Prolog pack (pack.pl + prolog/)
- [ ] Publish `@obinexusltd/prolog-polycall`
