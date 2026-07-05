# Build output

`npm run build:prolog` writes the platform-specific SWI-Prolog foreign library
to `lib/`. Compiled libraries are excluded from npm because they depend on the
operating system, architecture, SWI-Prolog ABI, and libpolycall build.
