####Basic SQL statement builder
@kwdef mutable struct StatementObject
    statement::String=""
    parameters::Vector{Any}=[]
end

struct FinalStatement
    statement::String
    parameters::Vector{Any}
end

mutable struct InfiniteRange
end

Base.iterate(inf_range::InfiniteRange, state=1)=(state, state+1)

function statementbuilder()
    parameters=[]

    function getparameter(param)
        push!(parameters, param)
        return "?"
    end

    function buildstatement(statement)
        return_stmt=StatementObject(statement, parameters)
        parameters=[]
        return return_stmt
    end
    
    function neststatement(stmt::StatementObject)
        append!(parameters, stmt.parameters)
        return stmt.statement
    end
    return (buildstatement, getparameter, neststatement)
end



const (Sql, P, N)=statementbuilder()

function concat(stmt1::StatementObject, stmt2::StatementObject, delimeter::String=" ")
    return StatementObject(join([stmt1.statement, stmt2.statement], delimeter), [stmt1.parameters;stmt2.parameters])
end


function concat(x::Vector{T} where T<:StatementObject, delimeter::String=" ")
    if length(x)==0
        return StatementObject[]
    elseif length(x)==1
        return x[1]
    else
        head=concat(x[1], x[2], delimeter)
        return_vec=x[2:end]
        return_vec[1]=head
        return concat(return_vec, delimeter)
    end
end




"""Must be used only right before execution/preparation, since this format is only Postgresql compatible, hence making combination with other formats error prone"""
function render_sqlite(stmt::StatementObject)
    return FinalStatement(stmt.statement*";", stmt.parameters)
end

function render_mysql(stmt::StatementObject)
    return FinalStatement(stmt.statement*";", stmt.parameters)
end

function render_postgresql(stmt::StatementObject)
    final_statement=@pipe stmt.statement|>
    split(_, "?")|>begin
        return_string=_[1]
        for i in 1:(length(_)-1)
            return_string*="\$$(i)$(_[i+1])"
        end
        return_string
    end
    return FinalStatement(final_statement*";", stmt.parameters)
end

######################


