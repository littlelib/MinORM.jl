using MySQL, DBInterface, DotEnv, Pipe


""".env file must include HOST, USER, PASSWD. Others are optional."""
function connectfromenv_mysql()
    cfg=DotEnv.config().dict
    delete!(cfg, "DBMS")
    args=[pop!(cfg, "host"), pop!(cfg, "user"), pop!(cfg, "passwd")]
    cfg=merge(Dict{Any, Any}(), cfg)
    if haskey(cfg, "port")
        cfg["port"]=parse(Int, cfg["port"])
    end
    cfg=@pipe cfg|>collect|>map(x->Symbol(x.first)=>x.second, _)
    MySQL.DBInterface.connect(MySQL.Connection, args...;cfg...)
end

