:- begin_tests(prolog_polycall).

:- use_module('../src/prolog_polycall').

test(explicit_path_returns_status) :-
    prolog_polycall:run_config('explicit-polycallrc', Status),
    assertion(Status =:= 0).

test(default_path_returns_status) :-
    prolog_polycall:run_config(Status),
    assertion(Status =:= 0).

test(nonzero_status_is_preserved) :-
    prolog_polycall:run_config('__status_37__', Status),
    assertion(Status =:= 37).

test(nonzero_status_throws, [
    throws(error(polycall_error(37), _))
]) :-
    prolog_polycall:run_config_or_throw('__status_37__').

:- end_tests(prolog_polycall).
