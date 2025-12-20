# Tutorial: Building a Blog Application

This tutorial walks through building a complete blog application with SQLSketch.jl, demonstrating key features and best practices.

## Prerequisites

```julia
using Pkg
Pkg.add(url="https://github.com/daikichiba9511/SQLSketch.jl")
Pkg.add("LibPQ")  # PostgreSQL driver
Pkg.add("Dates")
Pkg.add("UUIDs")
```

## 1. Database Setup

First, create a PostgreSQL database and connect:

```julia
using SQLSketch
using SQLSketch.Drivers: PostgreSQLDriver
using SQLSketch.Dialects: PostgreSQLDialect
using Dates
using UUIDs

# Connect to PostgreSQL
driver = PostgreSQLDriver("host=localhost dbname=blog_dev user=postgres password=postgres")
dialect = PostgreSQLDialect()
```

## 2. Define Data Models

Define Julia structs that map to our database tables:

```julia
# User model
struct User
    id::UUID
    email::String
    username::String
    created_at::DateTime
end

# Post model
struct Post
    id::UUID
    user_id::UUID
    title::String
    content::String
    published::Bool
    created_at::DateTime
    updated_at::Union{Nothing,DateTime}
end

# Comment model
struct Comment
    id::UUID
    post_id::UUID
    user_id::UUID
    content::String
    created_at::DateTime
end

# Tag model
struct Tag
    id::Int64
    name::String
end
```

## 3. Create Database Schema

Use SQLSketch's DDL operations to create tables:

```julia
# Create users table
create_users = create_table(:users) |>
    add_column(:id, :uuid) |>
    add_column(:email, :text) |>
    add_column(:username, :text) |>
    add_column(:created_at, :timestamp) |>
    primary_key(:id) |>
    not_null(:email) |>
    not_null(:username) |>
    unique_constraint(:email) |>
    unique_constraint(:username)

execute_dml(driver, create_users)

# Create posts table
create_posts = create_table(:posts) |>
    add_column(:id, :uuid) |>
    add_column(:user_id, :uuid) |>
    add_column(:title, :text) |>
    add_column(:content, :text) |>
    add_column(:published, :boolean) |>
    add_column(:created_at, :timestamp) |>
    add_column(:updated_at, :timestamp) |>
    primary_key(:id) |>
    not_null(:user_id) |>
    not_null(:title) |>
    not_null(:published) |>
    foreign_key(:user_id, :users, :id)

execute_dml(driver, create_posts)

# Create comments table
create_comments = create_table(:comments) |>
    add_column(:id, :uuid) |>
    add_column(:post_id, :uuid) |>
    add_column(:user_id, :uuid) |>
    add_column(:content, :text) |>
    add_column(:created_at, :timestamp) |>
    primary_key(:id) |>
    not_null(:post_id) |>
    not_null(:user_id) |>
    not_null(:content) |>
    foreign_key(:post_id, :posts, :id) |>
    foreign_key(:user_id, :users, :id)

execute_dml(driver, create_comments)

# Create tags table
create_tags = create_table(:tags) |>
    add_column(:id, :serial) |>
    add_column(:name, :text) |>
    primary_key(:id) |>
    not_null(:name) |>
    unique_constraint(:name)

execute_dml(driver, create_tags)

# Create posts_tags junction table
create_posts_tags = create_table(:posts_tags) |>
    add_column(:post_id, :uuid) |>
    add_column(:tag_id, :integer) |>
    primary_key(:post_id, :tag_id) |>
    foreign_key(:post_id, :posts, :id) |>
    foreign_key(:tag_id, :tags, :id)

execute_dml(driver, create_posts_tags)

# Create indexes for performance
create_index(:idx_posts_user_id) |> on(:posts, :user_id) |> execute_dml(driver)
create_index(:idx_comments_post_id) |> on(:comments, :post_id) |> execute_dml(driver)
create_index(:idx_posts_created_at) |> on(:posts, :created_at) |> execute_dml(driver)
```

## 4. Insert Data

### Create a User

```julia
function create_user(driver, email::String, username::String)::User
    q = insert_into(:users, [:id, :email, :username, :created_at]) |>
        values([
            literal(uuid4()),
            literal(email),
            literal(username),
            literal(now())
        ]) |>
        returning(
            col(:users, :id),
            col(:users, :email),
            col(:users, :username),
            col(:users, :created_at)
        )

    fetch_one(driver, q, User)
end

# Create a user
alice = create_user(driver, "alice@example.com", "alice")
println("Created user: $(alice.username) ($(alice.id))")
```

