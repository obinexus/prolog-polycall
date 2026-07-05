:- module(prolog_polycall, [
    run_config/1,
    run_config/2,
    run_config_or_throw/0,
    run_config_or_throw/1
]).

:- use_foreign_library(foreign(prolog_polycall)).

default_config('prolog-polycallrc').

%! run_config(-Status:integer) is det.
%
%  Run libpolycall with the default configuration and return its status.
run_config(Status) :-
    default_config(ConfigPath),
    run_config(ConfigPath, Status).

%! run_config(+ConfigPath:text, -Status:integer) is det.
%
%  Run libpolycall and return the core status unchanged.
run_config(ConfigPath, Status) :-
    run_config_native(ConfigPath, Status).

%! run_config_or_throw is det.
%
%  Run the default configuration or throw polycall_error(Status).
run_config_or_throw :-
    default_config(ConfigPath),
    run_config_or_throw(ConfigPath).

%! run_config_or_throw(+ConfigPath:text) is det.
%
%  Throw a structured Prolog error when libpolycall returns nonzero.
run_config_or_throw(ConfigPath) :-
    run_config(ConfigPath, Status),
    (   Status =:= 0
    ->  true
    ;   throw(error(
            polycall_error(Status),
            context(prolog_polycall:run_config_or_throw/1, ConfigPath)
        ))
    ).
