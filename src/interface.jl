using DataFrames
using Pipe

include("./Interface_SQLite.jl")
include("./Interface_MySQL.jl")
include("./Interface_PostgreSQL.jl")
include("./Types.jl")
include("./Objects.jl")
include("./Kernel_functions.jl")
include("./SQLbuilder.jl")

mutable struct DBManager{DBMS}
    connection
end

DBManager{:sqlite}()=DBManager{:sqlite}(connectfromenv_sqlite())
DBManager{:mysql}()=DBManager{:mysql}(connectfromenv_mysql())
DBManager{:postgresql}()=DBManager{:postgresql}(connectfromenv_postgresql())

close!(manager::DBManager{:sqlite})=SQLite.DBInterface.close!(manager.connection)
close!(manager::DBManager{:mysql})=MySQL.DBInterface.close!(manager.connection)
close!(manager::DBManager{:postgresql})=close(manager.connection)

reconnect!(manager::DBManager{:sqlite})=(close!(manager);DBManager.connection=connectfromenv_sqlite())
reconnect!(manager::DBManager{:mysql})=(close!(manager);DBManager.connection=connectfromenv_mysql())
reconnect!(manager::DBManager{:postgresql})=(close!(manager);DBManager.connection=connectfromenv_postgresql())

prepare(manager::DBManager{:sqlite}, query_format::String)=SQLite.DBInterface.prepare(manager.connection, query_format)
prepare(manager::DBManager{:mysql}, query_format::String)=MySQL.DBInterface.prepare(manager.connection, query_format)
prepare(manager::DBManager{:postgresql}, query_format::String)=LibPQ.prepare(manager.connection, query_format)

execute(stmt::SQLite.Stmt, params)=SQLite.DBInterface.execute(stmt, params)
execute(manager::DBManager{:sqlite}, query::String)=SQLite.DBInterface.execute(manager.connection, query)

execute(stmt::MySQL.Statement, params)=SQLite.DBInterface.execute(stmt, params)
execute(manager::DBManager{:mysql}, query::String)=SQLite.DBInterface.execute(manager.connection, query)

execute(stmt::LibPQ.Statement, params)=LibPQ.execute(stmt, params)
execute(manager::DBManager{:postgresql}, query::String)=LibPQ.execute(manager.connection, query)

function create(manager::DBManager{:sqlite}, schema::Type{T} where T<:Schema)
    table_data_string=generate_intermediate_tabledata(schema)|>
    generate_final_tabledata_sqlite
    sql="create table if not exists $(typeto_snakecase_name(schema)) ($(table_data_string));"
    execute(manager, sql)|>SQLite.DBInterface.close!
end

function create(manager::DBManager{:mysql}, schema::Type{T} where T<:Schema)
    table_data_string=generate_intermediate_tabledata(schema)|>
    generate_final_tabledata_mysql
    sql="create table if not exists $(typeto_snakecase_name(schema)) ($(table_data_string));"
    execute(manager, sql)|>MySQL.DBInterface.close!
end

function create(manager::DBManager{:postgresql}, schema::Type{T} where T<:Schema)
    table_data_string=generate_intermediate_tabledata(schema)|>
    generate_final_tabledata_postgresql
    sql="create table if not exists $(typeto_snakecase_name(schema)) ($(table_data_string));"
    execute(manager, sql)|>LibPQ.close
end


function drop(manager::DBManager{:sqlite}, schema::Type{T} where T<:Schema)
    sql="drop table if exists $(typeto_snakecase_name(schema));"
    execute(manager, sql)|>SQLite.DBInterface.close!
end

function drop(manager::DBManager{:mysql}, schema::Type{T} where T<:Schema)
    sql="drop table if exists $(typeto_snakecase_name(schema));"
    execute(manager, sql)|>MySQL.DBInterface.close!
end

function drop(manager::DBManager{:sqlite}, schema::Type{T} where T<:Schema)
    sql="drop table if exists $(typeto_snakecase_name(schema));"
    execute(manager, sql)|>LibPQ.close
end

function insert_intermediary(instance::T where T<:Schema)
    schema_name=typeto_snakecase_name(instance|>typeof)
    fields=fieldnames(instance|>typeof)|>collect
    if autoincrement(instance|>typeof)==true && isa(getfield(instance, primary(instance)), Missing)
        filter!(x->x!=primary(instance), fields)
    end
    col_names=@pipe fields|>join(_, ", ")
    stmt_object=@pipe fields|>
    map(x->Sql("$(  P(  getfield(instance, x)  )  )"), _)|>
    collect|>
    concat(_, ", ")
    return (schema_name, col_names, stmt_object)
