/*  PlUnit suite for prolog-polycall against the REAL installed core.

    Run through tests/run-real-core.sh, which builds the foreign library,
    starts a `polycall start` runtime and exports POLYCALL_* variables:

        swipl -p foreign=lib -g run_polycall_tests -t halt tests/prolog_polycall_tests.pl

    Without those variables run_polycall_tests exits 77 (SKIP), never 0.
*/

:- encoding(utf8).
:- use_module('../src/prolog_polycall').
:- use_module(library(plunit)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(base64)).
:- use_module(library(lists)).
:- use_module(library(utf8)).
:- use_module(library(yall)).
:- use_module(library(apply)).
:- if(exists_source(library(json))).
:- use_module(library(json), [atom_json_dict/3]).
:- else.
:- use_module(library(http/json), [atom_json_dict/3]).
:- endif.

realcore :-
    getenv('POLYCALL_TEST_RPC_ENDPOINT', _),
    getenv('POLYCALL_CLI', _).

env(Name, Value) :- getenv(Name, Value).
rpc(EP) :- env('POLYCALL_TEST_RPC_ENDPOINT', EP).
tmp(Name, Path) :- env('POLYCALL_TEST_TMP', D), atomic_list_concat([D, '/', Name], Path).

write_file(Name, Text, Path) :-
    tmp(Name, Path),
    setup_call_cleanup(open(Path, write, S, [encoding(octet)]), write(S, Text), close(S)).

%   status_of(:Goal, -Status): ok, or the polycall status Goal threw.
status_of(Goal, Status) :-
    catch(( call(Goal), Status = ok ),
          error(E, _),
          (   E =.. [polycall_error, S|_] -> Status = S ; Status = other(E) )).

%   error_of(:Goal, -Formal)
error_of(Goal, Formal) :-
    catch(( call(Goal), Formal = none ), error(Formal, _), true).

all_bytes(S) :- numlist(0, 255, Cs), string_codes(S, Cs).

take(H, Sender-Id-Payload) :- take(H, 3000, Sender-Id-Payload).
take(H, T, Sender-Id-Payload) :- peer_recv(H, T, message(Sender, Id, Payload)).

%   run a child swipl with extra environment; Code is its exit status
child_swipl(Env, Args, Code, Output) :-
    current_prolog_flag(executable, Swipl),
    append(Env, [Swipl|Args], EnvArgs),
    process_create(path(env), EnvArgs,
                   [stdout(pipe(Out)), stderr(pipe(Err)), process(Pid)]),
    read_string(Out, _, O), read_string(Err, _, E),
    close(Out), close(Err),
    process_wait(Pid, exit(Code)),
    string_concat(O, E, Output).

wait_thread(Id, Seconds, Status) :-
    get_time(T0), Deadline is T0 + Seconds,
    wait_thread_(Id, Deadline, Status).
wait_thread_(Id, Deadline, Status) :-
    thread_property(Id, status(S)),
    (   S \== running
    ->  thread_join(Id, Status)
    ;   get_time(Now), Now > Deadline
    ->  Status = still_running
    ;   sleep(0.02), wait_thread_(Id, Deadline, Status)
    ).

with_peers(Ids, Goal) :-
    setup_call_cleanup(
        maplist([Id, H]>>peer_open(Id, "127.0.0.1:0", '', H), Ids, Hs),
        call(Goal, Hs),
        forall(member(H, Hs), catch(peer_close(H), _, true))).

% ---- library ------------------------------------------------------------------

:- begin_tests(library, [condition(realcore)]).

test(version_and_abi) :-
    polycall_abi_version(1),
    polycall_version(V),
    split_string(V, ".", "", [Major, Minor, Patch]),
    assertion(Major == "1"),
    number_string(Mi, Minor), assertion(Mi >= 1),
    number_string(_, Patch).

test(strerror_names_every_status) :-
    findall(N, ( between(0, 18, I), S is -I, polycall_strerror(S, T),
                 split_string(T, ":", "", [N|_]) ), Names),
    nth0(0, Names, "POLYCALL_OK"), nth0(4, Names, "POLYCALL_E_TIMEOUT"),
    nth0(18, Names, "POLYCALL_E_INTERNAL"),
    sort(Names, Unique), length(Unique, 19),
    polycall_strerror(-999, U), sub_string(U, 0, _, _, "POLYCALL_E_UNKNOWN").

