module MinORM_MySQL
using MinORM, DotEnv, MySQL, Pipe
import MinORM

""".env file must include HOST, USER, PASSWD. Others are optional."""
function connectfromenv_mysql()
    cfg=DotEnv.config().dict
    delete!(cfg, "DBMS")
    args=[pop!(cfg, "host"), pop!(cfg, "user"), pop!(cfg, "passwd")]
    cfg=merge(Dict{Any, Any}(), cfg)
    if haskey(cfg, "port")
        cfg["port"]=parse(Int, cfg["port"])
    end
    cfg=@pipe cfg|>collect|>map(x->Symbol(x.first)=>x.second, _)
    MySQL.DBInterface.connect(MySQL.Connection, args...;cfg...)
end

MinORM.DBManager{:mysql}()=MinORM.DBManager{:mysql}(connectfromenv_mysql())
MinORM.render(manager::MinORM.DBManager{:mysql}, statement::MinORM.StatementObject)=MinORM.render_mysql(statement)
MinORM.generate_final_tabledata(manager::MinORM.DBManager{:mysql}, intermediate)=MinORM.generate_final_tabledata_core(intermediate, ["primary key auto_increment", "primary key", "not null"])

end