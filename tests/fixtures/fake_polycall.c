/*
 * Loader-failure fixture -- NOT a substitute for the core.
 *
 * Builds deliberately unusable stand-ins for libpolycall so the binding's
 * loader error paths can be tested; every functional test runs against the
 * real installed library.
 *
 *   cc -shared -fPIC -DFAKE_OLD_CORE ...  only the 1.0 symbol
 *                                         polycall_get_version (an old core
 *                                         without binding ABI v1)
 *   cc -shared -fPIC -DFAKE_ABI=2 ...     every ABI v1 symbol, but
 *                                         polycall_ffi_abi_version() == 2
 *
 * Link with -Wl,-soname,libpolycall.so.1 so it can stand in for the real
 * SONAME via LD_LIBRARY_PATH.
 */
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#  define FAKE_API __declspec(dllexport)
#else
#  define FAKE_API __attribute__((visibility("default")))
#endif

FAKE_API const char *polycall_get_version(void) { return "1.0.0"; }

#ifndef FAKE_OLD_CORE
#ifndef FAKE_ABI
#  define FAKE_ABI 2
#endif
#define FAKE_FAIL (-18) /* POLYCALL_E_INTERNAL */
typedef int32_t polycall_peer_t;

FAKE_API int polycall_ffi_abi_version(void) { return FAKE_ABI; }
FAKE_API int polycall_ffi_version(char *b, int l) { if (b && l > 0) b[0] = '\0'; return 0; }
FAKE_API const char *polycall_strerror(int s) { (void)s; return "FAKE: fixture library"; }
FAKE_API int polycall_last_error(char *b, size_t c) { if (b && c) b[0] = '\0'; return 0; }
FAKE_API int polycall_ffi_run_config(const char *p, int r) { (void)p; (void)r; return FAKE_FAIL; }
FAKE_API int polycall_ffi_describe(const char *p, char *b, int l) { (void)p; (void)b; (void)l; return FAKE_FAIL; }
FAKE_API int polycall_call(const char *e, const char *s, const char *o, const char *i, uint32_t t,
                           char *out, size_t cap, size_t *len)
{ (void)e; (void)s; (void)o; (void)i; (void)t; (void)out; (void)cap; (void)len; return FAKE_FAIL; }
FAKE_API int polycall_peer_open(const char *n, const char *b, const char *a, polycall_peer_t *h)
{ (void)n; (void)b; (void)a; (void)h; return FAKE_FAIL; }
FAKE_API int polycall_peer_close(polycall_peer_t h) { (void)h; return FAKE_FAIL; }
FAKE_API int polycall_peer_endpoint(polycall_peer_t h, char *b, size_t c) { (void)h; (void)b; (void)c; return FAKE_FAIL; }
FAKE_API int polycall_peer_node_id(polycall_peer_t h, char *b, size_t c) { (void)h; (void)b; (void)c; return FAKE_FAIL; }
FAKE_API int polycall_peer_register(polycall_peer_t h, const char *p, const char *e) { (void)h; (void)p; (void)e; return FAKE_FAIL; }
FAKE_API int polycall_peer_unregister(polycall_peer_t h, const char *p) { (void)h; (void)p; return FAKE_FAIL; }
FAKE_API int polycall_peer_list(polycall_peer_t h, char *b, size_t c, size_t *l) { (void)h; (void)b; (void)c; (void)l; return FAKE_FAIL; }
FAKE_API int polycall_peer_ping(polycall_peer_t h, const char *p, uint32_t t) { (void)h; (void)p; (void)t; return FAKE_FAIL; }
FAKE_API int polycall_peer_send(polycall_peer_t h, const char *p, const void *d, size_t n, const char *m, uint32_t t)
{ (void)h; (void)p; (void)d; (void)n; (void)m; (void)t; return FAKE_FAIL; }
FAKE_API int polycall_peer_recv(polycall_peer_t h, uint32_t t, char *s, size_t sc, char *m, size_t mc,
                                void *p, size_t pc, size_t *pl)
{ (void)h; (void)t; (void)s; (void)sc; (void)m; (void)mc; (void)p; (void)pc; (void)pl; return FAKE_FAIL; }
FAKE_API int polycall_peer_cancel(polycall_peer_t h) { (void)h; return FAKE_FAIL; }
FAKE_API int polycall_peer_health(polycall_peer_t h, char *b, size_t c, size_t *l) { (void)h; (void)b; (void)c; (void)l; return FAKE_FAIL; }
#endif
