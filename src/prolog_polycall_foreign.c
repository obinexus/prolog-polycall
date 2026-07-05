#include "prolog_polycall.h"

#include <SWI-Prolog.h>

static foreign_t run_config_native(term_t config_term, term_t status_term) {
    char *config_path = NULL;
    int32_t status;
    int unified;

    if (!PL_get_chars(
            config_term,
            &config_path,
            CVT_ATOM | CVT_STRING | REP_UTF8 | BUF_MALLOC | CVT_EXCEPTION
        )) {
        return FALSE;
    }

    status = prolog_polycall_run_config(config_path);
    PL_free(config_path);
    unified = PL_unify_integer(status_term, (int)status);
    return unified ? TRUE : FALSE;
}

install_t install(void) {
    (void)PL_register_foreign_in_module(
        "prolog_polycall",
        "run_config_native",
        2,
        run_config_native,
        0
    );
}
