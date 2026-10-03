% swipl -p foreign=lib examples/basic.pl [ConfigPath]     (after `make`)
% Validates a configuration file with the core: polycall_ffi_run_config(Path, 1).
:- use_module('../src/prolog_polycall').

:- initialization(main, main).

main(Argv) :-
    (   Argv = [ConfigPath|_]
    ->  true
    ;   ConfigPath = 'prolog-polycallrc'
    ),
    polycall_version(V),
    format("libpolycall ~w (binding ABI 1)~n", [V]),
    catch(
        (   run_config_or_throw(ConfigPath),
            format("configuration is valid for running: ~w~n", [ConfigPath])
        ),
        error(polycall_error(Status, Name, Detail), _),
        (   format(user_error, "~w (~d): ~w~n", [Name, Status, Detail]),
            halt(1)
        )
    ).