test(errors_carry_status_name_and_detail) :-
    error_of(peer_endpoint(987654, _), polycall_error(S, Name, Detail)),
    S == -3, Name == 'POLYCALL_E_INVALID_HANDLE',
    assertion(sub_string(Detail, _, _, _, "handle")),
    run_config(0),
    polycall_last_error("").

test(last_error_is_per_thread) :-
    status_of(peer_node_id(424242, _), -3),
    thread_self(Me),
    thread_create(( polycall_last_error(D), thread_send_message(Me, other_thread(D)) ), Id, []),
    thread_get_message(other_thread(Other)), thread_join(Id, true),
    assertion(Other == ""),
    polycall_last_error(Mine),
    assertion(Mine \== "").

%   The child loads the module and calls polycall_version/1; a library that
%   cannot be used must make that fail loudly (non-zero exit + message).
child_load(Env, ForeignDir, Code, Out) :-
    env('PROLOG_POLYCALL_REPO', Repo),
    atomic_list_concat(['foreign=', ForeignDir], P),
    format(atom(G), "use_module('~w/src/prolog_polycall'), prolog_polycall:polycall_version(V), writeln(V)", [Repo]),
    child_swipl(Env, ['-q', '-p', P, '-g', G, '-t', halt], Code, Out).

test(missing_library_is_a_clear_error) :-
    env('PROLOG_POLYCALL_NORPATH_DIR', Dir),
    child_load(['LD_LIBRARY_PATH=/nonexistent'], Dir, Code, Out),
    assertion(Code \== 0),
    assertion(sub_string(Out, _, _, _, "libpolycall.so.1")).

test(old_core_without_abi_v1_symbols_is_rejected) :-
    env('POLYCALL_TEST_FAKE_OLD', Old), file_directory_name(Old, D),
    env('PROLOG_POLYCALL_REPO', Repo), atomic_list_concat([Repo, '/lib'], Lib),
    atomic_list_concat(['LD_LIBRARY_PATH=', D], E),
    child_load([E], Lib, Code, Out),
    assertion(Code \== 0),
    assertion(sub_string(Out, _, _, _, "undefined symbol: polycall_")).

test(abi_mismatch_is_rejected) :-
    env('POLYCALL_TEST_FAKE_ABI2', Abi2), file_directory_name(Abi2, D),
    env('PROLOG_POLYCALL_REPO', Repo), atomic_list_concat([Repo, '/lib'], Lib),
    atomic_list_concat(['LD_LIBRARY_PATH=', D], E),
    child_load([E], Lib, Code, Out),
    assertion(Code \== 0),
    assertion(sub_string(Out, _, _, _, "reports binding ABI 2")),
    assertion(\+ sub_string(Out, _, _, _, "9.9.9")).

:- end_tests(library).

% ---- configuration --------------------------------------------------------------

:- begin_tests(config, [condition(realcore)]).

test(shipped_rc_files_validate_strictly) :-
    env('PROLOG_POLYCALL_REPO', Repo),
    atomic_list_concat([Repo, '/prolog-polycallrc'], Rc),
    atomic_list_concat([Repo, '/examples/prolog-polycallrc'], Ex),
    run_config(Rc, 0), run_config(Ex, true, 0),
    run_config_or_throw(Rc),
    polycall_describe(Rc, JSON),
    assertion(sub_string(JSON, _, _, _, "\"layer\"")).

test(missing_and_empty_paths) :-
    tmp('missing-polycallrc', Missing),
    run_config(Missing, -7), run_config('', -1),
    error_of(run_config_or_throw('/nonexistent/prolog-polycallrc'), polycall_error(-7, 'POLYCALL_E_NOT_FOUND', _)).

test(invalid_value_names_the_key) :-
    write_file('bad-polycallrc', "max_connections=lots\n", P),
    run_config(P, false, -13),
    polycall_last_error(D), assertion(sub_string(D, _, _, _, "max_connections")),
    error_of(run_config_or_throw(P), polycall_error(-13, _, D2)),
    assertion(sub_string(D2, _, _, _, "max_connections")).

