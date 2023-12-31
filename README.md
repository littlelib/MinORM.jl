# MINORM.jl
## A minimal ORM-ish layer on top of SQLite.jl, MySQL.jl, and LibPQ.jl.
---
<p style="text-align: center;font-size: 20px">
Disclaimer
</p>  

This package is not meant to be an actual, well-working ORM. It has very few functionalities, its queries & execution not well tuned, and its design just crude. **Its sole purpose is to dynamically create parameterized SQL queries for frequently used patterns, so that SQL injection can be prevented,** and nothing more. For general usage, Searchlight.jl or Wasabi.jl would be a far better option.
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
Connection to DBMS can be closed via MinORM.close!(manager::DBManager) function, and reconnected via MinORM.reconnect!(manager::DBManager).

## 3. Define struct representing the table.

Struct is used to define the table, and its instance to define each row. Such struct must abide by these rules:
- Must be a subtype of abstract type 'MinORM.Schema'
- Must have a 'primary' function defined, which takes the struct's type as argument,and outputs the primary key's field name as type 'Symbol'
- Default values can be set, but not in the DBMS itself; It will be taken care of in Julia, via @kwdef.
- If you want values to be nullable, use Union{Missing, T}, with T being a concrete type.

Currently supported types and their conversion are:
- Int64, Int32=>INTEGER
- Float64, Float32=>DECIMAL
- Dates.DateTime=>DATETIME
- String=>TEXT
- String_{N}=>VARCHAR(N)

String_{N} is a custom type, representing a string with limited capacity of N. It will throw an error if you try to insert a string with length greater than N. You can either use its constructor String_{N}(x::String), or simply assign a string using '=' to the field with type String_{N}, as Base.convert is implemented as such.

An example struct can be constructed like this:
```julia
using MinORM
# Must import MinORM, since you're going to extend MinORM.primary and MinORM.autoincrement.
import MinORM

manager=setup()

@kwdef mutable struct Test <: Schema
    id::Union{Missing, Int64}=missing
    name::String_{10}
    phone_number::Union{Missing, String_{13}}=missing
    favorite_movie::Union{Missing, String_{20}}="John Wick"
end

# Must be defined. It must be of type 'Symbol'.
MinORM.primary(::Type{Test})=:id
# Optional. Default is set to false. Must be an Int type for it to work, although no error message will be provided if not.
MinORM.autoincrement(::Type{Test})=true
```
SQL tables allow having these attributes:
- primary key
- not null
- default
- autoincrement  

In MinORM, primary key is defined by the 'primary' function, taking the struct type and returning the field name in type 'Symbol'. 'not null' is defined by not adding 'Missing' to its type definition, and 'default' is set by @kwdef, not the DBMS. 'autoincrement' is allowed only when autoincrement(::T) is set to true, and the primary key will be autoincremented if it's of type Int and the value is 'missing'.

## 4. Building SQL query 
Although MinORM tries to be an ORM, or something simillar to it at least, it does promote using user-defined SQL, rather than abstracting it. The only difference between a raw SQL query and MinORM's query is that 
1) MinORM has a way of building SQL statement in a way safe from SQL injection.
2) MinORM has boilerplate functions for basic instructions.

MinORM's query is defined by a StatementObject(Statement object), which is actually just a type of Tuple{String, Vector{Any}}. String part holds the parameterized SQL statement, and Vector{Any} part holds the parameters.
You can create a StatementObject using this syntax.
```julia
Sql("select id, name from Test where id=$(P(32)));") 
```
The function 'P'(Parameters) is a closure that encapsulates the variable it receives and returns "?". The function Sql, which is also a closure, takes the created string and the encapsulated variables, and returns a StatementObject with both the parameterized SQL statement and the vector of encapsulated variables.  
You can also concatenate multiple StatementObjects using 'concat' function.
```julia
a=Sql("ID=$(P(20230710))")
b=Sql("NAME=$(P("John"))")
julia> concat(a,b," AND ")
MinORM.StatementObject("ID=? AND NAME=?", Any[20230710, "John"])

multiple_statementobjects=[a,b,Sql("FAVORITE_FRUIT=$(P("Kiwi"))")]
julia> concat(multiple_statementobjects, " AND ")
MinORM.StatementObject("ID=? AND NAME=? AND FAVORITE_FRUIT=?", Any[20230710, "John", "Kiwi"])
```
You can nest a StatementObject inside a StatementObject using 'N'(Nest) function. It helps create complex queries.
```julia
a=Sql("ID=$(P(20230710))")
b=Sql("NAME=$(P("John"))")
julia> Sql("update TEST set $(N(b)) where $(N(a));")
MinORM.StatementObject("update TEST set NAME=? where ID=?;", Any["John", 20230710])
```
By concatenating and nesting StateObjects, you can create any parameterized query you want! This is also how every boilerplate functions are created. Keep in mind, though, that globally defined functions Sql, P, and N are just closures derived from a single instance of 'statementbuilder' function-that is, they all share the same environment. This can be problematic if you plan on using these closures in asynchronous functions. So in such cases, you have to manually define closures Sql, P, and N for your individual async scope, like this:
```julia
function test()
(Sql, P, N)=statementbuilder();
# Do something with these closures.
...
end
@async test()
```
Boilerplate functions already have closures for their own environment, so are safe to use asynchronously-least for building queries.


