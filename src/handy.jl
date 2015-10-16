# Handy wrappers to functions defined in api.jl.

"""
A handy function that wraps mysql_init and mysql_real_connect. Also does error
checking on the pointers returned by init and real_connect.
"""
function mysql_connect(host::String,
                        user::String,
                        passwd::String,
                        db::String,
                        port::Integer,
                        unix_socket::Any,
                        client_flag::Integer)

    mysqlptr::MYSQL = C_NULL
    mysqlptr = mysql_init(mysqlptr)

    if mysqlptr == C_NULL
        error("Failed to initialize MySQL database")
    end

    mysqlptr = mysql_real_connect(mysqlptr,
                                  host,
                                  user,
                                  passwd,
                                  db,
                                  convert(Cint, port),
                                  unix_socket,
                                  convert(Culong, client_flag))

    if mysqlptr == C_NULL
        error("Failed to connect to MySQL database")
    end

    return mysqlptr
end

"""
Wrapper over mysql_real_connect with CLIENT_MULTI_STATEMENTS passed
as client flag options.
"""
function mysql_connect(hostName::String, userName::String, password::String, db::String)
    return mysql_connect(hostName, userName, password, db, 0,
                         C_NULL, CLIENT_MULTI_STATEMENTS)
end

"""
Wrapper over mysql_close. Must be called to close the connection opened by mysql_connect.
"""
function mysql_disconnect(db::MYSQL)
    mysql_close(db)
end

"""
A function for executing queries and getting results.

In the case of multi queries returns an array of number of affected
 rows and DataFrames. The number of affected rows correspond to the
 non-SELECT queries and the DataFrames for the SELECT queries in the
 multi-query.

In the case of non-multi queries returns either the number of affected
 rows for non-SELECT queries or a DataFrame for SELECT queries.

By default, returns SELECT query results as DataFrames.
 Set `opformat` to `MYSQL_ARRAY` to get results as arrays.
"""
function mysql_execute_query(con::MYSQL, command::String, opformat=MYSQL_DATA_FRAME)
    response = mysql_query(con, command)
    mysql_display_error(con, response)

    data = Any[]

    while true
        result = mysql_store_result(con)
        if result != C_NULL # if select query
            retval = Nothing
            if opformat == MYSQL_DATA_FRAME
                retval = mysql_result_to_dataframe(result)
            else opformat == MYSQL_ARRAY
                retval = mysql_get_result_as_array(result)
            end
            push!(data, retval)
            mysql_free_result(result)

        elseif mysql_field_count(con) == 0
            push!(data, @compat Int(mysql_affected_rows(con)))
        else
            mysql_display_error(con,
                                "Query expected to produce results but did not.")
        end
        
        status = mysql_next_result(con)
        if status > 0
            mysql_display_error(con, "Could not execute multi statements.")
        elseif status == -1 # if no more results
            break
        end
    end

    if length(data) == 1
        return data[1]
    end
    return data
end

"""
A handy function to display the `mysql_error` message along with a user message `msg` through `error`
 when `condition` is true.
"""
function mysql_display_error(con, condition::Bool, msg)
    if (condition)
        err_string = msg * "\nMySQL ERROR: " * bytestring(mysql_error(con))
        error(err_string)
    end
end

mysql_display_error(con, condition::Bool) = mysql_display_error(con, condition, "")
mysql_display_error(con, response, msg) = mysql_display_error(con, response != 0, msg)
mysql_display_error(con, response) = mysql_display_error(con, response, "")
mysql_display_error(con, msg::String) = mysql_display_error(con, true, msg)

"""
Given a prepared statement pointer `stmtptr` returns a dataframe containing the results.
`mysql_stmt_prepare` must be called on the statement pointer before this can be used.
"""
function mysql_stmt_result_to_dataframe(stmtptr::Ptr{MYSQL_STMT})
    stmt = unsafe_load(stmtptr)
    metadata = mysql_stmt_result_metadata(stmtptr)
    mysql_display_error(stmt.mysql, metadata == C_NULL,
                        "Error occured while retrieving metadata")

    response = mysql_stmt_execute(stmtptr)
    mysql_display_error(stmt.mysql, response,
                        "Error occured while executing prepared statement")

    retval = mysql_stmt_result_to_dataframe(metadata, stmtptr)
    mysql_free_result(metadata)
    return retval
end
