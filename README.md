# MINORM.jl
## A minimal ORM-ish layer on top of SQLite.jl, MySQL.jl, and LibPQ.jl.
---
<p style="text-align: center;font-size: 20px">
Disclaimer
</p>  

This package is not meant to be an actual, well-working ORM. It has very few functionalities, its queries & execution not well tuned, and its design just crude. **Its sole purpose is to dynamically create parameterized SQL queries for frequently used patterns, so that SQL injection can be prevented,** and nothing more. For general usage, Searchlight.jl would be a far better option.
However, if you're fine with minimal ORM functionality and mediocre performance, it may not be so bad.

<br><br>

Since we talked about its incompetency already, let's skip to the good part. This package lets you... 
- work on multiple DBMS (currently supported: SQLite, MySQL/MariaDB, Postgresql) 
- easily setup configuration (via .env file)
- write your own sql query, in a safe way
- easily configure its structure(as there's nothing much to it really, but a simple layer on top of DBInterface.jl)

# Tutorial

## 1. Manage configuration.

Create a .env file in your working directory, which will be responsible for configuration information necessary to connect to the DBMS.

.env file should hold...
- SQLite  


```
DBMS=sqlite

# Leave as blank or comment using '#' if you want to use SQLite in-memory.
# New DB file will be created if it doesn't exist in the specified path.
db_path=./test.sqlite

```
- MySQL / MariaDB
```
# For both MySQL and MariaDB. You can also use 'mariadb', though what it does is completely the same.
DBMS=mysql

# HOST, USER, PASSWD values must be included. 
# Others are optional, and simply comment them if you want to use the default values.
# (port=3306, db(database name)="")
host=127.0.0.1
user=test
passwd=testing
# If you want to use the default value, commment the field using '#'.
#port=
db=test
```

- Postgresql
```
DBMS=postgresql

# Same as MySQL/MariaDB, with port=5432 as default.
 
host=127.0.0.1
user=test
passwd=testing
# If you want to use the default value, commment the field using '#'.
#port=
db=test
```  

And that's it! That's all you have to do, and the rest will be taken care of by MinORM.

Before we go to the next step, remember that although you can add additional fields other than the ones above, **they are not supported/tested and might break the configuration.** So use with caution if you want to use extra fields.

## 2. Create the DBManager instance. 

Connection between Julia and DBMS is managed by the DBManager instance.
DBManager is a struct that holds the DBMS type and connection to the corresponding DBMS.
```julia

mutable struct DBManager{DBMS}
    connection
end
```
The DBManager can be instantiated by the "setup()" function, which will automatically create the DBManager instance for the DBMS you specified in the .env file. Alternatively, you can use DBManager{DBMS}() to manually specify the DBMS type (Currently supported: DBManager{:sqlite}(), DBManager{:mysql}, DBManager{:postgresql}).

## 3. Define struct representing the table.

Struct is used to define the table and its rows. Such struct must abide by these rules:
- Must be a subtype of abstract type 'MinORM.Schema'
- Must have a 'primary' function defined, which takes the struct's type as argument,and outputs the primary key's field name as type 'Symbol'
- Default values can be set, but not in the DBMS itself; It will be taken care of in Julia, via @kwdef.
- If you want values to be nullable, use Union{Missing, T}, with T being a concrete type.

Currently supported types and their conversion are:
Int64, Int32=>INTEGER
Float64, Float32=>DECIMAL
Dates.DateTime=>DATETIME
String=>TEXT
String_{N}=>VARCHAR(N)

String_{N} is a custom type, representing a string with limited capacity of N. It will throw an error if you try to insert a string with length greater than N. You can either use its constructor String_{N}(x::String), or simply assign a string using '=' to the field with type String_{N}, as Base.convert is implemented as such.



