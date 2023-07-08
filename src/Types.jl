using Match, Dates
import Base

mutable struct String_{N}
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
limit(x::Type{String_{N}}) where N=N

function convertinto_sqltype(x)  
    @match x begin
        t::Type{Float64}=>"papasdf"
        t::Type{Float32}=>"decimal"
        t::Type{Int64}=>"int"
        t::Type{Int32}=>"int"
        t::Type{String}=>"text"
        t::Type{Dates.DateTime}=>"datetime"
        t::Type{String_{0}}=>"text"
        t::Type{<:String_}=>"varchar($(limit(t)))"
        _=>println("Unsupported type")
    end
end
