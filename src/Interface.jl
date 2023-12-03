include("./Objects.jl")
include("./Kernel_functions.jl")
include("./SQLbuilder.jl")

mutable struct DBManager{DBMS}
    connection
end

# Run only once, after 'using MinORM' or changing DBMS. You can just use 'connect()' to get the DBManager instance afterwards.
macro init()
    quote
        dbms=MinORM.getenv()
        if dbms=="sqlite"
            (@__MODULE__).eval(:(using Pkg; Pkg.add("SQLite");import SQLite))
            MinORM.DBManager{:sqlite}()
        elseif dbms=="mysql" || dbms=="mariadb"
            (@__MODULE__).eval(:(using Pkg; Pkg.add("MySQL");import MySQL))
            MinORM.DBManager{:mysql}()
        elseif dbms=="postgresql"
            (@__MODULE__).eval(:(using Pkg; Pkg.add("LibPQ");import LibPQ))
            MinORM.DBManager{:postgresql}()
        elseif dbms=="duckdb"
            println("Not yet supported")
        else
            error("Unsupported DBMS type $dbms")
        end
    end
end

getenv()=begin
    cfg=DotEnv.config()
    return get(cfg, "DBMS", "UNDEFINED")
end

function connect()
    dbms=getenv()
    if dbms=="sqlite"
        MinORM.DBManager{:sqlite}()
    elseif dbms=="mysql" || dbms=="mariadb"
        MinORM.DBManager{:mysql}()
    elseif dbms=="postgresql"
        MinORM.DBManager{:postgresql}()
    elseif dbms=="duckdb"
        println("Not yet supported")
    else
        error("Unsupported DBMS type $dbms")
    end
end


function setup_prompt()
    println("Select the DBMS you're about to use.\n 1) SQLite\n 2) MySQL / MariaDB\n 3) PostgreSQL\n 4) DuckDB")
    dbms=readline()
    if dbms=="1"
        println("Select the type of DB you want.\n 1) In-memory (Press enter without typing anything beforehand)\n 2) File (Type the DB name)")
        path=readline()
        open(".env", "w") do x
            write(x, "DBMS=sqlite\ndb_path=$path.sqlite")
        end
        nothing
    elseif dbms=="2"
        print("Host address: ")
        address=readline()
        print("Port(Optional. Skip if you want to use the default port, 3306): ")
        port=readline()
        print("User: ")
        user=readline()
        print("Password: ")
        password=readline()
        print("DB name: ")
        db=readline()
        open(".env", "w") do x
            write(x, "DBMS=mysql\nhost=$address\n$(port=="" ? "" : "port=$port\n")user=$user\npasswd=$password\ndb=$db")
        end
        nothing
    elseif dbms=="3"
        print("Host address: ")
        address=readline()
        print("Port(Optional. Skip if you want to use the default port, 5432): ")
        port=readline()
        print("User: ")
        user=readline()
        print("Password: ")
        password=readline()
        print("DB name: ")
        db=readline()
        open(".env", "w") do x
            write(x, "DBMS=postgresql\nhost=$address\n$(port=="" ? "" : "port=$port\n")user=$user\npasswd=$password\ndb=$db")
        end
        nothing
    elseif dbms=="4"
    else
        println("Unsupported DBMS type. Choose among 1~4.")
    end
end


function close!(object)
    DBInterface.close!(object)
end

function close!(cursor::DBInterface.Cursor)
    DBInterface.close!(cursor)
end

function close!(manager::DBManager) 
    DBInterface.close!(manager.connection)
end


function close!(manager::DBManager, statement) end
function close!(manager::DBManager, statement::DBInterface.Statement)
    DBInterface.close!(statement)
end



function prepare(manager::DBManager, query_format::String) 
    DBInterface.prepare(manager.connection, query_format)
end

function execute_core(statement, params)
    DBInterface.execute(statement, params)
end

function execute_core(manager::DBManager, query::String)
    DBInterface.execute(manager.connection, query)
end

function render(manager::DBManager, statement::StatementObject) end

function execute(manager::DBManager, statement::StatementObject)
    final_statement=render(manager, statement)
    prepared_statement=prepare(manager, final_statement.statement)
    result=execute_core(prepared_statement, final_statement.parameters)
    close!(manager, prepared_statement)
    close!(manager, result)
    nothing
end

function execute_withdf(manager::DBManager, statement::StatementObject)
    final_statement=render(manager, statement)
    prepared_statement=prepare(manager, final_statement.statement)
    result=execute_core(prepared_statement, final_statement.parameters)
    df=result|>DataFrame
    close!(manager, statement)
    close!(manager, result)
    df
end

function create(manager::DBManager, schema::Type{T} where T<:Schema)
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(schema)
    tabledata=generate_tabledata(manager, schema)
    stmt=Sql("create table $(schema_name) ($(tabledata));")
    execute(manager, stmt)
end

function create_withouterr(manager::DBManager, schema::Type{T} where T<:Schema)
    (Sql, P, N)=statementbuilder()
    schema_name=typeto_snakecase_name(schema)
    tabledata=generate_tabledata(manager, schema)
    stmt=Sql("create table if not exists $(schema_name) ($(tabledata));")
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

function update(manager::DBManager, schema::Type{T} where T<:Schema, sets::NTuple{N, Pair{Symbol, T} where T} where N; where::StatementObject)
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

