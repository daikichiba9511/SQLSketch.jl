"""
# Window Functions Examples

This file demonstrates the use of window functions in SQLSketch.jl.

Window functions perform calculations across a set of table rows that are
related to the current row, without collapsing the result set like GROUP BY.
"""

using SQLSketch
using SQLSketch.Drivers

# Setup: Create an in-memory SQLite database
db = SQLiteDriver()
conn = connect(db, ":memory:")
dialect = SQLiteDialect()
registry = CodecRegistry()

# Create sample tables
execute(conn, """
    CREATE TABLE employees (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        department TEXT NOT NULL,
        salary INTEGER NOT NULL,
        hire_date DATE NOT NULL
    )
""")

execute(conn, """
    CREATE TABLE sales (
        id INTEGER PRIMARY KEY,
        date DATE NOT NULL,
        amount INTEGER NOT NULL,
        region TEXT NOT NULL
    )
""")

# Insert sample data
execute(conn, """
    INSERT INTO employees (id, name, department, salary, hire_date) VALUES
    (1, 'Alice', 'Engineering', 120000, '2020-01-15'),
    (2, 'Bob', 'Engineering', 110000, '2020-03-20'),
    (3, 'Carol', 'Engineering', 105000, '2021-06-10'),
    (4, 'David', 'Sales', 95000, '2020-02-01'),
    (5, 'Eve', 'Sales', 90000, '2020-08-15'),
    (6, 'Frank', 'Marketing', 85000, '2019-11-20'),
    (7, 'Grace', 'Marketing', 80000, '2021-01-10')
""")

execute(conn, """
    INSERT INTO sales (id, date, amount, region) VALUES
    (1, '2025-01-01', 1000, 'East'),
    (2, '2025-01-02', 1500, 'East'),
    (3, '2025-01-03', 1200, 'East'),
    (4, '2025-01-04', 1800, 'East'),
    (5, '2025-01-05', 1600, 'East'),
    (6, '2025-01-01', 900, 'West'),
    (7, '2025-01-02', 1100, 'West'),
    (8, '2025-01-03', 1300, 'West')
""")

println("="^80)
println("Window Functions Examples")
println("="^80)

# Example 1: ROW_NUMBER - Assign unique sequential numbers within partitions
println("\n1. Employee ranking within each department by salary (ROW_NUMBER)")
println("-"^80)

q1 = from(:employees) |>
     select(NamedTuple,
            col(:employees, :name),
            col(:employees, :department),
            col(:employees, :salary),
            row_number(over(; partition_by = [col(:employees, :department)],
                            order_by = [(col(:employees, :salary), true)])))

sql1, _ = compile(dialect, q1)
println("SQL: ", sql1)
println("\nResults:")
for row in fetch_all(conn, dialect, registry, q1)
    println("  $row")
end

# Example 2: RANK - Rankings with gaps for ties
println("\n2. Employee salary ranking (RANK)")
println("-"^80)

q2 = from(:employees) |>
     select(NamedTuple,
            col(:employees, :name),
            col(:employees, :salary),
            rank(over(; order_by = [(col(:employees, :salary), true)])))

sql2, _ = compile(dialect, q2)
println("SQL: ", sql2)
println("\nResults:")
for row in fetch_all(conn, dialect, registry, q2)
    println("  $row")
end

# Example 3: LAG - Access previous row's value
println("\n3. Day-over-day sales comparison (LAG)")
println("-"^80)

q3 = from(:sales) |>
     where(col(:sales, :region) == literal("East")) |>
     select(NamedTuple,
            col(:sales, :date),
            col(:sales, :amount),
            lag(col(:sales, :amount), over(; order_by = [(col(:sales, :date), false)]))) |>
     order_by(col(:sales, :date))

sql3, _ = compile(dialect, q3)
println("SQL: ", sql3)
println("\nResults:")
for row in fetch_all(conn, dialect, registry, q3)
    println("  $row")
end

# Example 4: Running total with SUM and frame specification
println("\n4. Running total of sales (SUM with ROWS frame)")
println("-"^80)

q4 = from(:sales) |>
     where(col(:sales, :region) == literal("East")) |>
     select(NamedTuple,
            col(:sales, :date),
            col(:sales, :amount),
            win_sum(col(:sales, :amount),
                    over(; order_by = [(col(:sales, :date), false)],
                         frame = window_frame(:ROWS, :UNBOUNDED_PRECEDING, :CURRENT_ROW)))) |>
     order_by(col(:sales, :date))

sql4, _ = compile(dialect, q4)
println("SQL: ", sql4)
println("\nResults:")
for row in fetch_all(conn, dialect, registry, q4)
    println("  $row")
end

# Example 5: Moving average with 3-day window
println("\n5. 3-day moving average of sales (AVG with ROWS frame)")
println("-"^80)

q5 = from(:sales) |>
     where(col(:sales, :region) == literal("East")) |>
     select(NamedTuple,
            col(:sales, :date),
            col(:sales, :amount),
            win_avg(col(:sales, :amount),
                    over(; order_by = [(col(:sales, :date), false)],
                         # 1 PRECEDING + CURRENT ROW + 1 FOLLOWING = 3 rows
                         frame = window_frame(:ROWS, -1, 1)))) |>
     order_by(col(:sales, :date))

sql5, _ = compile(dialect, q5)
println("SQL: ", sql5)
println("\nResults:")
for row in fetch_all(conn, dialect, registry, q5)
    println("  $row")
end

# Example 6: NTILE - Divide into quartiles
println("\n6. Divide employees into salary quartiles (NTILE)")
println("-"^80)

q6 = from(:employees) |>
     select(NamedTuple,
            col(:employees, :name),
            col(:employees, :salary),
            ntile(4, over(; order_by = [(col(:employees, :salary), true)])))

sql6, _ = compile(dialect, q6)
println("SQL: ", sql6)
println("\nResults:")
for row in fetch_all(conn, dialect, registry, q6)
    println("  $row")
end

# Example 7: FIRST_VALUE and LAST_VALUE
println("\n7. Compare each salary to department min/max (FIRST_VALUE/LAST_VALUE)")
println("-"^80)

q7 = from(:employees) |>
     select(NamedTuple,
            col(:employees, :name),
            col(:employees, :department),
            col(:employees, :salary),
            first_value(col(:employees, :salary),
                        over(; partition_by = [col(:employees, :department)],
                             order_by = [(col(:employees, :salary), false)])),
            last_value(col(:employees, :salary),
                       over(; partition_by = [col(:employees, :department)],
                            order_by = [(col(:employees, :salary), false)],
                            # Need to specify frame to include all rows
                            frame = window_frame(:ROWS, :UNBOUNDED_PRECEDING,
                                                 :UNBOUNDED_FOLLOWING))))

sql7, _ = compile(dialect, q7)
println("SQL: ", sql7)
println("\nResults:")
for row in fetch_all(conn, dialect, registry, q7)
    println("  $row")
end

println("\n" * ("="^80))
println("All examples completed successfully!")
println("="^80)
