-module(europepmc_filter_app).
-export([handle/2, base_capabilities/0]).
-define(URL, "https://www.ebi.ac.uk/europepmc/webservices/rest/search?format=json&pageSize=15&resultType=core&query=").

base_capabilities() ->
    em_filter:base_capabilities() ++
    [<<"medical">>, <<"medicine">>, <<"biomed">>, <<"biomedical">>, <<"health">>,
     <<"disease">>, <<"clinical">>, <<"paper">>, <<"research">>, <<"pdf">>,
     <<"cancer">>, <<"biology">>, <<"article">>, <<"study">>, <<"pubmed">>, <<"open">>].

handle(Body, Memory) when is_binary(Body) -> {gen(extract_value(Body)), Memory};
handle(_Body, Memory) -> {[], Memory}.

gen("") -> [];
gen(Q) ->
    Full = Q ++ " AND OPEN_ACCESS:Y",
    Url = ?URL ++ uri_string:quote(Full),
    case fetch_json(Url) of
        {ok, #{<<"resultList">> := #{<<"result">> := Rs}}} when is_list(Rs) ->
            lists:filtermap(fun emb/1, Rs);
        _ -> []
    end.

emb(#{<<"pmcid">> := Pmc} = R) when is_binary(Pmc), byte_size(Pmc) > 0 ->
    Title   = safe(maps:get(<<"title">>, R, <<"Article">>)),
    Authors = safe(maps:get(<<"authorString">>, R, <<>>)),
    Journal = safe(maps:get(<<"journalTitle">>, R, <<>>)),
    Url = txt(["https://europepmc.org/articles/", Pmc, "?pdf=render"]),
    Resume = txt([Authors, " - ", Journal]),
    {true, #{<<"properties">> => #{
        <<"url">> => Url, <<"title">> => Title, <<"resume">> => Resume,
        <<"doc_type">> => <<"pdf">>, <<"source">> => <<"Europe PMC">>}}};
emb(_) -> false.

%%==================== helpers ====================
extract_value(Body) ->
    try json:decode(Body) of
        Map when is_map(Map) ->
            binary_to_list(maps:get(<<"value">>, Map, maps:get(<<"query">>, Map, <<"">>)));
        _ -> binary_to_list(Body)
    catch _:_ -> binary_to_list(Body) end.

fetch_json(Url) ->
    _ = application:ensure_all_started(inets),
    Headers = [{"User-Agent", "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"}],
    case httpc:request(get, {Url, Headers},
                       [{timeout, 15000}, {ssl, [{verify, verify_none}]}],
                       [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, B}} ->
            case catch json:decode(B) of M when is_map(M) -> {ok, M}; _ -> error end;
        _ -> error
    end.

txt(IoList) ->
    case unicode:characters_to_binary(IoList) of Bin when is_binary(Bin) -> Bin; _ -> <<>> end.

safe(B) when is_binary(B) -> B;
safe(L) when is_list(L) -> case unicode:characters_to_binary(L) of X when is_binary(X) -> X; _ -> <<>> end;
safe(_) -> <<>>.
