include("./Connections.jl")
include("./Objects.jl")
include("./Kernel_functions.jl")
include("./SQLbuilder.jl")

mutable struct DBManager{DBMS}
    connection
end

DBManager{:sqlite}()=DBManager{:sqlite}(connectfromenv_sqlite())
DBManager{:mysql}()=DBManager{:mysql}(connectfromenv_mysql())
DBManager{:postgresql}()=DBManager{:postgresql}(connectfromenv_postgresql())

setup()=begin
    cfg=DotEnv.config()
    if cfg["DBMS"]=="sqlite"
        return DBManager{:sqlite}()
    elseif cfg["DBMS"]=="mysql" || cfg["DBMS"]=="mariadb"
        return DBManager{:mysql}()
    elseif cfg["DBMS"]=="postgresql"
        return DBManager{:postgresql}()
    end
end

close!(manager::DBManager{:sqlite})=SQLite.DBInterface.close!(manager.connection)
close!(manager::DBManager{:mysql})=MySQL.DBInterface.close!(manager.connection)
close!(manager::DBManager{:postgresql})=close(manager.connection)

reconnect!(manager::DBManager{:sqlite})=(close!(manager);manager.connection=connectfromenv_sqlite())
reconnect!(manager::DBManager{:mysql})=(close!(manager);manager.connection=connectfromenv_mysql())
reconnect!(manager::DBManager{:postgresql})=(close!(manager);manager.connection=connectfromenv_postgresql())

prepare(manager::DBManager{:sqlite}, query_format::String)=SQLite.DBInterface.prepare(manager.connection, query_format)
prepare(manager::DBManager{:mysql}, query_format::String)=MySQL.DBInterface.prepare(manager.connection, query_format)
prepare(manager::DBManager{:postgresql}, query_format::String)=LibPQ.prepare(manager.connection, query_format)

execute_core(stmt::SQLite.Stmt, params)=SQLite.DBInterface.execute(stmt, params)
execute_core(manager::DBManager{:sqlite}, query::String)=SQLite.DBInterface.execute(manager.connection, query)

execute_core(stmt::MySQL.Statement, params)=SQLite.DBInterface.execute(stmt, params)
execute_core(manager::DBManager{:mysql}, query::String)=SQLite.DBInterface.execute(manager.connection, query)

execute_core(stmt::LibPQ.Statement, params)=LibPQ.execute(stmt, params)
execute_core(manager::DBManager{:postgresql}, query::String)=LibPQ.execute(manager.connection, query)

function execute(manager::DBManager, stmt::StatementObject)
    if isa(manager, DBManager{:sqlite})
        final_statement=stmt|>render_sqlite
        prepared_statement=prepare(manager, final_statement.statement)
        result=execute_core(prepared_statement, final_statement.parameters)
        (prepared_statement, result).|>SQLite.DBInterface.close!
    elseif isa(manager, DBManager{:mysql})
        final_statement=stmt|>render_mysql
        prepared_statement=prepare(manager, final_statement.statement)
        result=execute_core(prepared_statement, final_statement.parameters)
        prepared_statement|>MySQL.DBInterface.close!
    elseif isa(manager, DBManager{:postgresql})
        final_statement=stmt|>render_postgresql
        prepared_statement=prepare(manager, final_statement.statement)
        result=execute_core(prepared_statement, final_statement.parameters)
        result|>LibPQ.close
    else
        throw("Function not implemented for this type.")
    end
end

function execute_withdf(manager::DBManager, stmt::StatementObject)
    if isa(manager, DBManager{:sqlite})
        final_statement=stmt|>render_sqlite
        prepared_statement=prepare(manager, final_statement.statement)
        result=execute_core(prepared_statement, final_statement.parameters)
        df=result|>DataFrame
        (prepared_statement, result).|>SQLite.DBInterface.close!
        df
    elseif isa(manager, DBManager{:mysql})
        final_statement=stmt|>render_mysql
        prepared_statement=prepare(manager, final_statement.statement)
        result=execute_core(prepared_statement, final_statement.parameters)
        df=result|>DataFrame
        prepared_statement|>MySQL.DBInterface.close!
        df
    elseif isa(manager, DBManager{:postgresql})
        final_statement=stmt|>render_postgresql
        prepared_statement=prepare(manager, final_statement.statement)
        result=execute_core(prepared_statement, final_statement.parameters)
        df=result|>DataFrame
        result|>LibPQ.close
        df
    else
        throw("Function not implemented for this type.")
    end
end



