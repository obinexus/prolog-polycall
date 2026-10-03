# prolog-polycall

SWI-Prolog binding for the [Polycall](https://github.com/obinexus/polycall)
core's **binding ABI v1** (`polycall.h`, libpolycall >= 1.1.0): configuration
validation, `polycall_rpc` calls and peer-to-peer nodes. npm source
distribution `@obinexusltd/prolog-polycall` (not published yet).

`src/prolog_polycall.c` is a SWI-Prolog foreign library that includes the
real `<polycall.h>` and links the core through pkg-config;
`src/prolog_polycall.pl` is the Prolog module. Configuration parsing, the
wire protocols and the peer transport stay in libpolycall.

## Build

Requirements: SWI-Prolog >= 9 (`swipl`, headers), a C11 compiler, make,
pkg-config, and the Polycall core >= 1.1.0 installed with its `polycall.pc`.

```sh
export PKG_CONFIG_PATH=/opt/polycall/lib/pkgconfig   # if the core is not in a system prefix
make                                                 # -> lib/prolog_polycall.so
swipl -p foreign=lib examples/basic.pl prolog-polycallrc
```

On Linux the foreign library is linked with `-z now` and a RUNPATH to the
core's libdir: a missing core or an old 1.0 core without the ABI v1 symbols
makes `use_foreign_library/1` fail with a clear dynamic-loader error. A core
whose `polycall_ffi_abi_version()` is not 1 is reported when the module loads
and every API predicate then throws
`polycall_error(-15, 'POLYCALL_E_UNSUPPORTED', ...)` — it is never used.

## API (module `prolog_polycall`)

```prolog
:- use_module(library(prolog_polycall)).   % or use_module('src/prolog_polycall')

?- polycall_abi_version(1), polycall_version(V).
?- run_config('prolog-polycallrc', Status).       % polycall_ffi_run_config(Path, 1); Status unchanged
?- run_config('prolog-polycallrc', false, S).     % run=0: unknown keys are warnings
?- run_config_or_throw('prolog-polycallrc').
?- polycall_describe('prolog-polycallrc', JSON).

% one polycall_rpc round trip to `polycall start` / `polycall daemon start`
?- polycall_call('127.0.0.1:8084', inventory, get, '{"item_id":"widget-a"}', 2000, Out).

?- peer_open(alpha, "127.0.0.1:0", '', H),       % '' bind = send-only, '' token = none
   peer_register(H, beta, '127.0.0.1:9002'),
   peer_send(H, beta, utf8("hello"), 'msg-1', 5000),
   peer_recv(H, 5000, message(Sender, MessageId, Payload)),
   peer_list(H, Pairs), peer_health(H, JSON), peer_ping(H, beta, 2000),
   peer_unregister(H, beta), peer_cancel(H), peer_close(H).
```

Payloads are octets: a string/atom/code list of chars 0..255 (binary-safe,
NUL allowed), or `utf8(Text)`. Received payloads are strings of octets.
Timeouts are milliseconds or `infinite`. Failures throw

```prolog
error(polycall_error(Status, Name, Detail), context(Pred/Arity, _))
```

with the `POLYCALL_E_*` status, its `polycall_strerror` name and the
`polycall_last_error` detail of this thread. `polycall_call/6` adds the remote
error object (`polycall_error(Status, Name, Detail, Output)`), and a
`peer_recv/4` with a too-small capacity throws
`polycall_error(-10, 'POLYCALL_E_TOO_LARGE', Detail, needed(Bytes))` and leaves
the message queued. A `peer_recv` blocked in one thread is woken by
`peer_cancel/1` or `peer_close/1` from another.

Changed in 1.1.0: errors were `polycall_error(Status)`; they now carry the
name and detail.

## Tests

`tests/run-real-core.sh` builds the foreign library and runs the PlUnit
suite (`tests/prolog_polycall_tests.pl`) against the **real installed core**:
version/ABI, a missing core, an old core and an ABI 2 core in child `swipl`
processes, `run_config`, `polycall_call` against a live `polycall start`
runtime, two nodes both directions, payload matrix (empty, UTF-8, binary +
NUL, 1 MiB, 1 MiB + 1), registry ownership, de-duplication, auth, dead peers,
timeouts, small buffers, cancel and close waking blocked receivers (threads),
handle lifecycle, 8 concurrent sender threads, and interop with a
`polycall peer serve` C node. A missing swipl, make, pkg-config or core is
reported as SKIP (exit 77), never as success.

```sh
sh tests/run-real-core.sh     # core in /opt/polycall, or POLYCALL_PREFIX / POLYCALL_LIBRARY
```

## License

MIT, Nnamdi Michael Okpala (`okpalan@protonmail.com`), see [LICENSE](LICENSE).
