module DBControls


required_packages=["ODBC", "DotEnv"]

include("./manipulators.jl")
import .Manipulators

Manipulators.@auto_import required_packages

######################
# Environment setups

DotEnv.config()

#Choose which driver plugin to choose. In this version, it has only 2 options- MariaDB/Debian11/amd64 and MariaDB/Debian11/aarch64.
#DRIVER_PLUGIN_LOCATION is the location of lib*odbc.so.
DRIVER_LOCATION_DICT=Dict(:x86_64 => "odbc_connectors/mariadb-connector-odbc-3.1.18-debian-bullseye-amd64/lib/mariadb/libmaodbc.so",
:aarch64 => "odbc_connectors/mariadb-connector-odbc-3.1.18-debian-bullseye-aarch64/lib/mariadb/libmaodbc.so"
)
DRIVER_NAME="mariadb"


function setup()
    DRIVER_PLUGIN_LOCATION=begin
        if haskey(DRIVER_LOCATION_DICT, Sys.ARCH)==true && Sys.KERNEL==:Linux
            "$(@__DIR__)/$(DRIVER_LOCATION_DICT[Sys.ARCH])"
        else
            error("Currently unsupported architecture or OS.")
        end
    end
    ODBC.adddriver(DRIVER_NAME, DRIVER_PLUGIN_LOCATION)
end

function getconnection()
    connection=ODBC.Connection("Driver=$(DRIVER_NAME);DATABASE=$(ENV["DATABASE"]);", user=ENV["UID"], password=ENV["PASSWD"])
    return connection
end


######################


"""
Struct DBManager stores the connection{ODBC.Connection} and...some other stuff, maybe in the future.
"""
mutable struct DBManager
    connection::ODBC.Connection
end

DBManager(conn)=DBManager(conn)



"""These functions are responsible for execution of statements and query strings."""

function execute(self::DBManager, sql::String)
    ODBC.DBInterface.execute(self.connection, sql)
end

"""Closes connection of DBManager.connection."""
function close!(self::DBManager)
    self.connection|>ODBC.DBInterface.close!
end

end

