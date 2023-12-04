
function insert(manager::DBManager, instances::Vector{T} where T<:Schema)
    (Sql, P, N)=statementbuilder()
    if !(eltype(instances)<:typeof(first(instances)))
        error("Instances must be a vector of same schema")
    end
    schema_name=typeto_snakecase_name(instances|>eltype)
    fields=fieldnames(instances|>eltype)|>collect
    if autoincrement(instances|>eltype)==true && isa(getfield(first(instances), primary(instances|>eltype)), Missing)
        filter!(x->x!=primary(instances|>eltype), fields)
    end
    col_names=@pipe fields|>join(_, ", ")
    
    stmt_value_sets=map(instance->begin
        @pipe fields|>
        map(x->Sql("$(P(getfield(instance, x)))"), _)|>
        concat(_, ", ")|>
        Sql("($(N(_)))")
        end, instances)|>
    x->concat(x, ", ")
        
    stmt=Sql("insert into $(schema_name) ($(col_names)) values $(N(stmt_value_sets));")
    execute(manager, stmt)
end