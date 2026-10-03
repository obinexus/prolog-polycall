/*
 * prolog-polycall -- SWI-Prolog foreign library over the Polycall binding
 * ABI v1 (polycall.h, libpolycall >= 1.1.0). The Prolog API is in
 * src/prolog_polycall.pl; this file only marshals terms <-> C:
 *
 *   text (paths, ids, endpoints, JSON)  UTF-8 (atom, string or code list)
 *   payloads                            octets: a string/atom/code list of
 *                                       chars 0..255, or utf8(Text)
 *   handles                             int32
 *   timeouts                            0..4294967295 ms, or `infinite`
 *
 * Every predicate returns the raw status in its last argument; the Prolog
 * layer turns non-zero statuses into error(polycall_error(Status, Name,
 * Detail), _) after reading polycall_last_error on the same thread
 * ('$polycall_last_error'/1), so the detail is never another call's.
 *
 * Linked with pkg-config (polycall.pc) and -z now: an old 1.0 core without
 * the ABI v1 symbols fails use_foreign_library/1 with a clear error.
 */

#include <polycall.h>
#include <SWI-Prolog.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define TEXT_FLAGS (CVT_ATOM | CVT_STRING | CVT_LIST | REP_UTF8 | BUF_STACK | CVT_EXCEPTION)

/* NUL-terminated UTF-8 text. A Prolog text may contain code 0, which would
 * reach C silently truncated ('rc\0junk' validated 'rc'): refuse it with
 * domain_error(polycall_text, Text). */
static int get_text(term_t t, char **out)
{
    size_t len = 0;
    if (!PL_get_nchars(t, &len, out, TEXT_FLAGS)) return FALSE;
    if (memchr(*out, '\0', len)) return PL_domain_error("polycall_text", t);
    return TRUE;
}

/* '' -> NULL */
static int get_opt_text(term_t t, const char **out)
{
    char *s = NULL;
    if (!get_text(t, &s)) return FALSE;
    *out = *s ? s : NULL;
    return TRUE;
}

/* An integer in lo..hi. Out of range -- including integers too big for
 * int64 (bignums) -- is domain_error(Domain, T); a non-integer is
 * type_error(integer, T). */
static int get_int_in(term_t t, int64_t lo, int64_t hi, const char *domain, int64_t *v)
{
    if (PL_get_int64(t, v)) return (*v < lo || *v > hi) ? PL_domain_error(domain, t) : TRUE;
    if (PL_is_integer(t)) return PL_domain_error(domain, t);
    return PL_type_error("integer", t);
}

static int get_handle(term_t t, polycall_peer_t *h)
{
    int64_t v;
    if (!get_int_in(t, INT32_MIN, INT32_MAX, "polycall_handle", &v)) return FALSE;
    *h = (polycall_peer_t)v;
    return TRUE;
}

static int get_timeout(term_t t, uint32_t *ms)
{
    int64_t v;
    atom_t a;
    if (PL_get_atom(t, &a) && strcmp(PL_atom_chars(a), "infinite") == 0) {
        *ms = UINT32_MAX;
        return TRUE;
    }
    if (!get_int_in(t, 0, (int64_t)UINT32_MAX, "polycall_timeout_ms", &v)) return FALSE;
    *ms = (uint32_t)v;
    return TRUE;
}

static functor_t FUNCTOR_utf8_1; /* utf8/1, created once in install_prolog_polycall() */

/* payload: utf8(Text) -> UTF-8 bytes; otherwise octets (chars 0..255) */
static int get_payload(term_t t, char **data, size_t *len)
{
    if (PL_is_functor(t, FUNCTOR_utf8_1)) {
        term_t a = PL_new_term_ref();
        _PL_get_arg(1, t, a);
        return PL_get_nchars(a, len, data, CVT_ATOM | CVT_STRING | CVT_LIST | REP_UTF8 |
                                            BUF_STACK | CVT_EXCEPTION);
    }
    return PL_get_nchars(t, len, data, CVT_ATOM | CVT_STRING | CVT_LIST | REP_ISO_LATIN_1 |
                                        BUF_STACK | CVT_EXCEPTION);
}

