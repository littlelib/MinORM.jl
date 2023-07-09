function connectfromenv_sqlite()
    config=DotEnv.config().dict
    delete!(config, "DBMS")
    if haskey(config, "db_path")
        SQLite.DB(config["db_path"])
    else
        SQLite.DB()
    end
end