### Create a Post

```julia
function create_post(driver, user_id::UUID, title::String, content::String)::Post
    q = insert_into(:posts, [:id, :user_id, :title, :content, :published, :created_at, :updated_at]) |>
        values([
            literal(uuid4()),
            literal(user_id),
            literal(title),
            literal(content),
            literal(false),
            literal(now()),
            literal(nothing)
        ]) |>
        returning(
            col(:posts, :id),
            col(:posts, :user_id),
            col(:posts, :title),
            col(:posts, :content),
            col(:posts, :published),
            col(:posts, :created_at),
            col(:posts, :updated_at)
        )

    fetch_one(driver, q, Post)
end

# Create a post
post = create_post(driver, alice.id, "My First Post", "Hello, world!")
println("Created post: $(post.title)")
```

### Add Comments

```julia
function create_comment(driver, post_id::UUID, user_id::UUID, content::String)::Comment
    q = insert_into(:comments, [:id, :post_id, :user_id, :content, :created_at]) |>
        values([
            literal(uuid4()),
            literal(post_id),
            literal(user_id),
            literal(content),
            literal(now())
        ]) |>
        returning(
            col(:comments, :id),
            col(:comments, :post_id),
            col(:comments, :user_id),
            col(:comments, :content),
            col(:comments, :created_at)
        )

    fetch_one(driver, q, Comment)
end

# Add a comment
comment = create_comment(driver, post.id, alice.id, "First comment!")
```

## 5. Query Data

### Fetch All Published Posts

```julia
q = from(:posts) |>
    where(col(:posts, :published) == literal(true)) |>
    order_by(col(:posts, :created_at); desc=true) |>
    select(Post,
           col(:posts, :id),
           col(:posts, :user_id),
           col(:posts, :title),
           col(:posts, :content),
           col(:posts, :published),
           col(:posts, :created_at),
           col(:posts, :updated_at))

published_posts = fetch_all(driver, q)
```

### Fetch Posts with User Information

```julia
struct PostWithAuthor
    post_id::UUID
    title::String
    content::String
    author_username::String
    created_at::DateTime
end

q = from(:posts) |>
    join(:users, col(:users, :id) == col(:posts, :user_id); kind=:inner) |>
    where(col(:posts, :published) == literal(true)) |>
    order_by(col(:posts, :created_at); desc=true) |>
    select(PostWithAuthor,
           col(:posts, :id),
           col(:posts, :title),
           col(:posts, :content),
           col(:users, :username),
           col(:posts, :created_at))

posts_with_authors = fetch_all(driver, q)

for post in posts_with_authors
    println("$(post.title) by $(post.author_username)")
end
```

### Fetch Post with Comments

```julia
struct PostComment
    comment_id::UUID
    content::String
    author_username::String
    created_at::DateTime
end

function get_post_comments(driver, post_id::UUID)::Vector{PostComment}
    q = from(:comments) |>
        join(:users, col(:users, :id) == col(:comments, :user_id); kind=:inner) |>
        where(col(:comments, :post_id) == literal(post_id)) |>
        order_by(col(:comments, :created_at); desc=false) |>
        select(PostComment,
               col(:comments, :id),
               col(:comments, :content),
               col(:users, :username),
               col(:comments, :created_at))

    fetch_all(driver, q)
end

comments = get_post_comments(driver, post.id)
```

### Parameterized Search

```julia
search_term = p_(:search, String)

q = from(:posts) |>
    where(
        (col(:posts, :title) |> like(literal("%Julia%"))) |
        (col(:posts, :content) |> like(literal("%database%")))
    ) |>
    order_by(col(:posts, :created_at); desc=true) |>
    select(Post,
           col(:posts, :id),
           col(:posts, :user_id),
           col(:posts, :title),
           col(:posts, :content),
           col(:posts, :published),
           col(:posts, :created_at),
           col(:posts, :updated_at))

results = fetch_all(driver, q)
```

### Aggregation: Count Posts by User

```julia
struct UserPostCount
    username::String
    post_count::Int64
end

q = from(:posts) |>
    join(:users, col(:users, :id) == col(:posts, :user_id); kind=:inner) |>
    group_by(col(:users, :username)) |>
    select(UserPostCount,
           col(:users, :username),
           count_star())

counts = fetch_all(driver, q)

for row in counts
    println("$(row.username): $(row.post_count) posts")
end
```

## 6. Update Data

### Publish a Post

