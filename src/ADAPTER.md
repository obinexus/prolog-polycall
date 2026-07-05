# Adapter boundary

`prolog_polycall.pl` calls one SWI-Prolog foreign predicate. The foreign stub
marshals an atom or string as UTF-8, and `prolog_polycall_run_config()` makes
exactly one call to `polycall_ffi_run_config(config_path, 1)`. The core status
is unified unchanged with the Prolog result.

This package contains no configuration parser or runtime implementation.
