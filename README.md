# @obinexusltd/prolog-polycall

SWI-Prolog source binding for
[libpolycall](https://github.com/obinexus/libpolycall) 1.5, packaged for public
distribution through npmjs.org.

The binding is a thin adapter. A Prolog predicate calls one SWI-Prolog foreign
predicate, which marshals the configuration path as UTF-8 and forwards it to
`polycall_ffi_run_config(config_path, 1)`. Configuration parsing and runtime
behavior remain in libpolycall.

## Install from npm

```powershell
npm install @obinexusltd/prolog-polycall
```

This is a native source package. It includes Prolog and C sources, generated
and public headers, examples, tests, scripts, Makefile, configuration, and the
binding manifest. It excludes platform- and ABI-specific foreign libraries.

## Prolog API

```prolog
:- use_module('node_modules/@obinexusltd/prolog-polycall/src/prolog_polycall').

run_service :-
    prolog_polycall:run_config('prolog-polycallrc', Status),
    Status =:= 0.
```

For exception-oriented startup logic:

```prolog
run_service :-
    catch(
        prolog_polycall:run_config_or_throw('prolog-polycallrc'),
        error(polycall_error(Status), _),
        format(user_error, 'libpolycall status: ~d~n', [Status])
    ).
```

Exported predicates:

- `run_config(-Status)` uses `prolog-polycallrc`.
- `run_config(+ConfigPath, -Status)` returns the core status unchanged.
- `run_config_or_throw/0` uses the default configuration.
- `run_config_or_throw(+ConfigPath)` throws
  `error(polycall_error(Status), Context)` for nonzero status.

Atoms and strings are accepted as configuration paths and marshalled as UTF-8.

## Build and test

The native adapter can be built and tested without SWI-Prolog:

```powershell
npm run build
npm test
```

This machine currently has GCC and GNU Make but no Prolog implementation.
Therefore the native mock contract test, thin-boundary audit, and npm package
tests run, while the SWI-Prolog foreign-interface smoke test is reported as
skipped. When `swipl` and `swipl-ld` are on `PATH`, it runs automatically.

Run it explicitly after installing SWI-Prolog:

```powershell
npm run test:prolog
```

The native test proves exact path forwarding, validation mode `1`, and status
preservation. The PL-Unit suite then verifies default and explicit paths plus
structured errors through the actual foreign interface.

## Link with libpolycall

Build libpolycall, then provide its linker flags:

```powershell
make foreign POLYCALL_LDFLAGS="-LC:/path/to/libpolycall/lib -lpolycall"
```

This invokes `swipl-ld` and writes the loadable foreign library under `lib/`.
Add that directory to SWI-Prolog's `foreign` search path when running:

```powershell
swipl -p foreign=lib -s examples/basic.pl -- prolog-polycallrc
```

On Windows, the Makefile links directly with GCC instead of `swipl-ld` because
the latter can split an installation path containing `Program Files`. It uses
`C:/PROGRA~1/swipl` by default; override `SWI_HOME` if SWI-Prolog is installed
elsewhere.

## JavaScript build-tool entry point

```js
const binding = require('@obinexusltd/prolog-polycall');

console.log(binding.prologModule);
console.log(binding.directories.src.relativeFiles);
console.log(binding.resolve('examples', 'basic.pl'));
```

All package directory metadata is project-relative. The CommonJS entry point
indexes `src`, `include`, `generated`, `dist`, `examples`, `tests`, and
`scripts`; `resolve()` rejects traversal outside the selected directory.

## Publish publicly

```powershell
npm pack --dry-run
npm publish --access public
```

`publishConfig.access` is already `public`. Publishing is not automatic.

## Author and license

Nnamdi Michael Okpala (`okpalan@protonmail.com`). Licensed under MIT.