test(unknown_key_warning_unless_strict) :-
    write_file('unknown-polycallrc', "log_level=info\nmystery_key=1\n", P),
    run_config(P, false, 0), run_config(P, true, -13), run_config(P, -13).

test(tls_refused_not_faked_when_strict) :-
    write_file('tls-polycallrc', "tls_enabled=true\ncert_file=/x/c.pem\nkey_file=/x/k.pem\n", P),
    run_config(P, false, 0), run_config(P, true, -15),
    polycall_last_error(D), string_lower(D, L), assertion(sub_string(L, _, _, _, "tls")).

:- end_tests(config).

% ---- polycall_call ----------------------------------------------------------------

:- begin_tests(call, [condition(realcore)]).

test(success) :-
    rpc(EP),
    polycall_call(EP, inventory, get, '{"item_id":"widget-a"}', 2000, Out),
    assertion(Out == "{\"item_id\":\"widget-a\",\"quantity\":42,\"in_stock\":true}"),
    polycall_call(EP, debug, echo, '', 2000, Null),
    assertion(Null == "{\"echo\":null}"),
    polycall_call(EP, debug, echo, "{\"s\":\"hé \U0001F30D\"}", 2000, Echo),
    assertion(Echo == "{\"echo\":{\"s\":\"hé \U0001F30D\"}}").

test(unknown_operation) :-
    rpc(EP), status_of(polycall_call(EP, inventory, teleport, '{}', 2000, _), -7).

test(remote_error_carries_the_error_object) :-
    rpc(EP),
    error_of(polycall_call(EP, inventory, get, '{"item_id":"nope"}', 2000, _), polycall_error(-9, _, _, Obj)),
    assertion(sub_string(Obj, _, _, _, "item.unknown")).

test(deadline_exceeded) :-
    rpc(EP), get_time(T0),
    status_of(polycall_call(EP, debug, sleep, '{"ms":2000}', 150, _), -4),
    get_time(T1), assertion(T1 - T0 < 1.9).

test(invalid_input) :-
    rpc(EP),
    status_of(polycall_call(EP, debug, echo, '{not json', 1000, _), -1),
    status_of(polycall_call(EP, debug, echo, '{}', 0, _), -1),
    status_of(polycall_call('no-port', debug, echo, '', 1000, _), -1).

test(no_runtime) :-
    status_of(polycall_call('127.0.0.1:1', inventory, get, '{}', 1000, _), -5).

:- end_tests(call).

% ---- peers ---------------------------------------------------------------------------

:- begin_tests(peer, [condition(realcore)]).

test(identity_endpoint_and_send_only_node) :-
    peer_open(alpha, "127.0.0.1:0", '', A), peer_open('sender-only', '', '', S),
    peer_node_id(A, "alpha"), peer_endpoint(A, EP),
    split_string(EP, ":", "", ["127.0.0.1", Port]), number_string(PN, Port), assertion(PN > 0),
    peer_endpoint(S, ""), assertion(A > 0), assertion(A \== S),
    peer_health(A, J), assertion(sub_string(J, _, _, _, "\"node_id\":\"alpha\"")),
    peer_close(A), peer_close(S).

test(payloads_both_directions) :-
    with_peers([alpha, beta], [[A, B]]>>(
        peer_endpoint(A, EA), peer_endpoint(B, EB),
        peer_register(A, beta, EB), peer_register(B, alpha, EA),
        peer_send(A, beta, "hello beta", 'a2b-1', 3000),
        take(B, R1), assertion(R1 == "alpha"-"a2b-1"-"hello beta"),
        peer_send(B, alpha, "hello alpha", 'b2a-1', 3000),
        take(A, R2), assertion(R2 == "beta"-"b2a-1"-"hello alpha"),
        peer_ping(A, beta, 2000), peer_ping(B, EA, 2000))).

