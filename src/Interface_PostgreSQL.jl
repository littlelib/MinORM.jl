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
