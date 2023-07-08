using SQLite, DBInterface, DotEnv

function connectfromenv_sqlite()
    config=DotEnv.config().dict
    delete!(config, "DBMS")
    if haskey(config, "db_path")
        SQLite.DB(config["db_path"])
    else
        SQLite.DB()
    end
end

"""
DBInterface.prepare(conn::LibPQ.Connection, args...; kws...) =
    LibPQ.prepare(conn, args...; kws...)

DBInterface.execute(conn::Union{LibPQ.Connection, LibPQ.Statement}, args...; kws...) =
    LibPQ.execute(conn, args...; kws...)
"""