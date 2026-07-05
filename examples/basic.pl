:- use_module('../src/prolog_polycall').

:- initialization(main, main).

main(Argv) :-
    (   Argv = [ConfigPath|_]
    ->  true
    ;   ConfigPath = 'prolog-polycallrc'
    ),
    catch(
        (   prolog_polycall:run_config_or_throw(ConfigPath),
            writeln('libpolycall completed successfully')
        ),
        error(polycall_error(Status), _),
        (   format(user_error, 'libpolycall failed with status ~d~n', [Status]),
            halt(Status)
        )
    ).
