module DBCommands

import Pkg
Pkg.activate(@__DIR__)
using Pipe

include("./manipulators.jl")
import .Manipulators

include("./01_DBControls.jl")
import .DBControls

required_packages=["ODBC", "DataFrames", "DotEnv", "Dates"]



Manipulators.@auto_import required_packages




################################
"""Constants to use"""
const TYPE_DICT_UNLIMITED=Dict(
    Int64 => "int",
    Float64=>"decimal",
    Float32=>"decimal",
    String=>"text",
    Dates.DateTime=>"datetime",
)

const TYPE_DICT_LIMITED=Dict(
    Int64 => "int",
    Float64=>"decimal",
    Float32=>"decimal",
    String=>"varchar",
    Dates.DateTime=>"datetime",
)

const Query=Tuple{Any, Any, Any}

"""Simple setup function, just to make things easier."""
function setup()
    DBControls.setup()
    manager=DBControls.DBManager(DBControls.getconnection())
    return manager
end

#########################
"""Define schemas to use in here. Use structs to hold information of the schema, and use the "attributes" function to add additional information, such as sizes or defaults.
Place 0 if there's no attribute to apply.
Beware not to use attributes to apply the primary key attribute, as it will break the program.
Use "primary" function to set primary key, by making it return n of the nth field you want to set as primary key.

Structs representing each schema should be a subtype of Schema. Each structs will be then iterated via subtypes(Schema).
"""

abstract type Schema end

attributes(x)=attributes(typeof(x))
primary(x)=primary(typeof(x))

return_closure(x)=begin
    if isnothing(x)
        throw("This type cannot be auto_incremented")
    else
        inner=x
        closure=()->begin
            inner+=1
            return inner
        end
        return closure
    end
end

function create_auto_increment(schema::Type{T} where T<:Schema, manager::DBControls.DBManager)
    getmax_symbol=@pipe schema|>primary|>fieldnames(schema)[_]|>"max($(_))"|>Symbol
    max_val=select(manager, schema, getmax_symbol)[1,1]
    if typeof(max_val)<:Real
        return return_closure(max_val)
    else
        parsed_max_val=max_val|>
        string|>
        x->(v=tryparse(Int64, x); isnothing(v) ? tryparse(Float64, x) : v)
        return return_closure(parsed_max_val)
    end
end



"""small functions for later use, when dynamically creating parameterized sql statements."""
function typeto_snakecase_name(T::Type)
    raw_name=string(T)
    last_name=split(raw_name, ".")[end]
    name=last_name|>collect
    for (i,char) in enumerate(name)
        if isuppercase(char)==true
            name[i]=lowercase(char)
            if i!=1
                insert!(name, i, '_')
            end
        end
    end
    return join(name)
end

function parse_core(query::Query, vars::Vector)
    inner_vars=vars
    if isa(query[1], Query)
        parsed=parse_core(query[1], inner_vars)
        return parse_core((parsed[1], query[2], query[3]), parsed[2])
    elseif isa(query[3], Query)
        parsed=parse_core(query[3], inner_vars)
        return parse_core((query[1], query[2], parsed[1]), parsed[2])
    else
        function ifsymbol(query)
            if isa(query, Symbol)
                return string(query)
            else
                push!(inner_vars, query)
                return "?"
            end
        end
        return (map(ifsymbol, query)|>
        x->join(x, " ")|>
        x->"($(x))"|>
        Symbol,
        inner_vars)
    end
end

function parse_query(query::Query)
    parsed=parse_core(query, [])
    return (string(parsed[1]), parsed[2])
end

function generate_sqltype(T::Type;type_dict_unlimited::Dict{DataType, String}=TYPE_DICT_UNLIMITED, type_dict_limited::Dict{DataType, String}=TYPE_DICT_LIMITED)
    converted_types=zip(fieldtypes(T), attributes(T))|>
    y->map(x->x[2]==0 ? type_dict_unlimited[x[1]] : "$(type_dict_limited[x[1]])$(x[2])", y)|>
    collect
    converted_types[primary(T)]*=" primary key"
    return converted_types
end


function parse_struct_as_set(instance)
    if isstructtype(instance|>typeof)
        field_names=instance|>typeof|>fieldnames
        parsed_set_values=[getfield(instance, i) for i in field_names]
        parsed_set_string=@pipe field_names|>map(x->"$(x) = ?", _)|>join(_, ", ")
        return (parsed_set_string, parsed_set_values)
    end
end

function parse_pair_as_set(set::NTuple{N, Pair{Symbol, T}} where {N, T})
    parsed_set_string=@pipe set|>map(x->"$(x.first) = ?", _)|>join(_, ", ")
    parsed_set_value=@pipe set|>map(x->x.second, _)|>collect
    return (parsed_set_string, parsed_set_value)
end

"""Basic SQL statement generators. They all use parameterized statements, except for create and drop"""

function create(self::DBControls.DBManager, schema::Type{T} where T<:Schema)
    schema_name=typeto_snakecase_name(schema)
    schema_def=zip(schema|>fieldnames, schema|>generate_sqltype)|>
    collect|>
    x->map(y->join(y, " "), x)|>
    x->join(x, ", ")
    sql_string="create table if not exists $(schema_name) ($(schema_def));"
    println(sql_string)
    ODBC.DBInterface.execute(self.connection, sql_string)
