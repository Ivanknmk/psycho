-module(psycho_server).

-behavior(proc).

-export([start/2, start/3,
         start_link/2, start_link/3]).

-export([init/1, handle_msg/3]).

-record(state, {handler_sup, lsock, app}).

-define(DEFAULT_BACKLOG, 128).
-define(DEFAULT_RECBUF, 8192).

%%%===================================================================
%%% Start / init
%%%===================================================================

start(Binding, App) ->
    start(Binding, App, []).

start(Binding, App, Options) ->
    proc:start(?MODULE, [Binding, App, Options]).

start_link(Binding, App) ->
    start_link(Binding, App, []).

start_link(Binding, App, Options) ->
    proc:start_link(?MODULE, [Binding, App, Options]).

init([Binding, App, Options]) ->
    HandlerSup = start_handler_sup(),
    LSock = listen(Binding, Options),
    {ok, init_state(HandlerSup, LSock, App), {first_msg, accept}}.

start_handler_sup() ->
    {ok, Sup} = psycho_handler_sup:start_link(),
    Sup.

listen(Binding, Options) ->
    Port = binding_port(Binding),
    ListenOpts = listen_options(Binding, Options),
    handle_listen(gen_tcp:listen(Port, ListenOpts)).

binding_port(Port) when is_integer(Port) -> Port;
binding_port({_Addr, Port}) when is_integer(Port) -> Port; 
binding_port(Other) -> error({invalid_binding, Other}).

listen_options(_Binding, Opts) ->
    %% TODO - use Binding to specify bound IP addr
    [binary,
     {active, false},
     {reuseaddr, true},
     {backlog, proplists:get_value(backlog, Opts, ?DEFAULT_BACKLOG)},
     {recbuf, proplists:get_value(recbuf, Opts, ?DEFAULT_RECBUF)}].

handle_listen({ok, LSock}) -> LSock;
handle_listen({error, Err}) -> error({listen, Err}).

init_state(HandlerSup, LSock, App) ->
    #state{handler_sup=HandlerSup, lsock=LSock, app=App}.

%%%===================================================================
%%% Message dispatch
%%%===================================================================

handle_msg(accept, noreply, State) ->
    handle_accept(accept(State), State),
    {next_msg, accept, State}.

accept(#state{lsock=LSock}) ->
    gen_tcp:accept(LSock).

handle_accept({ok, Sock}, State) ->
    dispatch_request(Sock, State).

dispatch_request(Sock, #state{handler_sup=Sup, app=App}) ->
    handle_start_handler(psycho_handler_sup:start_handler(Sup, Sock, App)).

handle_start_handler({ok, _Pid}) -> ok;
handle_start_handler(Other) -> psycho_log:error(Other).
