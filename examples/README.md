# SQLSketch.jl Examples

This directory contains example scripts demonstrating SQLSketch.jl functionality.

## Files

### Database Creation

**`create_test_db.jl`** - Create a persistent SQLite database for testing
- Creates `test.db` with sample users and posts tables
- Inserts test data (5 users, 5 posts)
- Demonstrates foreign key relationships

```bash
julia --project=. examples/create_test_db.jl
```

### Testing

**`test_sqlite.sh`** - Comprehensive SQLite database tests
- Runs 20 SQL queries to verify database functionality
- Tests SELECT, JOIN, WHERE, GROUP BY, and more
- Requires sqlite3 command-line tool

```bash
./examples/test_sqlite.sh
```

See script header for detailed usage documentation.

**`manual_integration_test.jl`** - Manual integration test for Phase 1-5
- Demonstrates end-to-end flow from Query AST to results
- Tests Query → Compile → Execute → Decode pipeline
- Uses in-memory database (no persistent file)

```bash
julia --project=. examples/manual_integration_test.jl
```

## Quick Start

```bash
# 1. Create test database
julia --project=. examples/create_test_db.jl

# 2. Run SQLite tests
./examples/test_sqlite.sh

# 3. Inspect database manually
sqlite3 examples/test.db
sqlite> .tables
sqlite> .schema users
sqlite> SELECT * FROM users;
sqlite> .quit
```

## Database Schema

### users table
```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    age INTEGER,
    is_active INTEGER DEFAULT 1,
    created_at TEXT NOT NULL
);
```

### posts table
```sql
CREATE TABLE posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    content TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
);
```

## Notes

- Database files (`*.db`) are excluded from git via `.gitignore`
- `test.db` must be recreated after cloning the repository
- All examples use SQLite for simplicity and portability
