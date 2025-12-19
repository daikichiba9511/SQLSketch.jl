"""
# Transaction Management

This module defines the transaction abstraction for SQLSketch.

Transactions provide atomic operations: all changes are committed together on success,
or all changes are rolled back on failure.

## Design Principles

- Transactions are explicit and scoped using do-blocks
- Automatic commit on success, rollback on exception
- Transaction handles are connection-compatible for query execution
- Savepoints enable nested transaction semantics
- No hidden magic - transaction boundaries are always clear

## Usage

```julia
# Basic transaction
transaction(db) do tx
    execute(tx, "INSERT INTO users (email) VALUES (?)", ["alice@example.com"])
    execute(tx, "INSERT INTO orders (user_id, total) VALUES (?, ?)", [1, 100.0])
    # Automatically commits if no exception
end

# With query execution API
transaction(db) do tx
    users = fetch_all(tx, dialect, registry, query, params)
    execute_dml(tx, dialect, insert_query)
end

# Nested transactions using savepoints
transaction(db) do tx
    execute(tx, "INSERT INTO users (email) VALUES (?)", ["alice@example.com"])

    savepoint(tx, :sp1) do sp
        execute(sp, "INSERT INTO orders (user_id, total) VALUES (?, ?)", [1, 100.0])
        # Rolls back to sp1 if error occurs here
    end

    # User insert still commits
end
```

See `docs/design.md` for detailed design rationale.
"""

"""
Abstract base type for transaction handles.

Transaction handles wrap a connection and provide transaction semantics
(commit/rollback). They are compatible with the execute() interface.
"""
abstract type TransactionHandle end

"""
    transaction(f::Function, conn::Connection) -> result

Execute a function within a database transaction.

The transaction automatically commits if the function completes successfully,
or rolls back if an exception is thrown.

# Arguments

  - `f`: Function to execute within the transaction. Receives transaction handle as argument.
  - `conn`: Database connection

# Returns

The return value of the function `f`

# Example

```julia
# Simple transaction
result = transaction(db) do tx
    execute(tx, "INSERT INTO users (email) VALUES (?)", ["alice@example.com"])
    execute(tx, "INSERT INTO orders (user_id, total) VALUES (?, ?)", [1, 100.0])
    return "success"
end
# result == "success"

# Transaction with query execution
users = transaction(db) do tx
    q = from(:users) |>
        where(col(:users, :active) == literal(true)) |>
        select(NamedTuple, col(:users, :id), col(:users, :email))

    fetch_all(tx, dialect, registry, q)
end
# users is Vector{NamedTuple}

# Transaction rollback on exception
try
    transaction(db) do tx
        execute(tx, "INSERT INTO users (email) VALUES (?)", ["alice@example.com"])
        error("Something went wrong!")
        # Transaction is automatically rolled back
    end
catch e
    println("Transaction rolled back: ", e)
end
```

# Errors

Rethrows any exception that occurs within the function `f` after rolling back
the transaction.
"""
function transaction(f::Function, conn::Connection)
    error("transaction not implemented for $(typeof(conn))")
end

"""
    savepoint(f::Function, tx::TransactionHandle, name::Symbol) -> result

Create a savepoint within a transaction for nested transaction semantics.

Savepoints allow partial rollback: if an exception occurs within the savepoint,
only changes made within that savepoint are rolled back. The outer transaction
can still commit.

# Arguments

  - `f`: Function to execute within the savepoint. Receives transaction handle.
  - `tx`: Transaction handle (from outer `transaction()` call)
  - `name`: Unique name for the savepoint

# Returns

The return value of the function `f`

# Example

```julia
transaction(db) do tx
    # This insert is in the outer transaction
    execute(tx, "INSERT INTO users (email) VALUES (?)", ["alice@example.com"])

    # Savepoint for risky operation
    try
        savepoint(tx, :risky_operation) do sp
            execute(sp, "INSERT INTO orders (user_id, total) VALUES (?, ?)", [1, 100.0])
            # Some risky operation that might fail
            if some_condition
                error("Risky operation failed!")
            end
        end
    catch e
        # Orders insert was rolled back, but users insert will still commit
        println("Savepoint rolled back: ", e)
    end

    # User insert still commits
end

# Multiple savepoints
transaction(db) do tx
    execute(tx, "INSERT INTO users (email) VALUES (?)", ["alice@example.com"])

    savepoint(tx, :sp1) do sp1
        execute(sp1, "INSERT INTO orders (user_id, total) VALUES (?, ?)", [1, 100.0])

        savepoint(sp1, :sp2) do sp2
            execute(sp2, "INSERT INTO order_items (order_id, sku) VALUES (?, ?)", [1, "ABC123"])
        end
    end
end
```

# Errors

Rethrows any exception that occurs within the function `f` after rolling back
to the savepoint.

# Notes

  - Savepoints can be nested
  - Savepoint names must be unique within a transaction
  - SQLite uses SAVEPOINT/RELEASE/ROLLBACK TO commands
"""
function savepoint(f::Function, tx::TransactionHandle, name::Symbol)
    error("savepoint not implemented for $(typeof(tx))")
end
