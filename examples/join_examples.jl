"""
# JOIN Examples

This file demonstrates all types of JOIN operations in SQLSketch.jl:
- INNER JOIN
- LEFT JOIN (LEFT OUTER JOIN)
- RIGHT JOIN (RIGHT OUTER JOIN)
- FULL JOIN (FULL OUTER JOIN)
- Self-joins
- Multiple joins
"""

using SQLSketch          # Core query building functions
using SQLSketch.Drivers  # Database drivers

println("="^80)
println("JOIN Examples")
println("="^80)

# Setup: Create an in-memory SQLite database
driver = SQLiteDriver()
db = connect(driver, ":memory:")
dialect = SQLiteDialect()
registry = CodecRegistry()

# Create sample tables
println("\n[1] Creating sample tables...")

# Users table
users_table = create_table(:users) |>
              add_column(:id, :integer; primary_key = true) |>
              add_column(:name, :text; nullable = false) |>
              add_column(:email, :text; nullable = false) |>
              add_column(:department_id, :integer)

execute(db, dialect, users_table)

# Departments table
departments_table = create_table(:departments) |>
                    add_column(:id, :integer; primary_key = true) |>
                    add_column(:name, :text; nullable = false) |>
                    add_column(:budget, :real)

execute(db, dialect, departments_table)

# Projects table
projects_table = create_table(:projects) |>
                 add_column(:id, :integer; primary_key = true) |>
                 add_column(:name, :text; nullable = false) |>
                 add_column(:user_id, :integer) |>
                 add_column(:status, :text)

execute(db, dialect, projects_table)

println("✓ Tables created")

# Insert sample data
println("\n[2] Inserting sample data...")

# Insert departments
departments_data = [(1, "Engineering", 500000.0),
                    (2, "Sales", 300000.0),
                    (3, "Marketing", 200000.0),
                    (4, "HR", 100000.0)]

for (id, name, budget) in departments_data
    execute(db, dialect,
            insert_into(:departments, [:id, :name, :budget]) |>
            insert_values([[literal(id), literal(name), literal(budget)]]))
end

# Insert users (note: some users have no department, one department has no users)
users_data = [(1, "Alice", "alice@example.com", 1),
              (2, "Bob", "bob@example.com", 1),
              (3, "Charlie", "charlie@example.com", 2),
              (4, "Diana", "diana@example.com", 2),
              (5, "Eve", "eve@example.com", 3),
              (6, "Frank", "frank@example.com", missing)]

for (id, name, email, dept_id) in users_data
    if dept_id === missing
        execute(db, dialect,
                insert_into(:users, [:id, :name, :email, :department_id]) |>
                insert_values([[literal(id), literal(name), literal(email),
                                literal(nothing)]]))
    else
        execute(db, dialect,
                insert_into(:users, [:id, :name, :email, :department_id]) |>
                insert_values([[literal(id), literal(name), literal(email),
                                literal(dept_id)]]))
    end
end

# Insert projects
projects_data = [(1, "Project Alpha", 1, "active"),
                 (2, "Project Beta", 1, "completed"),
                 (3, "Project Gamma", 2, "active"),
                 (4, "Project Delta", 3, "planning"),
                 (5, "Project Epsilon", 5, "active"),
                 (6, "Project Zeta", missing, "planning")]

for (id, name, user_id, status) in projects_data
    if user_id === missing
        execute(db, dialect,
                insert_into(:projects, [:id, :name, :user_id, :status]) |>
                insert_values([[literal(id), literal(name), literal(nothing),
                                literal(status)]]))
    else
        execute(db, dialect,
                insert_into(:projects, [:id, :name, :user_id, :status]) |>
                insert_values([[literal(id), literal(name), literal(user_id),
                                literal(status)]]))
    end
end

println("✓ Data inserted")
println("  - 4 departments (HR has no users)")
println("  - 6 users (Frank has no department)")
println("  - 6 projects (Project Zeta has no assigned user)")

# Example 1: INNER JOIN
println("\n[3] Example 1: INNER JOIN")
println("-"^80)
println("Shows only users who have a department")

q1 = from(:users) |>
     inner_join(:departments, col(:users, :department_id) == col(:departments, :id)) |>
     select(NamedTuple,
            col(:users, :name),
            col(:users, :email),
            col(:departments, :name)) |>
     order_by(col(:users, :name))

sql1, _ = compile(dialect, q1)
println("SQL: ", sql1)
println("\nResults:")
for row in fetch_all(db, dialect, registry, q1)
    println("  User: $(row.name), Email: $(row.email), Department: $(row[3])")
end
println("  → Frank is excluded (no department)")

# Example 2: LEFT JOIN
println("\n[4] Example 2: LEFT JOIN")
println("-"^80)
println("Shows ALL users, including those without a department")

q2 = from(:users) |>
     left_join(:departments, col(:users, :department_id) == col(:departments, :id)) |>
     select(NamedTuple,
            col(:users, :name),
            col(:users, :email),
            col(:departments, :name)) |>
     order_by(col(:users, :name))

sql2, _ = compile(dialect, q2)
println("SQL: ", sql2)
println("\nResults:")
for row in fetch_all(db, dialect, registry, q2)
    dept_name = ismissing(row[3]) ? "NULL" : row[3]
    println("  User: $(row.name), Email: $(row.email), Department: $dept_name")
end
println("  → Frank is included with NULL department")

# Example 3: RIGHT JOIN
println("\n[5] Example 3: RIGHT JOIN")
println("-"^80)
println("Shows ALL departments, including those without users")

