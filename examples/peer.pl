% swipl -p foreign=lib examples/peer.pl     (after `make`)
% Two peer nodes in one process exchange a payload in each direction.
:- use_module('../src/prolog_polycall').

:- initialization(main, main).

main(_) :-
    peer_open(alpha, "127.0.0.1:0", '', Alpha),
    peer_open(beta, "127.0.0.1:0", '', Beta),
    peer_endpoint(Beta, BetaEndpoint),
    peer_register(Alpha, beta, BetaEndpoint),            % alpha's registry only
    peer_send(Alpha, beta, utf8("hello beta"), 'greeting-1', 2000),
    peer_recv(Beta, 2000, message(From, Id, Payload)),
    string_length(Payload, N),
    format("beta got ~d bytes from ~w (id ~w)~n", [N, From, Id]),
    peer_endpoint(Alpha, AlphaEndpoint),
    peer_send(Beta, AlphaEndpoint, "hello alpha", 'greeting-2', 2000),
    peer_recv(Alpha, 2000, message(_, _, Back)),
    format("alpha got ~w~n", [Back]),
    peer_close(Alpha),
    peer_close(Beta).
