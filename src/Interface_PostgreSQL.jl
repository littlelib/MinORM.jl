using LibPQ, DBInterface, DotEnv,Pipe

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

"""
DBInterface.connect(::Type{LibPQ.Connection}, args...; kws...) =
    LibPQ.Connection(args...; kws...)

DBInterface.prepare(conn::LibPQ.Connection, args...; kws...) =
    LibPQ.prepare(conn, args...; kws...)

DBInterface.execute(conn::Union{LibPQ.Connection, LibPQ.Statement}, args...; kws...) =
    LibPQ.execute(conn, args...; kws...)
    """