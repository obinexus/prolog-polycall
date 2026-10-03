# Build output

`make` writes the platform-specific SWI-Prolog foreign library to
`lib/prolog_polycall.so` (load it with `swipl -p foreign=lib`). Compiled
libraries are not committed or packed: they depend on the OS, architecture,
SWI-Prolog ABI and libpolycall build.