q3 = from(:users) |>
     right_join(:departments, col(:users, :department_id) == col(:departments, :id)) |>
     select(NamedTuple,
            col(:departments, :name),
            col(:departments, :budget),
            col(:users, :name)) |>
     order_by(col(:departments, :name))

sql3, _ = compile(dialect, q3)
println("SQL: ", sql3)
println("\nResults:")
result3 = fetch_all(db, dialect, registry, q3)
if isempty(result3)
    println("  Note: SQLite does not support RIGHT JOIN")
    println("  You can rewrite as LEFT JOIN with reversed tables:")

    q3_rewrite = from(:departments) |>
                 left_join(:users, col(:users, :department_id) == col(:departments, :id)) |>
                 select(NamedTuple,
                        col(:departments, :name),
                        col(:departments, :budget),
                        col(:users, :name)) |>
                 order_by(col(:departments, :name))

    sql3_rewrite, _ = compile(dialect, q3_rewrite)
    println("  Rewritten SQL: ", sql3_rewrite)
    println("\n  Results (using LEFT JOIN):")
    for row in fetch_all(db, dialect, registry, q3_rewrite)
        user_name = ismissing(row[3]) ? "NULL" : row[3]
        println("    Department: $(row.name), Budget: $(row.budget), User: $user_name")
    end
    println("  → HR department is included with NULL user")
else
    for row in result3
        user_name = ismissing(row[3]) ? "NULL" : row[3]
        println("  Department: $(row.name), Budget: $(row.budget), User: $user_name")
    end
end

# Example 4: Multiple JOINs
println("\n[6] Example 4: Multiple JOINs")
println("-"^80)
println("Join users, departments, and projects together")

q4 = from(:users) |>
     inner_join(:departments, col(:users, :department_id) == col(:departments, :id)) |>
     inner_join(:projects, col(:projects, :user_id) == col(:users, :id)) |>
     where(col(:projects, :status) == literal("active")) |>
     select(NamedTuple,
            col(:users, :name),
            col(:departments, :name),
            col(:projects, :name),
            col(:projects, :status)) |>
     order_by(col(:users, :name))

sql4, _ = compile(dialect, q4)
println("SQL: ", sql4)
println("\nResults:")
for row in fetch_all(db, dialect, registry, q4)
    println("  User: $(row[1]), Department: $(row[2]), Project: $(row[3]), Status: $(row.status)")
end

# Example 5: Self-join
println("\n[7] Example 5: Self-join")
println("-"^80)
println("Find users in the same department (excluding self)")

# First, let's create an alias pattern by using different table references
q5 = from(:users) |>
     inner_join(:users, col(:users, :department_id) == col(:users, :department_id)) |>
     where(col(:users, :id) < col(:users, :id)) |>
     select(NamedTuple,
            col(:users, :name),
            col(:users, :name),
            col(:users, :department_id))

# Note: This will generate incorrect SQL due to ambiguous table references
# For self-joins, you would typically need table aliases which requires
# raw SQL or extending the query builder
println("Note: Self-joins require table aliases, which is not yet fully supported.")
println("You can use raw SQL for complex self-joins:")
println("""
  SELECT u1.name AS user1, u2.name AS user2, u1.department_id
  FROM users u1
  INNER JOIN users u2 ON u1.department_id = u2.department_id
  WHERE u1.id < u2.id
  ORDER BY u1.department_id, u1.name
""")

# Example 6: JOIN with WHERE conditions on both tables
println("\n[8] Example 6: JOIN with filtering on both tables")
println("-"^80)

q6 = from(:users) |>
     inner_join(:departments, col(:users, :department_id) == col(:departments, :id)) |>
     where((col(:departments, :budget) > literal(200000.0)) &
           like(col(:users, :name), literal("A%"))) |>
     select(NamedTuple,
            col(:users, :name),
            col(:departments, :name),
            col(:departments, :budget))

sql6, _ = compile(dialect, q6)
println("SQL: ", sql6)
println("\nResults (departments with budget > 200k AND users starting with 'A'):")
for row in fetch_all(db, dialect, registry, q6)
    println("  User: $(row[1]), Department: $(row[2]), Budget: \$$(row.budget)")
end

# Example 7: LEFT JOIN with filtering
println("\n[9] Example 7: LEFT JOIN with filtering")
println("-"^80)
println("Find users and their active projects (including users with no active projects)")

q7 = from(:users) |>
     left_join(:projects,
               col(:projects, :user_id) == col(:users, :id)) |>
     where((col(:projects, :status) == literal("active")) | col(:projects, :status) |>
           is_null) |>
     select(NamedTuple,
            col(:users, :name),
            col(:projects, :name),
            col(:projects, :status)) |>
     order_by(col(:users, :name))

sql7, _ = compile(dialect, q7)
println("SQL: ", sql7)
println("\nResults:")
for row in fetch_all(db, dialect, registry, q7)
    project_name = ismissing(row[2]) ? "No active project" : row[2]
    status = ismissing(row.status) ? "" : " ($(row.status))"
    println("  User: $(row[1]), Project: $project_name$status")
end

# Cleanup
close(db)

println("\n" * "="^80)
println("✅ All JOIN examples completed successfully!")
println("="^80)

println("\nKey takeaways:")
println("  - INNER JOIN: Only matching rows from both tables")
println("  - LEFT JOIN: All rows from left table, matching from right (NULL if no match)")
println("  - RIGHT JOIN: All rows from right table, matching from left (not supported in SQLite)")
println("  - Multiple JOINs: Chain multiple |> join() operations")
println("  - Combine with WHERE: Filter before or after joining")
println("  - Self-joins: Require table aliases (use raw SQL or future enhancements)")
