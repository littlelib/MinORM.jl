# MINORM.jl
## A minimal ORM-ish layer on top of SQLite.jl, MySQL.jl, LibPQ.jl.
---
Warning: This package is not meant to be an actual, well-working ORM. It has very few functionalities, its queries not well tuned, and its design just crude. **Its sole purpose is to dynamically create prepared statements for frequently used patterns, so that sql injection can be prevented, and nothing more.**