end

function drop(self::DBControls.DBManager, schema::Type{T} where T<:Schema)
    schema_name=typeto_snakecase_name(schema)
    sql_string="drop table if exists $(schema_name);"
    println(sql_string)
    ODBC.DBInterface.execute(self.connection, sql_string)
end

function insert(self::DBControls.DBManager, instance::T where T<:Schema)
    schema_name=typeto_snakecase_name(instance|>typeof)
    values=[getfield(instance, i) for i in instance|>typeof|>fieldnames]
    parsed_values= @pipe map(x->"?", values)|>join(_, ", ")
    stmt_string="insert into $(schema_name) values ($(parsed_values))"
    stmt=ODBC.DBInterface.prepare(self.connection, stmt_string)
    ODBC.DBInterface.execute(stmt, Tuple(values))
end

function select(self::DBControls.DBManager, schema::Type{T} where T<:Schema, to_select::Tuple; where::Query=(Symbol(true), :(=), Symbol(true)))
    parsed_select=to_select.|>string|>x->join(x, ", ")
    parsed_where=parse_query(where)
    stmt_string="select $(parsed_select) from $(typeto_snakecase_name(schema)) where $(parsed_where[1]);"
    stmt=ODBC.DBInterface.prepare(self.connection, stmt_string)
    println(stmt_string)
    val_return=ODBC.DBInterface.execute(stmt, Tuple(parsed_where[2]))|>DataFrames.DataFrame
    ODBC.DBInterface.close!(stmt)
    return val_return
end

function select(self::DBControls.DBManager, schema::Type{T} where T<:Schema, to_select::Symbol=:(*); where::Query=(Symbol(true), :(=), Symbol(true)))
    parsed_where=parse_query(where)
    println(parsed_where[1])
    println(parsed_where[2])

    stmt_string="select $(to_select) from $(typeto_snakecase_name(schema)) where $(parsed_where[1]);"
    println(stmt_string)
    stmt=ODBC.DBInterface.prepare(self.connection, stmt_string)
    val_return=ODBC.DBInterface.execute(stmt, Tuple(parsed_where[2]))|>DataFrames.DataFrame
    ODBC.DBInterface.close!(stmt)
    return val_return
end

function delete(self::DBControls.DBManager, instance::T where T<:Schema)
    schema_name=typeto_snakecase_name(instance|>typeof)
    primarykey_fieldname=(instance|>typeof|>fieldnames)[instance|>primary]
    primarykey_value=getfield(instance, primarykey_fieldname)
    println(primarykey_fieldname)
    println(Tuple(primarykey_value))
    stmt_string="delete from $(schema_name) where $(primarykey_fieldname)=?;"
    println(stmt_string)
    stmt=ODBC.DBInterface.prepare(self.connection, stmt_string)
    ODBC.DBInterface.execute(stmt, Tuple([primarykey_value]))
    ODBC.DBInterface.close!(stmt)
end

function delete(self::DBControls.DBManager, schema::Type{T} where T<:Schema; where::Query=(Symbol(true), :(=), Symbol(false)))
    parsed_where=parse_query(where)
    schema_name=typeto_snakecase_name(schema)
    stmt_string="delete from $(schema_name) where $(parsed_where[1])"
    stmt=ODBC.DBInterface.prepare(self.connection, stmt_string)
    ODBC.DBInterface.execute(stmt, Tuple(parsed_where[2]))
    ODBC.DBInterface.close!(stmt)
end

function update(self::DBControls.DBManager, instance::T where T<:Schema;where::Union{Query, Nothing}=nothing)
    if where==nothing
        primarykey_fieldname=(instance|>typeof|>fieldnames)[instance|>primary]
        primarykey_value=getfield(instance, primarykey_fieldname)
        where=(primarykey_fieldname, :(=), primarykey_value)
    end
    schema_name=typeto_snakecase_name(instance|>typeof)
    parsed_where=where|>parse_query
    parsed_set=parse_struct_as_set(instance)
    stmt_string="update $(schema_name) set $(parsed_set[1]) where $(parsed_where[1]);"
    println(stmt_string)
    stmt=ODBC.DBInterface.prepare(self.connection, stmt_string)
    ODBC.DBInterface.execute(stmt, Tuple([parsed_set[2];parsed_where[2]]))
    ODBC.DBInterface.close!(stmt)
end

function update(self::DBControls.DBManager, schema::Type{T} where T<:Schema, set::NTuple{N, Pair{Symbol, T}} where {N, T}; where::Query=(Symbol(true), :(=), Symbol(false)))
    schema_name=typeto_snakecase_name(schema)
    parsed_set=parse_pair_as_set(set)
    parsed_where=parse_query(where)
    stmt_string="update $(schema_name) set $(parsed_set[1]) where $(parsed_where[1])"
    stmt=ODBC.DBInterface.prepare(self.connection, stmt_string)
    ODBC.DBInterface.execute(stmt, Tuple([parsed_set[2];parsed_where[2]]))
    ODBC.DBInterface.close!(stmt)
end

function close!(self::DBControls.DBManager)
    ODBC.DBInterface.close!(self.connection)
end

function reconnect!(self::DBControls.DBManager)
    try
        ODBC.DBInterface.close!(self.connection)
    catch
    end
    DBControls.setup()
    self.connection=DBControls.getconnection()
end


end