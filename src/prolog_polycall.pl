:- module(prolog_polycall, [
    run_config/1,               % -Status                 (default config, strict)
    run_config/2,               % +Path, -Status          polycall_ffi_run_config(Path, 1)
    run_config/3,               % +Path, +Strict, -Status
    run_config_or_throw/0,
    run_config_or_throw/1,      % +Path
    run_config_or_throw/2,      % +Path, +Strict
    polycall_abi_version/1,     % -Version (== 1)
    polycall_version/1,         % -VersionString
    polycall_strerror/2,        % +Status, -Text
    polycall_last_error/1,      % -Detail (this thread)
    polycall_describe/2,        % +Path, -JSON
    polycall_call/6,            % +Endpoint, +Service, +Operation, +InputJSON, +TimeoutMs, -OutputJSON
    peer_open/4,                % +NodeId, +Bind, +Token, -Handle
    peer_close/1,
    peer_endpoint/2,
    peer_node_id/2,
    peer_register/3,            % +Handle, +PeerId, +Endpoint
    peer_unregister/2,
    peer_list/2,                % +Handle, -Pairs (PeerId-Endpoint)
    peer_list_json/2,
    peer_ping/3,                % +Handle, +Peer, +TimeoutMs
    peer_send/5,                % +Handle, +Peer, +Payload, +MessageId, +TimeoutMs
    peer_recv/3,                % +Handle, +TimeoutMs, -message(Sender, MessageId, Payload)
    peer_recv/4,                % +Handle, +TimeoutMs, +Capacity, -Message
    peer_cancel/1,
    peer_health/2               % +Handle, -JSON
]).

/** <module> SWI-Prolog binding for the Polycall binding ABI v1

Reaches libpolycall >= 1.1.0 (polycall.h, binding ABI v1) through the
foreign library prolog_polycall (src/prolog_polycall.c). Configuration
parsing, the wire protocols and the peer transport stay in the core.

Errors are thrown as

    error(polycall_error(Status, Name, Detail), context(Pred/Arity, _))

where Status is the negative POLYCALL_E_* code, Name its symbolic name
from polycall_strerror() (e.g. 'POLYCALL_E_TIMEOUT') and Detail the
polycall_last_error() text of the failing call on this thread. A failed
polycall_call/6 adds the remote error object: polycall_error(Status, Name,
Detail, Output). A peer_recv whose Capacity is too small throws
polycall_error(-10, 'POLYCALL_E_TOO_LARGE', Detail, needed(Bytes)) and the
message stays queued.

Payloads are octets: a string/atom/code list of chars 0..255, or
utf8(Text) to send Text UTF-8 encoded. Received payloads are strings of
octets. Timeouts are milliseconds or `infinite`. Bind '' opens a
send-only node; Token '' means no authentication.
*/

:- use_foreign_library(foreign(prolog_polycall)).
:- if(exists_source(library(json))).          % SWI-Prolog >= 9.3 / 10
:- use_module(library(json), [atom_json_dict/3]).
:- else.
:- use_module(library(http/json), [atom_json_dict/3]).
:- endif.

%   Refuse a core that is not binding ABI v1. SWI-Prolog only prints an
%   exception raised while a module loads, so the error is also recorded
%   and every API predicate re-throws it (abi_ok/0): a mismatched core can
%   never be used silently.
:- dynamic abi_error/1.
check_abi :-
    retractall(abi_error(_)),
    '$polycall_abi_version'(V),
    (   V == 1
    ->  true
    ;   format(string(Msg), "libpolycall reports binding ABI ~w; prolog-polycall requires ABI 1", [V]),
        Error = error(polycall_error(-15, 'POLYCALL_E_UNSUPPORTED', Msg), context(prolog_polycall/0, _)),
        assertz(abi_error(Error)),
        print_message(error, Error)
    ).
:- initialization(check_abi, now).

abi_ok :-
    (   abi_error(Error)
    ->  throw(Error)
    ;   true
    ).

default_config('prolog-polycallrc').

%!  check(+Status, +PI) is det.
%   Throw polycall_error/3 for a non-zero status.
check(0, _) :- !.
check(Status, PI) :-
    polycall_error_term(Status, Formal),
    throw(error(Formal, context(PI, _))).

polycall_error_term(Status, polycall_error(Status, Name, Detail)) :-
    '$polycall_last_error'(Detail),
    status_name(Status, Name).

status_name(Status, Name) :-
    polycall_strerror(Status, Text),
    (   sub_string(Text, Before, _, _, ":")
    ->  sub_atom(Text, 0, Before, _, Name)
    ;   atom_string(Name, Text)
    ).

%!  polycall_abi_version(-V) is det.
polycall_abi_version(V) :- '$polycall_abi_version'(V).

%!  polycall_version(-Version:string) is det.
polycall_version(V) :-
    abi_ok,
    '$polycall_version'(V, St),
    check(St, polycall_version/1).

%!  polycall_last_error(-Detail:string) is det.
polycall_last_error(D) :- '$polycall_last_error'(D).

%!  run_config(-Status) is det.
%!  run_config(+Path, -Status) is det.
%!  run_config(+Path, +Strict, -Status) is det.
%   Validate a configuration file with the core grammar; Status is the core
%   status unchanged (0 = POLYCALL_OK). run_config/2 is
%   polycall_ffi_run_config(Path, 1); Strict = false is run=0.
run_config(Status) :-
    default_config(Path),
    run_config(Path, Status).
run_config(Path, Status) :-
    run_config(Path, true, Status).