static int unify_utf8(term_t t, const char *s, size_t len)
{
    return PL_unify_chars(t, PL_STRING | REP_UTF8, len, s);
}

static int unify_status(term_t t, int st)
{
    return PL_unify_integer(t, st);
}

/* ---- library -------------------------------------------------------------- */

static foreign_t pc_abi_version(term_t v)
{
    return PL_unify_integer(v, polycall_ffi_abi_version());
}

static foreign_t pc_version(term_t v, term_t st)
{
    char buf[64];
    int n = polycall_ffi_version(buf, (int)sizeof buf);
    if (n < 0) return unify_status(st, n);
    return unify_utf8(v, buf, strlen(buf)) && unify_status(st, POLYCALL_OK);
}

static foreign_t pc_strerror(term_t code, term_t text)
{
    int c;
    const char *s;
    if (!PL_get_integer_ex(code, &c)) return FALSE;
    s = polycall_strerror(c);
    return unify_utf8(text, s, strlen(s));
}

static foreign_t pc_last_error(term_t text)
{
    char buf[1024];
    polycall_last_error(buf, sizeof buf);
    return unify_utf8(text, buf, strlen(buf));
}

/* ---- configuration / call -------------------------------------------------- */

static foreign_t pc_run_config(term_t path, term_t run, term_t st)
{
    char *p;
    int r;
    if (!get_text(path, &p) || !PL_get_integer_ex(run, &r)) return FALSE;
    return unify_status(st, polycall_ffi_run_config(p, r));
}

static foreign_t pc_describe(term_t path, term_t json, term_t st)
{
    char *p, *buf;
    int cap = 65536, n, attempt;
    if (!get_text(path, &p)) return FALSE;
    for (attempt = 0; attempt < 4; ++attempt) {
        buf = (char *)malloc((size_t)cap);
        if (!buf) return PL_resource_error("memory");
        n = polycall_ffi_describe(p, buf, cap);
        if (n >= 0 && n < cap) {
            int ok = unify_utf8(json, buf, (size_t)n) && unify_status(st, POLYCALL_OK);
            free(buf);
            return ok;
        }
        free(buf);
        if (n < 0) return unify_status(st, n);
        cap = n + 1;
    }
    return unify_status(st, POLYCALL_E_TOO_LARGE);
}

/* '$polycall_call'(+Endpoint, +Service, +Operation, +Input|'', +TimeoutMs, -Output, -Status) */
static foreign_t pc_call(term_t ep, term_t svc, term_t op, term_t in, term_t to, term_t out, term_t st)
{
    char *e, *s, *o;
    const char *i;
    uint32_t ms;
    size_t len = 0;
    char *buf;
    int rc, ok;
    if (!get_text(ep, &e) || !get_text(svc, &s) || !get_text(op, &o) || !get_opt_text(in, &i) ||
        !get_timeout(to, &ms)) {
        return FALSE;
    }
    buf = (char *)malloc(POLYCALL_CALL_MAX_OUTPUT);
    if (!buf) return PL_resource_error("memory");
    rc = polycall_call(e, s, o, i, ms, buf, POLYCALL_CALL_MAX_OUTPUT, &len);
    if (rc == POLYCALL_E_TOO_LARGE) buf[0] = '\0';
    ok = unify_utf8(out, buf, rc == POLYCALL_OK ? len : strlen(buf)) && unify_status(st, rc);
    free(buf);
    return ok;
}

/* ---- peer ------------------------------------------------------------------ */

static foreign_t pc_peer_open(term_t id, term_t bind, term_t token, term_t handle, term_t st)
{
    char *n;
    const char *b, *k;
    polycall_peer_t h = 0;
    int rc;
    if (!get_text(id, &n) || !get_opt_text(bind, &b) || !get_opt_text(token, &k)) return FALSE;
    rc = polycall_peer_open(n, b, k, &h);
    return PL_unify_integer(handle, rc == POLYCALL_OK ? h : 0) && unify_status(st, rc);
}

