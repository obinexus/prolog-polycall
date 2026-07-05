# TODO — prolog-polycall

Status: implemented SWI-Prolog source adapter for libpolycall 1.5.

- [x] Exact thin shim over `polycall_ffi_run_config(config_path, 1)`
- [x] SWI-Prolog foreign predicate with UTF-8 path marshalling
- [x] Raw-status and structured-error Prolog APIs
- [x] Native mock contract test and PL-Unit foreign-interface test
- [x] npm public-package metadata and relative directory index
- [x] Updated README and MIT license
- [ ] Install SWI-Prolog and execute `npm run test:prolog` locally
- [ ] Run the example against a built libpolycall shared core
- [ ] Publish `@obinexusltd/prolog-polycall` publicly on npm
