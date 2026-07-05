#include "prolog_polycall.h"
#include "polycall_ffi_mock.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    int32_t status;

    polycall_ffi_mock_reset();
    status = prolog_polycall_run_config("examples/prolog-polycallrc");
    assert(status == 0);
    assert(polycall_ffi_mock_call_count() == 1);
    assert(polycall_ffi_mock_last_validate() == 1);
    assert(strcmp(polycall_ffi_mock_last_config(), "examples/prolog-polycallrc") == 0);

    polycall_ffi_mock_return_status(41);
    status = prolog_polycall_run_config("custom-polycallrc");
    assert(status == 41);
    assert(polycall_ffi_mock_call_count() == 2);
    assert(strcmp(polycall_ffi_mock_last_config(), "custom-polycallrc") == 0);

    status = prolog_polycall_run_config(NULL);
    assert(status == 41);
    assert(polycall_ffi_mock_call_count() == 3);
    assert(strcmp(polycall_ffi_mock_last_config(), "") == 0);

    puts("prolog-polycall native adapter test: PASS");
    return 0;
}