static foreign_t pc_peer_close(term_t handle, term_t st)
{
    polycall_peer_t h = 0;
    if (!get_handle(handle, &h)) return FALSE;
    return unify_status(st, polycall_peer_close(h));
}

static foreign_t pc_peer_cancel(term_t handle, term_t st)
{
    polycall_peer_t h = 0;
    if (!get_handle(handle, &h)) return FALSE;
    return unify_status(st, polycall_peer_cancel(h));
}

static foreign_t pc_peer_endpoint(term_t handle, term_t text, term_t st)
{
    polycall_peer_t h = 0;
    char buf[POLYCALL_ENDPOINT_MAX];
    int rc;
    if (!get_handle(handle, &h)) return FALSE;
    rc = polycall_peer_endpoint(h, buf, sizeof buf);
    if (rc != POLYCALL_OK) buf[0] = '\0';
    return unify_utf8(text, buf, strlen(buf)) && unify_status(st, rc);
}

static foreign_t pc_peer_node_id(term_t handle, term_t text, term_t st)
{
    polycall_peer_t h = 0;
    char buf[POLYCALL_PEER_ID_MAX];
    int rc;
    if (!get_handle(handle, &h)) return FALSE;
    rc = polycall_peer_node_id(h, buf, sizeof buf);
    if (rc != POLYCALL_OK) buf[0] = '\0';
    return unify_utf8(text, buf, strlen(buf)) && unify_status(st, rc);
}

static foreign_t pc_peer_register(term_t handle, term_t id, term_t ep, term_t st)
{
    polycall_peer_t h = 0;
    char *i, *e;
    if (!get_handle(handle, &h) || !get_text(id, &i) || !get_text(ep, &e)) return FALSE;
    return unify_status(st, polycall_peer_register(h, i, e));
}

static foreign_t pc_peer_unregister(term_t handle, term_t id, term_t st)
{
    polycall_peer_t h = 0;
    char *i;
    if (!get_handle(handle, &h) || !get_text(id, &i)) return FALSE;
    return unify_status(st, polycall_peer_unregister(h, i));
}

typedef int (*sized_fn)(polycall_peer_t, char *, size_t, size_t *);
static foreign_t sized_json(sized_fn fn, term_t handle, term_t json, term_t st)
{
    polycall_peer_t h = 0;
    size_t cap = 4096, len = 0;
    int rc = POLYCALL_E_TOO_LARGE, attempt;
    if (!get_handle(handle, &h)) return FALSE;
    for (attempt = 0; attempt < 4; ++attempt) {
        char *buf = (char *)malloc(cap);
        if (!buf) return PL_resource_error("memory");
        rc = fn(h, buf, cap, &len);
        if (rc == POLYCALL_OK) {
            int ok = unify_utf8(json, buf, len) && unify_status(st, rc);
            free(buf);
            return ok;
        }
        free(buf);
        if (rc != POLYCALL_E_TOO_LARGE) break;
        cap = len + 1;
    }
    return unify_utf8(json, "", 0) && unify_status(st, rc);
}

static foreign_t pc_peer_list(term_t handle, term_t json, term_t st)
{
    return sized_json(polycall_peer_list, handle, json, st);
}

static foreign_t pc_peer_health(term_t handle, term_t json, term_t st)
{
    return sized_json(polycall_peer_health, handle, json, st);
}

static foreign_t pc_peer_ping(term_t handle, term_t peer, term_t to, term_t st)
{
    polycall_peer_t h = 0;
    char *p;
    uint32_t ms;
    if (!get_handle(handle, &h) || !get_text(peer, &p) || !get_timeout(to, &ms)) return FALSE;
    return unify_status(st, polycall_peer_ping(h, p, ms));
}