end

function insert(manager::DBManager{:sqlite}, instance::T where T<:Schema)
    (schema_name, col_names, stmt_object)=insert_intermediary(instance)
    stmt_string="insert into $(schema_name) ($(col_names)) values ($(stmt_object[1]));"
    stmt=prepare(manager, stmt_string)
    execute(stmt, stmt_object[2])|>SQLite.DBInterface.close!
    SQLite.DBInterface.close!(stmt)
end

function insert(manager::DBManager{:mysql}, instance::T where T<:Schema)
    (schema_name, col_names, stmt_object)=insert_intermediary(instance)
    stmt_string="insert into $(schema_name) ($(col_names)) values ($(stmt_object[1]));"
    stmt=prepare(manager, stmt_string)
    execute(stmt, stmt_object[2])
    MySQL.DBInterface.close!(stmt)
end

function insert(manager::DBManager{:postgresql}, instance::T where T<:Schema)
    (schema_name, col_names, stmt_object)=insert_intermediary(instance)
    stmt_object=stmt_object|>renderto_postgresql
    stmt_string="insert into $(schema_name) ($(col_names)) values ($(stmt_object[1]));"
    stmt=prepare(manager, stmt_string)
    execute(stmt, stmt_object[2])|>LibPQ.close
end
    



function select(manager::DBManager{:sqlite}, schema::Type{T} where T<:Schema, columns::NTuple{N, Symbol} where N; where::StmtObject=Sql("true"))
    schema_name=typeto_snakecase_name(schema)
    columns=@pipe columns|>join(_, ", ")
    stmt_object=where
    stmt_string="select $(columns) from $(schema_name) where $(stmt_object[1]);"
    stmt=prepare(manager, stmt_string)
    result=execute(stmt, stmt_object[2])
    df=result|>DataFrame
    result|>SQLite.DBInterface.close!
    SQLite.DBInterface.close!(stmt)
    return df
end

function select(manager::DBManager{:sqlite}, schema::Type{T} where T<:Schema, column::Symbol=:(*); where::StmtObject=Sql("true"))
    schema_name=typeto_snakecase_name(schema)
    stmt_object=where
    stmt_string="select $(column) from $(schema_name) where $(stmt_object[1]);"
    stmt=prepare(manager, stmt_string)
    result=execute(stmt, stmt_object[2])
    df=result|>DataFrame
    result|>SQLite.DBInterface.close!
    SQLite.DBInterface.close!(stmt)
    return df
end


function select(manager::DBManager{:mysql}, schema::Type{T} where T<:Schema, columns::NTuple{N, Symbol} where N; where::StmtObject=Sql("true"))
    schema_name=typeto_snakecase_name(schema)
    columns=@pipe columns|>join(_, ", ")
    stmt_object=where
    stmt_string="select $(columns) from $(schema_name) where $(stmt_object[1]);"
    stmt=prepare(manager, stmt_string)
    result=execute(stmt, stmt_object[2])
    df=result|>DataFrame
    MySQL.DBInterface.close!(stmt)
    return df
end

function select(manager::DBManager{:mysql}, schema::Type{T} where T<:Schema, column::Symbol=:(*); where::StmtObject=Sql("true"))
    schema_name=typeto_snakecase_name(schema)
    stmt_object=where
    stmt_string="select $(column) from $(schema_name) where $(stmt_object[1]);"
    stmt=prepare(manager, stmt_string)
    result=execute(stmt, stmt_object[2])
    df=result|>DataFrame
    MySQL.DBInterface.close!(stmt)
    return df
end

function select(manager::DBManager{:postgresql}, schema::Type{T} where T<:Schema, columns::NTuple{N, Symbol} where N; where::StmtObject=Sql("true"))
    schema_name=typeto_snakecase_name(schema)
    columns=@pipe columns|>join(_, ", ")
    stmt_object=where|>renderto_postgresql
    stmt_string="select $(columns) from $(schema_name) where $(stmt_object[1]);"
    stmt=prepare(manager, stmt_string)
    result=execute(stmt, stmt_object[2])
    df=result|>DataFrame
    result|>LibPQ.close
    return df
end

function select(manager::DBManager{:postgresql}, schema::Type{T} where T<:Schema, column::Symbol=:(*); where::StmtObject=Sql("true"))
    schema_name=typeto_snakecase_name(schema)
    stmt_object=where|>renderto_postgresql
    stmt_string="select $(column) from $(schema_name) where $(stmt_object[1]);"
    stmt=prepare(manager, stmt_string)
    result=execute(stmt, stmt_object[2])
    df=result|>DataFrame
    result|>LibPQ.close
    return df
end
