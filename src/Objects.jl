include("./Types.jl")

abstract type Schema end

"""
These attributes must be set manually when creating table representing objects.

primary key: Set by defining function "primary" for the object type or its instance. Should be of type Union{Int, Missing} with its defaults set to "missing" if you want to autoincrement it, and it will autoincremented value when executed in DBMS.
defaults: Set by @kwdef. Just handle it in Julia, not in the DBMS.
nullable: If nullable, make it a type of Union{T, Missing}
autoincrement: Set function autoincrement(::Type{T})=true if you want to enable autoincrement.

Primary key can't have constant defaults(as it must be unique), and should not be nullable.
Every table MUST contain a primary key, otherwise it will get a stackoverflow error(due to the intermediary generic function). If you don't want one, just create a dummy column for it.


"""
primary(x::T where T<:Schema)=primary(typeof(x))
primary(x)=throw("function 'primary' is not defined for this type.")
autoincrement(x::T where T<:Schema)=autoincrement(typeof(x))
autoincrement(x)=false
"""
@kwdef mutable struct Test <: Schema
    x::Union{Int, Missing}=missing
    y::Union{String, Missing}="Default value"
end
Test(x::String)=Test(missing, x)
primary(::Type{Test})=:x
autoincrement(::Type{Test})=true

@kwdef mutable struct Test_2 <: Schema
    x::Union{Int, Missing}=missing
    y::Union{String}="Default value"
end
primary(::Type{Test_2})=:x
autoincrement(::Type{Test_2})=true
"""

"""generate most of the tabledata here, since only types common to most DBMSs are used.
However, there are differences in how DBMSs define attributes(such as autoincrement), so they will be generated after the DBMS to use is decided."""
function generate_intermediate_tabledata(schema::Type{T} where T<:Schema)
    fields=fieldnames(schema)
    types=fieldtypes(schema)
    types_parsed=map(x->convertinto_sqltype(x), types)
    tabledata=@pipe zip(fields, types_parsed)|>
    map(x->join(x, " "), _)
    (tabledata, schema)
end

function generate_final_tabledata_core(intermediate, queries::Vector{String})
    intermediate_tabledata=intermediate[1]
    schema=intermediate[2]
    fields=fieldnames(schema)
    type_attributes=map(x->begin
        if x==primary(schema)
            if autoincrement(schema)==true && fieldtype(schema, x)<:Union{Missing, Nothing, Signed, Unsigned}
                queries[1]
            else
                queries[2]
            end
        elseif !(Nothing<:fieldtype(schema, x)) && !(Missing<:fieldtype(schema, x))
            queries[3]
        else
            ""
        end
    end, fields)
    @pipe zip(intermediate_tabledata, type_attributes)|>
    map(x->join(x, " "), _)|>
    join(_, ", ")
end

function generate_final_tabledata(manager, intermediate)
end

function generate_tabledata(manager, schema::Type{T} where T<:Schema)
    @pipe generate_intermediate_tabledata(schema)|>
    generate_final_tabledata(manager, _)
end