test(payload_matrix) :-
    with_peers([alpha, beta], [[A, B]]>>(
        peer_endpoint(B, EB), peer_register(A, beta, EB),
        peer_send(A, beta, "", 'empty-1', 3000),
        take(B, E), assertion(E == "alpha"-"empty-1"-""),
        U = "héllo — 世界 \U0001F30D",
        peer_send(A, beta, utf8(U), 'utf8-1', 3000),
        take(B, _-"utf8-1"-UB), string_length(UB, 22),
        string_codes(UB, UCs), phrase(utf8_codes(Back), UCs), string_codes(Back2, Back),
        assertion(Back2 == U),
        all_bytes(Bytes), string_concat(Bytes, "\u0000\u0000tail\u0000", Bin),
        peer_send(A, beta, Bin, 'binary-1', 3000),
        take(B, BR), assertion(BR == "alpha"-"binary-1"-Bin),
        numlist(0, 255, Cs), findall(Cs, between(1, 4096, _), Css), append(Css, MaxCodes),
        string_codes(Max, MaxCodes), string_length(Max, 1048576),
        peer_send(A, beta, Max, 'max-1', 10000),
        take(B, 5000, _-"max-1"-MaxR), assertion(MaxR == Max),
        string_concat(Max, "x", Over),
        status_of(peer_send(A, beta, Over, 'over-1', 3000), -10),
        status_of(peer_recv(B, 200, _), -4))).

test(registry_belongs_to_its_node_only) :-
    with_peers([alpha, beta], [[A, B]]>>(
        peer_list(A, []), peer_endpoint(B, EB),
        peer_register(A, beta, EB), peer_list(A, [beta-EB]),
        peer_list(B, []), peer_list_json(B, "{}"),
        peer_send(A, beta, "x", 'own-1', 3000), take(B, "alpha"-_-_),
        peer_list(B, []),
        status_of(peer_send(B, alpha, "x", '', 2000), -7),
        peer_unregister(A, beta), peer_list(A, []),
        status_of(peer_unregister(A, beta), -7),
        status_of(peer_register(A, 'bad id!', EB), -1))).

test(duplicate_message_id_delivered_once) :-
    with_peers([alpha, beta], [[A, B]]>>(
        peer_endpoint(B, EB), peer_register(A, beta, EB),
        peer_send(A, beta, "once", 'dup-1', 3000), peer_send(A, beta, "once", 'dup-1', 3000),
        take(B, R), assertion(R == "alpha"-"dup-1"-"once"),
        status_of(peer_recv(B, 300, _), -4),
        peer_health(B, J), assertion(sub_string(J, _, _, _, "\"duplicates\":1")))).

test(auth_failure_rejected_nothing_queued) :-
    env('POLYCALL_DEV_TOKEN', Tok),
    peer_open(beta, "127.0.0.1:0", Tok, B), peer_open(carol, '', '', C),
    peer_open(mallory, '', 'not-the-token', M), peer_open(alpha, '', Tok, G),
    peer_endpoint(B, EB),
    status_of(peer_send(C, EB, "x", 'auth-1', 2000), -8),
    status_of(peer_send(M, EB, "x", 'auth-2', 2000), -8),
    status_of(peer_recv(B, 200, _), -4),
    peer_send(G, EB, "ok", 'auth-3', 2000),
    take(B, R), assertion(R == "alpha"-"auth-3"-"ok"),
    maplist(peer_close, [B, C, M, G]).

test(dead_peer_is_transport_error) :-
    peer_open(alpha, "127.0.0.1:0", '', A), peer_open(doomed, "127.0.0.1:0", '', D),
    peer_endpoint(D, ED), peer_close(D), peer_register(A, doomed, ED),
    status_of(peer_send(A, doomed, "into the void", 'dead-1', 2000), -5),
    status_of(peer_ping(A, ED, 1000), -5),
    peer_close(A).

test(receive_timeout_and_poll) :-
    peer_open(beta, "127.0.0.1:0", '', B),
    get_time(T0), status_of(peer_recv(B, 150, _), -4), get_time(T1),
    Dt is T1 - T0, assertion(Dt >= 0.1), assertion(Dt < 3.0),
    status_of(peer_recv(B, 0, _), -4),
    peer_close(B).

test(too_small_buffer_leaves_message_queued) :-
    with_peers([alpha, beta], [[A, B]]>>(
        peer_endpoint(B, EB), peer_send(A, EB, "0123456789", 'size-1', 3000),
        error_of(peer_recv(B, 2000, 4, _), polycall_error(-10, _, _, needed(N))),
        assertion(N == 10),
        take(B, R), assertion(R == "alpha"-"size-1"-"0123456789"))).

