####Basic SQL statement builder
using Pipe
import Base

const StmtObject=Tuple{String, Vector{Any}}

mutable struct InfiniteRange
end

Base.iterate(inf_range::InfiniteRange, state=1)=(state, state+1)

function prepared_statement_builder()
    parameters=[]

    function getparameter(param)
        push!(parameters, param)
        return "?"
    end

    function buildstatement(statement)
        return_stmt=(statement, parameters)|>deepcopy
        parameters=[]
        return return_stmt
    end
    
    return (buildstatement, getparameter)
end



const (Sql, P)=prepared_statement_builder()

function concat(stmt1::StmtObject, stmt2::StmtObject, delimeter::String=" ")
    return (join([stmt1[1], stmt2[1]], delimeter), [stmt1[2];stmt2[2]])
end


function concat(x::Vector{StmtObject}, delimeter::String=" ")
    if length(x)==0
        return StmtObject[]
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
function renderto_postgresql(stmt_object::StmtObject)
    stmt_sql=@pipe stmt_object[1]|>
    split(_, "?")|>begin
        return_string=_[1]
        for i in 1:(length(_)-1)
            return_string*="\$$(i)$(_[i+1])"
        end
        return_string
    end
    return (stmt_sql, stmt_object[2])
end

######################