```julia
function publish_post(driver, post_id::UUID)
    q = update(:posts) |>
        set_(:published, literal(true)) |>
        set_(:updated_at, literal(now())) |>
        where(col(:posts, :id) == literal(post_id))

    execute_dml(driver, q)
end

publish_post(driver, post.id)
```

### Edit Post Content

```julia
function edit_post(driver, post_id::UUID, new_title::String, new_content::String)
    q = update(:posts) |>
        set_(:title, literal(new_title)) |>
        set_(:content, literal(new_content)) |>
        set_(:updated_at, literal(now())) |>
        where(col(:posts, :id) == literal(post_id))

    execute_dml(driver, q)
end

edit_post(driver, post.id, "Updated Title", "Updated content!")
```

## 7. Transactions

Use transactions to ensure data consistency:

```julia
function create_post_with_tags(driver, user_id::UUID, title::String, content::String, tag_names::Vector{String})
    transaction(driver) do tx
        # Create post
        post_q = insert_into(:posts, [:id, :user_id, :title, :content, :published, :created_at, :updated_at]) |>
            values([
                literal(uuid4()),
                literal(user_id),
                literal(title),
                literal(content),
                literal(false),
                literal(now()),
                literal(nothing)
            ]) |>
            returning(col(:posts, :id))

        post_id = fetch_one(tx, post_q)

        # Create or find tags and link to post
        for tag_name in tag_names
            # Try to insert tag (using ON CONFLICT DO NOTHING for PostgreSQL)
            tag_q = insert_into(:tags, [:name]) |>
                values([literal(tag_name)]) |>
                on_conflict([:name]) |>
                do_nothing() |>
                returning(col(:tags, :id))

            # Get tag id
            tag_id_q = from(:tags) |>
                where(col(:tags, :name) == literal(tag_name)) |>
                select(NamedTuple, col(:tags, :id))

            tag_id = fetch_one(tx, tag_id_q)

            # Link post and tag
            link_q = insert_into(:posts_tags, [:post_id, :tag_id]) |>
                values([literal(post_id), literal(tag_id)])

            execute_dml(tx, link_q)
        end

        post_id
    end
end

# Create post with tags atomically
post_id = create_post_with_tags(driver, alice.id, "Julia Tutorial", "Learn Julia!", ["julia", "tutorial", "programming"])
```

## 8. Window Functions

Rank posts by number of comments:

```julia
struct PostRank
    title::String
    comment_count::Int64
    rank::Int64
end

q = from(:posts) |>
    join(:comments, col(:comments, :post_id) == col(:posts, :id); kind=:left) |>
    group_by(col(:posts, :id), col(:posts, :title)) |>
    select(NamedTuple,
           col(:posts, :title),
           count_star(),
           row_number() |> over(order_by(count_star(); desc=true)))

rankings = fetch_all(driver, q)
```

## 9. Advanced: Subqueries

Find users who have commented on their own posts:

```julia
# Subquery: posts where user commented
commented_own_posts = from(:comments) |>
    join(:posts, col(:posts, :id) == col(:comments, :post_id); kind=:inner) |>
    where(col(:comments, :user_id) == col(:posts, :user_id)) |>
    select(NamedTuple, col(:posts, :user_id))

# Main query: users who commented on own posts
q = from(:users) |>
    where(col(:users, :id) |> in_(subquery(commented_own_posts))) |>
    select(User,
           col(:users, :id),
           col(:users, :email),
           col(:users, :username),
           col(:users, :created_at))

users = fetch_all(driver, q)
```

## 10. Cleanup

```julia
# Drop all tables (in correct order due to foreign keys)
execute_dml(driver, drop_table(:posts_tags))
execute_dml(driver, drop_table(:comments))
execute_dml(driver, drop_table(:posts))
execute_dml(driver, drop_table(:tags))
execute_dml(driver, drop_table(:users))
```

## Summary

This tutorial covered:

- ✅ Database schema creation with DDL
- ✅ Type-safe data models
- ✅ INSERT operations with RETURNING
- ✅ SELECT queries with joins and filtering
- ✅ UPDATE and DELETE operations
- ✅ Parameterized queries
- ✅ Aggregation and grouping
- ✅ Transactions for data consistency
- ✅ Window functions for analytics
- ✅ Subqueries for complex filtering

## Next Steps

- Explore [API Reference](api.md) for complete function documentation
- Read [Design Philosophy](design.md) to understand SQLSketch's architecture
- Check out advanced PostgreSQL features (JSONB, Arrays, CTEs)
- Build your own application with SQLSketch!
