mutable struct String_{N} <: AbstractString
    body::String
    String_{N}(x::String) where N=begin
        if length(x)>N
            throw("String length exceeds designated capacity")
        else
            new(x)
        end
    end
end

Base.convert(::Type{String_{N}}, x::String) where N=String_{N}(x)
Base.convert(::Type{String}, x::String_)=x.body
Base.length(x::String_)=length(x.body)
Base.iterate(string_::String_{N}, state::Integer=1) where N=state>length(string_) ? nothing : (string_.body[state], state+1)
limit(x::Type{String_{N}}) where N=N
limit(X::Type{Union{String_{N}, T}}) where {T<:Union{Missing, Nothing},N}=N


function convertinto_sqltype(x)  
    if Float64<:x
        "decimal"
    elseif Float32<:x
        "decimal"
    elseif Int64<:x
        "integer"
    elseif Int32<:x
        "integer" 
    elseif DateTime<:x
        "datetime"
    elseif String<:x
        "text"
    elseif String_{limit(x)}<:x
        "varchar($(limit(x)))"
    elseif isa(x, Union{Missing, nothing})
        "null"
    else
        println("Unsupported type")
    end
end