Most of the time, you'd be using StatementObjects inside of a boilerplate function, to create only a portion of the required query. However, you can also create the whole query without boilerplate function, and directly execute the generated StatementObject, if that's what you want. Use 'execute' function if you don't want the result, and if you want the result as DataFrames.DataFrame type, you can use 'execute_withdf' function.
```julia
execute(manager::DBManager, stmt::StatementObject)
execute_withdf(manager::DBManager,)
```

## 5. Boilerplate functions - create, drop, insert, select, delete, update
MinORM comes with boilerplate instructions for basic SQL patterens. Before we go into details, first we'll set up the test environment.
```julia
@kwdef mutable struct Test <: Schema
    id::Union{Missing, Int64}=missing
    name::String_{10}
    phone_number::Union{Missing, String_{13}}=missing
    favorite_movie::Union{Missing, String_{20}}="John Wick"
end

MinORM.primary(::Type{Test})=:id
MinORM.autoincrement(::Type{Test})=true

manager=setup()
```
- create  
  ```julia
  create(manager, Test)
  ``` 
  MinORM will execute a SQL query to create the table. If it was MySQL, for example, it would execute "create table if not exists test (id integer primary key auto_increment, name varchar(10) not null, phone_number varchar(13), favorite_movie varchar(20));". Default is not included in the SQL query, as it would be handled in MinORM, not the DBMS.

- drop  
  ```julia
  drop(manager, Test)
  ```
  Drop table if it exists.
- insert
  ```julia
  a=Test(name="Winston") # Test(missing, "Winston", missing, "John Wick")
  b=Test(id=31, name="Marcus") # Test(31, "Marcus", missing, "John Wick")
  insert(manager, a) # id will be autoincremented.
  insert(manager, b) # id will use the defined value.
  ```
  You can insert into a table by putting the instance of table as an argument. Note that if you want to use the autoincremented value, you leave the primary key's field value as 'missing'.
- select
  ```julia
  # Equivalent of "select * from test where true;".
  select(manager, Test) 
  # Equivalent of "select id, name, phone_number from test where true;". Field names should be of type Symbol.
  select(manager, Test, :id, :name, :phone_number) 
  # You can also put field names inside a tuple.
  select(manager, Test, (:id, :name, :phone_number)) 
  # You can optionally provide keyword "where" of type StatementObject.
  select(manager, Test, :id, :name, :phone_number, where=Sql("id=1")) 
  ```
  Select returns DataFrames.DataFrame object. Keyword "where" has to be of type StatementObject.
- delete
  ```julia
  # When deleting with instance, it's actually using the instance's primary key value, so you must specify it.
  delete(manager, Test(1, "Winston", missing, "John Wick")) 
  # 'where' keyword should be specified, otherwise it will do nothing.
  delete(manager, Test, where=Sql("id=1"))
  ```
  You can either use the table instance with its primary key's value specified(not of value 'missing'), or use the table type itself and provide keyword 'where'.
- update
  ```julia
  # Update using a table instance. It uses primary key's value to decide which row to update, so it must be set properly. Keep it mind that this method can't change the primary key itself.
  update(manager, Test(31, "Marcus", "999-9999-9999", "Spiderman"))
  # Use "Pair{Symbol, T} where T" to update columns, and use keyword 'where' to decide which row(or rows) to update. You can also change the primary key.
  update(manager, Test, :id=>2, :name=>"Norman", where=Sql("name='Marcus'"))
  # You can also put pairs inside a tuple.
  update(manager, Test, (:id=>2, :name=>"Norman"), where=Sql("name='Marcus'"))
  ```


