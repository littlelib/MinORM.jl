include("MinORM.jl")

function insert(manager::DBManager, instances::Vector{T} where T<:Schema)
    (Sql, P, N)=statementbuilder()
    if !(eltype(instances)<:typeof(first(instances)))
        error("Instances must be a vector of same schema")
    end
    schema_name=typeto_snakecase_name(instances|>eltype)
    fields=fieldnames(instance|>eltype)|>collect
    if autoincrement(instance|>eltype)==true && isa(getfield(instance, primary(instance)), Missing)
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