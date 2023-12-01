module MinORM_SQLite
using MinORM, DotEnv, SQLite, DBInterface
import MinORM

function connectfromenv_sqlite()
    config=DotEnv.config().dict
    delete!(config, "DBMS")
    if haskey(config, "db_path")
        SQLite.DB(config["db_path"])
    else
        SQLite.DB()
    end
end

MinORM.DBManager{:sqlite}()=MinORM.DBManager{:sqlite}(connectfromenv_sqlite())
MinORM.render(manager::MinORM.DBManager{:sqlite}, statement::MinORM.StatementObject)=MinORM.render_sqlite(statement)
MinORM.generate_final_tabledata(manager::MinORM.DBManager{:sqlite}, intermediate)=MinORM.generate_final_tabledata_core(intermediate, ["primary key autoincrement", "primary key", "not null"])

end