blocked_recv(H) :- peer_recv(H, infinite, _).

test(cancel_wakes_a_blocked_receive) :-
    peer_open(beta, "127.0.0.1:0", '', B),
    thread_create(blocked_recv(B), Id, []),
    sleep(0.3), thread_property(Id, status(running)),
    peer_cancel(B),
    wait_thread(Id, 5, St),
    assertion(St = exception(error(polycall_error(-12, 'POLYCALL_E_CANCELLED', _), _))),
    status_of(peer_recv(B, 100, _), -4),
    peer_close(B).

test(close_wakes_every_blocked_receive) :-
    peer_open(beta, "127.0.0.1:0", '', B),
    findall(Id, ( between(1, 3, _), thread_create(blocked_recv(B), Id, []) ), Ids),
    sleep(0.3), forall(member(Id, Ids), thread_property(Id, status(running))),
    peer_close(B),
    maplist([Id, S]>>wait_thread(Id, 5, S), Ids, Sts),
    forall(member(S, Sts), assertion(S = exception(error(polycall_error(-17, 'POLYCALL_E_CLOSED', _), _)))).

test(double_close_calls_after_close_invalid_handles) :-
    peer_open(closing, "127.0.0.1:0", '', P), peer_close(P),
    status_of(peer_close(P), -3),
    forall(member(G, [peer_endpoint(P, _), peer_node_id(P, _), peer_send(P, '127.0.0.1:1', "x", '', 1000),
                      peer_recv(P, 0, _), peer_cancel(P), peer_list(P, _), peer_health(P, _),
                      peer_register(P, x, '127.0.0.1:1'), peer_unregister(P, x),
                      peer_ping(P, '127.0.0.1:1', 1000)]),
           status_of(G, -3)),
    forall(member(Bogus, [0, -1, 999999, 2147483647]), status_of(peer_ping(Bogus, '127.0.0.1:1', 1000), -3)),
    peer_open(closing, "127.0.0.1:0", '', N), assertion(N \== P),
    status_of(peer_endpoint(P, _), -3), peer_close(N).

