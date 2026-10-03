# Adapter boundary

`prolog_polycall.pl` is the Prolog API; `prolog_polycall.c` is a SWI-Prolog
foreign library that includes the real `<polycall.h>` and only marshals
terms to C and back:

- text (paths, ids, endpoints, JSON, tokens): UTF-8, refused when it contains
  code 0 (it would reach C truncated);
- payloads: octets (chars 0..255, binary-safe) or `utf8(Text)`;
- handles: `int32`; timeouts: `uint32` milliseconds or `infinite`;
- outputs: caller-owned buffers sized per `polycall.h` (the library never
  returns memory to free).

Each foreign predicate makes one core call and returns its status unchanged;
the Prolog layer turns a non-zero status into
`error(polycall_error(Status, Name, Detail), _)` after reading
`polycall_last_error` on the same thread. `run_config/2` is exactly
`polycall_ffi_run_config(Path, 1)`.

This package contains no configuration parser, wire protocol or peer
transport: those stay in libpolycall.