/* '$polycall_peer_send'(+H, +Peer, +Payload, +MessageId|'', +TimeoutMs, -Status) */
static foreign_t pc_peer_send(term_t handle, term_t peer, term_t payload, term_t mid, term_t to, term_t st)
{
    polycall_peer_t h = 0;
    char *p, *data;
    const char *m;
    size_t len = 0;
    uint32_t ms;
    if (!get_handle(handle, &h) || !get_text(peer, &p) || !get_payload(payload, &data, &len) ||
        !get_opt_text(mid, &m) || !get_timeout(to, &ms)) {
        return FALSE;
    }
    return unify_status(st, polycall_peer_send(h, p, data, len, m, ms));
}

/* '$polycall_peer_recv'(+H, +TimeoutMs, +Capacity, -Sender, -MessageId, -Payload, -Needed, -Status)
 * Payload is a string of octets (chars 0..255); on POLYCALL_E_TOO_LARGE,
 * Needed is the message size and the message stays queued. */
static foreign_t pc_peer_recv(term_t handle, term_t to, term_t capacity, term_t sender, term_t mid,
                              term_t payload, term_t needed, term_t st)
{
    polycall_peer_t h = 0;
    uint32_t ms;
    int64_t cap64;
    size_t cap, len = 0;
    char s[POLYCALL_PEER_ID_MAX], m[POLYCALL_MESSAGE_ID_MAX];
    char *buf;
    int rc, ok;
    if (!get_handle(handle, &h) || !get_timeout(to, &ms) ||
        !get_int_in(capacity, 0, INT64_MAX, "polycall_capacity", &cap64)) {
        return FALSE;
    }
    /* no message exceeds POLYCALL_PEER_MAX_PAYLOAD: clamp, never allocate more */
    cap = cap64 > (int64_t)POLYCALL_PEER_MAX_PAYLOAD ? (size_t)POLYCALL_PEER_MAX_PAYLOAD : (size_t)cap64;
    buf = (char *)malloc(cap ? cap : 1);
    if (!buf) return PL_resource_error("memory");
    s[0] = m[0] = '\0';
    /* blocks in the core; other Prolog threads keep running */
    rc = polycall_peer_recv(h, ms, s, sizeof s, m, sizeof m, buf, cap, &len);
    if (rc != POLYCALL_OK) {
        free(buf);
        return PL_unify_int64(needed, rc == POLYCALL_E_TOO_LARGE ? (int64_t)len : 0) &&
               unify_status(st, rc);
    }
    ok = unify_utf8(sender, s, strlen(s)) && unify_utf8(mid, m, strlen(m)) &&
         PL_unify_chars(payload, PL_STRING | REP_ISO_LATIN_1, len, buf) &&
         PL_unify_int64(needed, (int64_t)len) && unify_status(st, rc);
    free(buf);
    return ok;
}

install_t install_prolog_polycall(void)
{
    FUNCTOR_utf8_1 = PL_new_functor(PL_new_atom("utf8"), 1);
#define REG(name, arity, fn) \
    PL_register_foreign_in_module("prolog_polycall", name, arity, (pl_function_t)(fn), 0)
    REG("$polycall_abi_version", 1, pc_abi_version);
    REG("$polycall_version", 2, pc_version);
    REG("polycall_strerror", 2, pc_strerror);
    REG("$polycall_last_error", 1, pc_last_error);
    REG("$polycall_run_config", 3, pc_run_config);
    REG("$polycall_describe", 3, pc_describe);
    REG("$polycall_call", 7, pc_call);
    REG("$polycall_peer_open", 5, pc_peer_open);
    REG("$polycall_peer_close", 2, pc_peer_close);
    REG("$polycall_peer_cancel", 2, pc_peer_cancel);
    REG("$polycall_peer_endpoint", 3, pc_peer_endpoint);
    REG("$polycall_peer_node_id", 3, pc_peer_node_id);
    REG("$polycall_peer_register", 4, pc_peer_register);
    REG("$polycall_peer_unregister", 3, pc_peer_unregister);
    REG("$polycall_peer_list", 3, pc_peer_list);
    REG("$polycall_peer_health", 3, pc_peer_health);
    REG("$polycall_peer_ping", 4, pc_peer_ping);
    REG("$polycall_peer_send", 6, pc_peer_send);
    REG("$polycall_peer_recv", 8, pc_peer_recv);
#undef REG
}
