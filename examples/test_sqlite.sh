#!/bin/bash

################################################################################
# SQLite Database Test Script
################################################################################
#
# DESCRIPTION:
#   This script tests the SQLite database created by SQLSketch.jl using the
#   sqlite3 command-line tool. It runs 20 different SQL queries to verify
#   database functionality including SELECT, JOIN, WHERE, GROUP BY, and more.
#
# USAGE:
#   ./examples/test_sqlite.sh
#
# PREREQUISITES:
#   1. Create the test database first:
#      julia --project=. examples/create_test_db.jl
#
#   2. Ensure sqlite3 is installed:
#      - macOS: sqlite3 is pre-installed
#      - Ubuntu/Debian: sudo apt-get install sqlite3
#      - Fedora/RHEL: sudo dnf install sqlite
#
# OUTPUT:
#   The script will run 20 SQL tests and display:
#   - Test description
#   - SQL query being executed
#   - Query results in column format
#   - Summary and database integrity check
#
# WHAT IS TESTED:
#   - Basic queries (SELECT, COUNT)
#   - Filtering (WHERE, LIKE)
#   - Joins (INNER JOIN, LEFT JOIN)
#   - Aggregation (GROUP BY, COUNT)
#   - Sorting (ORDER BY)
#   - Pagination (LIMIT, OFFSET)
#   - Subqueries
#   - String and arithmetic operations
#
# EXIT CODES:
#   0 - All tests passed
#   1 - Database file not found or test failed
#
# EXAMPLES:
#   # Run all tests
#   ./examples/test_sqlite.sh
#
#   # Inspect database manually after tests
#   sqlite3 examples/test.db
#   sqlite> .tables
#   sqlite> SELECT * FROM users;
#
################################################################################

set -e  # Exit on error

DB_PATH="$(dirname "$0")/test.db"
SQLITE="sqlite3 -cmd '.mode column' -cmd '.headers on'"

echo "================================================================"
echo "SQLite Database Test Script"
echo "================================================================"
echo "Database: $DB_PATH"
echo ""

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
    echo "❌ Error: Database file not found!"
    echo "Please run: julia --project=. examples/create_test_db.jl"
    exit 1
fi

echo "✓ Database file exists"
echo ""

# Function to run SQL query with nice formatting
run_query() {
    local description="$1"
    local query="$2"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "TEST: $description"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "SQL:"
    echo "$query" | sed 's/^/  /'
    echo ""
    echo "Result:"
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB_PATH" "$query"
    echo ""
}

# Test 1: List all tables
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST: List all tables"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sqlite3 "$DB_PATH" ".tables"
echo ""

# Test 2: Show table schemas
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST: Show table schemas"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Users table:"
sqlite3 "$DB_PATH" ".schema users"
echo ""
echo "Posts table:"
sqlite3 "$DB_PATH" ".schema posts"
echo ""

# Test 3: Count rows
run_query "Count all users" \
    "SELECT COUNT(*) as total_users FROM users;"

run_query "Count all posts" \
    "SELECT COUNT(*) as total_posts FROM posts;"

# Test 4: Select all users
run_query "Select all users" \
    "SELECT * FROM users ORDER BY id;"

# Test 5: Select all posts
run_query "Select all posts" \
    "SELECT * FROM posts ORDER BY id;"

# Test 6: Filter users by age
run_query "Filter users where age > 26" \
    "SELECT id, name, email, age FROM users WHERE age > 26 ORDER BY age;"

# Test 7: Filter active users
run_query "Select only active users" \
    "SELECT id, name, email, is_active FROM users WHERE is_active = 1;"

# Test 8: Simple JOIN
run_query "JOIN users and posts" \
    "SELECT u.name, p.title, p.created_at
     FROM users u
     JOIN posts p ON u.id = p.user_id
     ORDER BY p.created_at;"

# Test 9: JOIN with filter
run_query "JOIN with WHERE clause (active users only)" \
    "SELECT u.name, u.is_active, p.title
     FROM users u
     JOIN posts p ON u.id = p.user_id
     WHERE u.is_active = 1
     ORDER BY u.name;"

# Test 10: Aggregation - count posts per user
run_query "Count posts per user" \
    "SELECT u.name, COUNT(p.id) as post_count
     FROM users u
     LEFT JOIN posts p ON u.id = p.user_id
     GROUP BY u.id, u.name
     ORDER BY post_count DESC, u.name;"

# Test 11: Subquery
run_query "Users with more than 1 post" \
    "SELECT u.name, u.email,
        (SELECT COUNT(*) FROM posts p WHERE p.user_id = u.id) as post_count
     FROM users u
     WHERE (SELECT COUNT(*) FROM posts p WHERE p.user_id = u.id) > 1;"

# Test 12: Date filtering
run_query "Posts created after 2025-01-07" \
    "SELECT title, created_at FROM posts WHERE created_at > '2025-01-07' ORDER BY created_at;"

# Test 13: LIKE pattern matching
run_query "Users with 'a' in their name" \
    "SELECT name, email FROM users WHERE name LIKE '%a%' ORDER BY name;"

# Test 14: DISTINCT
run_query "Distinct ages" \
    "SELECT DISTINCT age FROM users ORDER BY age;"

# Test 15: LIMIT and OFFSET
run_query "First 3 users" \
    "SELECT id, name, email FROM users ORDER BY id LIMIT 3;"

run_query "Users with OFFSET (skip first 2)" \
    "SELECT id, name, email FROM users ORDER BY id LIMIT 3 OFFSET 2;"

# Test 16: ORDER BY DESC
run_query "Users ordered by age (descending)" \
    "SELECT name, age FROM users ORDER BY age DESC;"

# Test 17: Multiple columns ORDER BY
run_query "Order by is_active, then age" \
    "SELECT name, is_active, age FROM users ORDER BY is_active DESC, age ASC;"

# Test 18: NULL handling (create a test case)
run_query "Check for NULL values in age" \
    "SELECT name, age,
        CASE
            WHEN age IS NULL THEN 'No age'
            ELSE CAST(age AS TEXT)
        END as age_display
     FROM users;"

# Test 19: Arithmetic operations
run_query "Calculate age in months" \
    "SELECT name, age, (age * 12) as age_in_months FROM users WHERE age IS NOT NULL;"

# Test 20: String operations
run_query "Uppercase names and email domains" \
    "SELECT
        UPPER(name) as name_upper,
        email,
        SUBSTR(email, INSTR(email, '@') + 1) as domain
     FROM users;"

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All 20 SQL tests completed successfully!"
echo ""
echo "Database integrity check:"
sqlite3 "$DB_PATH" "PRAGMA integrity_check;"
echo ""
echo "Database size:"
ls -lh "$DB_PATH" | awk '{print "  " $5}'
echo ""
echo "================================================================"
echo "You can also run custom queries with:"
echo "  sqlite3 examples/test.db"
echo "================================================================"
