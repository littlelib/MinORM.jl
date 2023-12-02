module MinORM

using DataFrames, DotEnv, Pipe, Dates, DBInterface
import Base


include("./Interface.jl")
include("devels.jl")

export DBManager, @init, setup_prompt, connect, close!, execute, execute_withdf, create, drop, insert, select, delete, update, Schema, statementbuilder, Sql, P, N, StmtObject, concat, String_, primary, autoincrement

end # module MinORM