function create(manager::DBManager, schema::Type{T} where T<:Schema)
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(schema)
    table_data=generate_intermediate_tabledata(schema)|>
    x->begin
        if isa(manager, DBManager{:sqlite})
            x|>generate_final_tabledata_sqlite
        elseif isa(manager, DBManager{:mysql})
            x|>generate_final_tabledata_mysql
        elseif isa(manager, DBManager{:postgresql})
            x|>generate_final_tabledata_postgresql
        else
            throw("Function not implemented for this type.")
        end
    end
    stmt=Sql("create table if not exists $(schema_name) ($table_data);")
    execute(manager, stmt)
end



function drop(manager::DBManager, schema::Type{T} where T<:Schema)
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(schema)
    stmt=Sql("drop table if exists $(schema_name);")
    execute(manager, stmt)
end



function insert(manager::DBManager, instance::T where T<:Schema)
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(instance|>typeof)
    fields=fieldnames(instance|>typeof)|>collect
    if autoincrement(instance|>typeof)==true && isa(getfield(instance, primary(instance)), Missing)
        filter!(x->x!=primary(instance), fields)
    end
    col_names=@pipe fields|>join(_, ", ")
    
    stmt_values=@pipe fields|>
    map(x->Sql("$(P(getfield(instance, x)))"), _)|>
    collect|>
    concat(_, ", ")
    
    stmt=Sql("insert into $(schema_name) ($(col_names)) values ($(N(stmt_values)));")
    execute(manager, stmt)
end



function select(manager::DBManager, schema::Type{T} where T<:Schema, columns::NTuple{N, Symbol} where N; where::StatementObject=Sql("true"))
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(schema)
    columns=@pipe columns|>join(_, ", ")
    stmt_where=where
    stmt=Sql("select $(columns) from $(schema_name) where $(N(stmt_where))")
    execute_withdf(manager, stmt)
end

function select(manager::DBManager, schema::Type{T} where T<:Schema, columns::Symbol...; where::StatementObject=Sql("true"))
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(schema)
    columns=@pipe columns|>join(_, ", ")
    stmt_where=where
    stmt=Sql("select $(columns) from $(schema_name) where $(N(stmt_where))")
    execute_withdf(manager, stmt)
end

function select(manager::DBManager, schema::Type{T} where T<:Schema, column::Symbol=:(*); where::StatementObject=Sql("true"))
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(schema)
    stmt_where=where
    stmt=Sql("select $(column) from $(schema_name) where $(N(stmt_where))")
    execute_withdf(manager, stmt)
end



function delete(manager::DBManager, instance::T where T<:Schema)
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(typeof(instance))
    stmt_where=Sql("$(primary(instance))=$(P(getfield(instance, primary(instance))))")
    stmt=Sql("delete from $(schema_name) where $(N(stmt_where));")
    execute(manager, stmt)
end

function delete(manager::DBManager, schema::Type{T} where T<:Schema; where::StatementObject=Sql("false"))
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(schema)
    stmt_where=where
    stmt=Sql("delete from $(schema_name) where $(N(stmt_where));")
    execute(manager, stmt)
end



function update(manager::DBManager, instance::T where T<:Schema; where::Union{StatementObject, Nothing}=nothing)
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(instance|>typeof)
    stmt_where=where
    if where==nothing
        stmt_where=Sql("$(primary(instance))=$(P(getfield(instance, primary(instance))))")
    end
    
    stmt_set=@pipe fieldnames(instance|>typeof)|>
    map(x->Sql("$(x)=$(P(getfield(instance, x)))"), _)|>collect|>
    concat(_, ", ")
    
    stmt=Sql("update $(schema_name) set $(N(stmt_set)) where $(N(stmt_where));")
    execute(manager, stmt)
end

function update(manager::DBManager, schema::Type{T} where T<:Schema, sets::NTuple{N, Pair{Symbol, T}} where {N, T}; where::StatementObject)
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(schema)
    stmt_where=where
    stmt_set=@pipe sets|>map(x->Sql("$(x.first)=$(P(x.second))"), _)|>collect|>concat(_, ", ")
    stmt=Sql("update $(schema_name) set $(N(stmt_set)) where $(N(stmt_where));")
    execute(manager, stmt)
end

function update(manager::DBManager, schema::Type{T} where T<:Schema, sets::(Pair{Symbol, T} where T<:Any)...; where::StatementObject)
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(schema)
    stmt_where=where
    stmt_set=@pipe sets|>map(x->Sql("$(x.first)=$(P(x.second))"), _)|>collect|>concat(_, ", ")
    stmt=Sql("update $(schema_name) set $(N(stmt_set)) where $(N(stmt_where));")
    execute(manager, stmt)
end