test(invalid_identifiers) :-
    status_of(peer_open('bad id!', "127.0.0.1:0", '', _), -1),
    length(L, 64), maplist(=(0'x), L), atom_codes(Long, L),
    status_of(peer_open(Long, "127.0.0.1:0", '', _), -1),
    status_of(peer_open(public, "0.0.0.0:0", '', _), -13),
    peer_open(alpha, "127.0.0.1:0", '', A), peer_endpoint(A, EA),
    status_of(peer_send(A, EA, "x", 'bad id!', 1000), -1),
    catch(peer_send(A, EA, "世", '', 1000), error(representation_error(_), _), true),
    peer_close(A).

deliver(H, EP, Id, Payload) :-
    catch(peer_send(H, EP, Payload, Id, 5000), error(polycall_error(St, _, _), _), true),
    (   var(St) -> true
    ;   St == -11 -> flag(polycall_busy, N, N + 1), sleep(0.01), deliver(H, EP, Id, Payload)
    ;   throw(error(polycall_error(St, retry, Id), _))
    ).

sender(shared(H), T, EP, Per) :-
    forall(between(1, Per, I1), ( I0 is I1 - 1, format(atom(Id), "shared-~w-~w", [T, I0]),
                                  format(string(P), "s~w:~w", [T, I0]), deliver(H, EP, Id, P) )).
sender(own, T, EP, Per) :-
    format(atom(Node), "own~w", [T]),
    peer_open(Node, '', '', H),
    forall(between(1, Per, I1), ( I0 is I1 - 1, format(atom(Id), "own~w-~w", [T, I0]),
                                  format(string(P), "o~w:~w", [T, I0]), deliver(H, EP, Id, P) )),
    peer_close(H).

test(concurrent_senders_shared_and_separate_handles) :-
    peer_open(beta, "127.0.0.1:0", '', B), peer_endpoint(B, EB),
    peer_open(shared, '', '', Sh),
    Per = 40,
    flag(polycall_busy, _, 0),
    findall(Id, ( between(0, 3, T), thread_create(sender(shared(Sh), T, EB, Per), Id, []) ), Ids1),
    findall(Id, ( between(4, 7, T), thread_create(sender(own, T, EB, Per), Id, []) ), Ids2),
    Total is 8 * Per,
    findall(MId-(S-P), ( between(1, Total, _), take(B, 10000, S-MId-P) ), Got),
    append(Ids1, Ids2, Ids), maplist([I]>>thread_join(I, true), Ids),
    length(Got, Total), sort(1, @<, Got, Unique), length(Unique, Total),
    memberchk("shared-3-39"-("shared"-"s3:39"), Got),
    memberchk("own6-7"-("own6"-"o6:7"), Got),
    status_of(peer_recv(B, 200, _), -4),
    flag(polycall_busy, Busy, Busy),
    ( Busy > 0 -> format(user_error, "  [backpressure] ~w E_BUSY answers retried with the same id~n", [Busy]) ; true ),
    peer_close(B), peer_close(Sh).

:- end_tests(peer).

% ---- interop with the C CLI peer ---------------------------------------------------------

cli(Args, Code, Out) :-
    env('POLYCALL_CLI', Cli),
    process_create(Cli, Args, [stdout(pipe(O)), stderr(null), process(Pid)]),
    read_string(O, _, Out), close(O),
    process_wait(Pid, exit(Code)).

start_cli_node(Id, Pid, EP) :-
    env('POLYCALL_CLI', Cli),
    format(atom(F), "~w.~w.ep", [Id, Id]), tmp(F, File),
    ( exists_file(File) -> delete_file(File) ; true ),
    process_create(Cli, [peer, serve, '--node-id', Id, '--endpoint', '127.0.0.1:0', '--endpoint-file', File],
                   [stdout(null), stderr(null), process(Pid)]),
    wait_endpoint(File, 100, EP).
wait_endpoint(File, N, EP) :-
    (   exists_file(File), size_file(File, Sz), Sz > 0
    ->  read_file_to_string(File, S, []), split_string(S, "", " \r\n", [EP0]), atom_string(EP, EP0)
    ;   N > 0 -> sleep(0.1), N1 is N - 1, wait_endpoint(File, N1, EP)
    ;   throw(error(polycall_cli_node_did_not_start, _))
    ).

:- begin_tests(interop, [condition(realcore)]).

test(prolog_peer_and_cli_peer_exchange_both_ways) :-
    env('POLYCALL_DEV_TOKEN', Tok),
    start_cli_node(cnode, CPid, CEP),
    call_cleanup(
        ( peer_open('prolog-node', "127.0.0.1:0", Tok, H),
          peer_register(H, cnode, CEP), peer_ping(H, cnode, 2000),
          all_bytes(Bytes), string_concat("prolog\u0000toÿC ", Bytes, Payload),
          peer_send(H, cnode, Payload, 'prolog-to-c-1', 3000),
          cli([peer, recv, '--to', CEP, '-t', 3000], 0, Out),
          atom_json_dict(Out, D, [value_string_as(string)]),
          assertion(D.from == "prolog-node"), assertion(D.id == "prolog-to-c-1"),
          base64(Payload, B64), atom_string(B64, B64S), assertion(D.payload_b64 == B64S),
          string_reverse(Bytes, Rev), string_concat("C\u0000to Prolog ", Rev, Back),
          write_file('c-to-prolog.bin', Back, BackFile),
          peer_endpoint(H, PEP),
          cli([peer, send, '--from', cnode, '--to', PEP, '--id', 'c-to-prolog-1', '--payload-file', BackFile], 0, _),
          take(H, R), assertion(R == "cnode"-"c-to-prolog-1"-Back),
          peer_send(H, cnode, "again", 'prolog-dup-1', 3000),
          peer_send(H, cnode, "again", 'prolog-dup-1', 3000),
          cli([peer, recv, '--to', CEP, '-t', 3000], 0, Out2),
          assertion(sub_string(Out2, _, _, _, "\"prolog-dup-1\"")),
          cli([peer, recv, '--to', CEP, '-t', 300], 6, _),
          peer_close(H) ),
        ( process_kill(CPid), process_wait(CPid, _) )).

string_reverse(S, R) :- string_codes(S, Cs), reverse(Cs, Rs), string_codes(R, Rs).

test(cli_registers_on_the_prolog_node) :-
    env('POLYCALL_DEV_TOKEN', Tok),
    peer_open('prolog-node', "127.0.0.1:0", Tok, H), peer_endpoint(H, EP),
    cli([peer, register, '--to', EP, '--id', 'remote-c', '--peer-endpoint', '127.0.0.1:9'], 0, _),
    peer_list(H, L), assertion(L == ['remote-c'-"127.0.0.1:9"]),
    cli([peer, health, '--to', EP], 0, HOut),
    assertion(sub_string(HOut, _, _, _, "\"node_id\":\"prolog-node\"")),
    peer_close(H).

test(call_matches_the_cli_client) :-
    rpc(EP),
    cli([call, inventory, get, '--endpoint', EP, '--input-value', '{"item_id":"widget-b"}'], 0, Out),
    polycall_call(EP, inventory, get, '{"item_id":"widget-b"}', 2000, Mine),
    assertion(sub_string(Out, _, _, _, Mine)),
    assertion(Mine == "{\"item_id\":\"widget-b\",\"quantity\":7,\"in_stock\":true}").

:- end_tests(interop).

% ---- boundaries: integers, NUL in text, Unicode paths ------------------------------------

domain_of(Goal, Domain) :-
    catch(( call(Goal), Domain = none ), error(domain_error(Domain, _), _), true).
type_of(Goal, Type) :-
    catch(( call(Goal), Type = none ), error(type_error(Type, _), _), true).

:- begin_tests(boundaries, [condition(realcore)]).

test(timeouts_outside_uint32_are_domain_errors) :-
    rpc(RPC),
    peer_open(alpha, "127.0.0.1:0", '', A), peer_endpoint(A, EA),
    forall(member(Bad, [-1, 4294967296, 18446744073709551616]),
           ( domain_of(peer_recv(A, Bad, _), D1), assertion(D1 == polycall_timeout_ms),
             domain_of(peer_ping(A, EA, Bad), D2), assertion(D2 == polycall_timeout_ms),
             domain_of(peer_send(A, EA, "x", '', Bad), D3), assertion(D3 == polycall_timeout_ms),
             domain_of(polycall_call(RPC, debug, echo, '', Bad, _), D4), assertion(D4 == polycall_timeout_ms) )),
    type_of(peer_recv(A, 1.5, _), T1), assertion(T1 == integer),
    type_of(peer_recv(A, forever, _), T2), assertion(T2 == integer),
    polycall_call(RPC, debug, echo, '1', 600000, Out), assertion(Out == "{\"echo\":1}"),
    status_of(polycall_call(RPC, debug, echo, '1', 600001, _), -1),
    status_of(peer_recv(A, 0, _), -4),
    peer_ping(A, EA, infinite), peer_ping(A, EA, 4294967295),
    peer_close(A).

test(receive_capacity_bounds) :-
    with_peers([alpha, beta], [[A, B]]>>(
        peer_endpoint(B, EB),
        length(Cs, 4096), maplist(=(0'A), Cs), string_codes(Four, Cs),
        peer_send(A, EB, Four, 'cap-1', 3000),
        domain_of(peer_recv(B, 2000, -1, _), D), assertion(D == polycall_capacity),
        error_of(peer_recv(B, 2000, 0, _), polycall_error(-10, _, _, needed(N0))), assertion(N0 == 4096),
        peer_recv(B, 0, 4096, message(_, _, Got)), assertion(Got == Four),
        length(Ms, 1048576), maplist(=(0xA5), Ms), string_codes(Max, Ms),
        peer_send(A, EB, Max, 'cap-2', 10000),
        peer_recv(B, 5000, 1099511627776, message(_, _, M2)), assertion(M2 == Max),
        peer_send(A, EB, Max, 'cap-3', 10000),
        error_of(peer_recv(B, 5000, 1048575, _), polycall_error(-10, _, _, needed(N1))),
        assertion(N1 == 1048576),
        peer_recv(B, 0, 1048576, message(_, _, M3)), assertion(M3 == Max))).

test(handles_outside_int32_are_domain_errors) :-
    forall(member(Bad, [2147483648, -2147483649, 9223372036854775808]),
           ( domain_of(peer_endpoint(Bad, _), D), assertion(D == polycall_handle) )),
    status_of(peer_endpoint(-2147483648, _), -3).

test(text_with_nul_is_refused_not_truncated) :-
    rpc(RPC),
    env('PROLOG_POLYCALL_REPO', Repo), atomic_list_concat([Repo, '/prolog-polycallrc'], Rc),
    atom_concat(Rc, '\u0000.ignored', RcNul),
    domain_of(run_config(RcNul, _), D1), assertion(D1 == polycall_text),
    domain_of(polycall_describe(RcNul, _), D2), assertion(D2 == polycall_text),
    domain_of(peer_open('al\u0000pha', "127.0.0.1:0", '', _), D3), assertion(D3 == polycall_text),
    domain_of(polycall_call(RPC, debug, echo, '1\u0000', 1000, _), D4), assertion(D4 == polycall_text),
    peer_open(alpha, "127.0.0.1:0", '', A), peer_endpoint(A, EA),
    domain_of(peer_register(A, 'beta\u0000x', EA), D5), assertion(D5 == polycall_text),
    atom_concat(EA, '\u0000junk', EANul),
    domain_of(peer_send(A, EANul, "x", '', 1000), D6), assertion(D6 == polycall_text),
    domain_of(peer_send(A, EA, "x", 'id\u0000x', 1000), D7), assertion(D7 == polycall_text),
    peer_list(A, []),
    peer_send(A, EA, "pay\u0000load\u0000", 'nul-payload', 2000),
    take(A, R), assertion(R == "alpha"-"nul-payload"-"pay\u0000load\u0000"),
    peer_close(A).

test(non_ascii_config_path) :-
    tmp('配置 é ü – Ω', Dir), make_directory_path(Dir),
    atomic_list_concat([Dir, '/prolog-polycallrc-ñ'], P),
    setup_call_cleanup(open(P, write, S, [encoding(utf8)]),
                       format(S, "log_level=info~nmax_connections=8~ntls_enabled=false~n", []),
                       close(S)),
    run_config(P, 0), run_config(P, false, 0),
    polycall_describe(P, J), assertion(sub_string(J, _, _, _, "max_connections")),
    atomic_list_concat([Dir, '/bad-ü'], Bad),
    setup_call_cleanup(open(Bad, write, S2, [encoding(utf8)]), format(S2, "max_connections=many~n", []), close(S2)),
    error_of(run_config_or_throw(Bad), polycall_error(-13, 'POLYCALL_E_CONFIG', Detail)),
    assertion(sub_string(Detail, _, _, _, "max_connections")),
    atomic_list_concat([Dir, '/missing-ñ'], Missing),
    run_config(Missing, -7).

:- end_tests(boundaries).

%   Entry point for the runner. Without the environment of
%   tests/run-real-core.sh nothing can run: exit 77 (SKIP), never success.
%   Otherwise exit 1 unless every test ran and passed.
run_polycall_tests :-
    (   realcore
    ->  true
    ;   format(user_error, "SKIP: run through tests/run-real-core.sh (no real-core environment)~n", []),
        halt(77)
    ),
    (   predicate_property(plunit:run_tests(_, _), defined)
    ->  % SWI-Prolog >= 9.1: check the summary counts
        (   catch(plunit:run_tests(all, [summary(S)]), E, (print_message(error, E), fail))
        ->  true
        ;   halt(1)
        ),
        format("plunit summary: ~p~n", [S]),
        (   S.total > 0, S.failed =:= 0, S.blocked =:= 0, S.timeout =:= 0, S.passed =:= S.total
        ->  true
        ;   format(user_error, "FAIL: not every test ran and passed~n", []),
            halt(1)
        )
    ;   % SWI-Prolog 9.0: run_tests/0 fails on any failed test; realcore
        % holds (checked above), so no unit is skipped by its condition
        (   run_tests
        ->  true
        ;   halt(1)
        )
    ).
