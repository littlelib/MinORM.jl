include("./Interface_SQLite.jl")
include("./Interface_MySQL.jl")
include("./Interface_PostgreSQL.jl")
include("./Types.jl")

mutable struct DBManager{DBMS}
    connection
end

DBManager{:sqlite}()=DBManager{:sqlite}(connectfromenv_sqlite())
DBManager{:mysql}()=DBManager{:mysql}(connectfromenv_mysql())
DBManager{:postgresql}()=DBManager{:postgresql}(connectfromenv_postgresql())

prepare(manager::DBManager{:sqlite})