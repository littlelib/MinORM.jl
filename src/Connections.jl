function connectfromenv_sqlite()
    config=DotEnv.config().dict
    delete!(config, "DBMS")
    if haskey(config, "db_path")
        SQLite.DB(config["db_path"])
    else
        SQLite.DB()
    end
end

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

function connectfromenv_postgresql()
    cfg=DotEnv.config().dict
    delete!(cfg, "DBMS")
    delete!(cfg, "db_path")
    if haskey(cfg, "db")
        cfg["dbname"]=pop!(cfg, "db")
    end
    if haskey(cfg, "passwd")
        cfg["password"]=pop!(cfg, "passwd")
    end
    connection_options_string=@pipe cfg|>
    collect|>
    map(x->join([x.first, x.second], "="), _)|>
    join(_, " ")
    LibPQ.Connection(connection_options_string)
end