run_config(Path, Strict, Status) :-
    abi_ok,
    must_be(boolean, Strict),
    ( Strict == true -> Run = 1 ; Run = 0 ),
    '$polycall_run_config'(Path, Run, Status).

%!  run_config_or_throw is det.
%!  run_config_or_throw(+Path) is det.
%!  run_config_or_throw(+Path, +Strict) is det.
run_config_or_throw :-
    default_config(Path),
    run_config_or_throw(Path).
run_config_or_throw(Path) :-
    run_config_or_throw(Path, true).
run_config_or_throw(Path, Strict) :-
    run_config(Path, Strict, Status),
    check(Status, run_config_or_throw/2).

%!  polycall_describe(+Path, -JSON:string) is det.
polycall_describe(Path, JSON) :-
    abi_ok,
    '$polycall_describe'(Path, JSON, St),
    check(St, polycall_describe/2).

%!  polycall_call(+Endpoint, +Service, +Operation, +Input, +TimeoutMs, -Output:string) is det.
%   One polycall_rpc v1 round trip, never retried. Input is JSON text or ''
%   (sent as null).
polycall_call(Endpoint, Service, Operation, Input, TimeoutMs, Output) :-
    abi_ok,
    '$polycall_call'(Endpoint, Service, Operation, Input, TimeoutMs, Out, St),
    (   St == 0
    ->  Output = Out
    ;   polycall_error_term(St, polycall_error(St, Name, Detail)),
        throw(error(polycall_error(St, Name, Detail, Out), context(polycall_call/6, _)))
    ).

%!  peer_open(+NodeId, +Bind, +Token, -Handle) is det.
peer_open(NodeId, Bind, Token, Handle) :-
    abi_ok,
    '$polycall_peer_open'(NodeId, Bind, Token, H, St),
    check(St, peer_open/4),
    Handle = H.

peer_close(H) :-
    abi_ok,
    '$polycall_peer_close'(H, St),
    check(St, peer_close/1).

peer_cancel(H) :-
    abi_ok,
    '$polycall_peer_cancel'(H, St),
    check(St, peer_cancel/1).

peer_endpoint(H, Endpoint) :-
    abi_ok,
    '$polycall_peer_endpoint'(H, E, St),
    check(St, peer_endpoint/2),
    Endpoint = E.

peer_node_id(H, NodeId) :-
    abi_ok,
    '$polycall_peer_node_id'(H, N, St),
    check(St, peer_node_id/2),
    NodeId = N.

peer_register(H, PeerId, Endpoint) :-
    abi_ok,
    '$polycall_peer_register'(H, PeerId, Endpoint, St),
    check(St, peer_register/3).

peer_unregister(H, PeerId) :-
    abi_ok,
    '$polycall_peer_unregister'(H, PeerId, St),
    check(St, peer_unregister/2).

%!  peer_list_json(+H, -JSON:string) is det.
peer_list_json(H, JSON) :-
    abi_ok,
    '$polycall_peer_list'(H, J, St),
    check(St, peer_list_json/2),
    JSON = J.

%!  peer_list(+H, -Pairs) is det.
%   This node's registry as sorted PeerId-Endpoint pairs (atoms-strings).
peer_list(H, Pairs) :-
    peer_list_json(H, JSON),
    atom_json_dict(JSON, Dict, [value_string_as(string)]),
    dict_pairs(Dict, _, Pairs).

peer_health(H, JSON) :-
    abi_ok,
    '$polycall_peer_health'(H, J, St),
    check(St, peer_health/2),
    JSON = J.

peer_ping(H, Peer, TimeoutMs) :-
    abi_ok,
    '$polycall_peer_ping'(H, Peer, TimeoutMs, St),
    check(St, peer_ping/3).

%!  peer_send(+H, +Peer, +Payload, +MessageId, +TimeoutMs) is det.
%   Exactly one delivery attempt; retry with the SAME MessageId ('' lets
%   the core generate one) -- the receiver drops duplicates.
peer_send(H, Peer, Payload, MessageId, TimeoutMs) :-
    abi_ok,
    '$polycall_peer_send'(H, Peer, Payload, MessageId, TimeoutMs, St),
    check(St, peer_send/5).

%!  peer_recv(+H, +TimeoutMs, -Message) is det.
%!  peer_recv(+H, +TimeoutMs, +Capacity, -Message) is det.
%   Message = message(Sender, MessageId, Payload). TimeoutMs 0 polls,
%   `infinite` waits for a message, peer_cancel/1 or peer_close/1.
peer_recv(H, TimeoutMs, Message) :-
    peer_recv(H, TimeoutMs, 1048576, Message).
peer_recv(H, TimeoutMs, Capacity, Message) :-
    abi_ok,
    '$polycall_peer_recv'(H, TimeoutMs, Capacity, Sender, Id, Payload, Needed, St),
    (   St == 0
    ->  Message = message(Sender, Id, Payload)
    ;   St == -10
    ->  polycall_error_term(St, polycall_error(St, Name, Detail)),
        throw(error(polycall_error(St, Name, Detail, needed(Needed)), context(peer_recv/4, _)))
    ;   check(St, peer_recv/4)
    ).

:- multifile prolog:error_message//1.
prolog:error_message(polycall_error(Status, Name, Detail)) -->
    [ 'Polycall: ~w (status ~w): ~w'-[Name, Status, Detail] ].
prolog:error_message(polycall_error(Status, Name, Detail, Extra)) -->
    [ 'Polycall: ~w (status ~w): ~w [~w]'-[Name, Status, Detail, Extra] ].
