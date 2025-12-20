**[English README is available here / 英語版 README](README.md)**

---

⚠️ **メンテナンスに関する注意**

**これはトイプロジェクトであり、積極的にメンテナンスされていません。**

このパッケージは、Julia で型付きSQLクエリビルダーの設計を探求するための教育的/実験的なプロジェクトとして作成されました。
コードは機能しますが、本番環境での使用は推奨しません。
Issue や Pull Request には対応しない可能性があります。

---

> ⚠️ **ステータス**
>
> SQLSketch.jl は現在、[@daikichiba9511](https://github.com/daikichiba9511)が開発している**サンプル/実験的なパッケージ**です。
>
> このリポジトリの主な目的は、以下に焦点を当てた *Julia ネイティブな SQL クエリビルディングのアプローチ*を探求し、文書化することです：
> - 型安全なクエリ構成
> - 検査可能な SQL 生成
> - 明確な抽象化の境界
>
> 安定版がリリースされるまで、API は予告なく変更される可能性があります。

# SQLSketch.jl

**Julia のための実験的な型付き SQL クエリビルダー。**

SQLSketch.jl は、強い型付けと最小限の隠れた魔法で SQL クエリを構築するための、
軽量で組み合わせ可能な方法を提供します。

コアアイデアはシンプルです：

> **SQL は常に可視化・検査可能であるべき。
> クエリ API は SQL の論理的評価順序に従うべき。
> 型は邪魔にならずに正しさを導くべき。**

---

## 設計目標

- SQL は常に可視化・検査可能
- クエリ API は SQL の論理的評価順序に従う
- 出力 SQL は SQL の構文順序に従う
- クエリ境界での強い型付け
- 最小限の隠れた魔法
- コアプリミティブと便利層の明確な分離
- **PostgreSQL ファーストの開発**、SQLite / MySQL との互換性

---

## アーキテクチャ

SQLSketch は2層システムとして設計されています：

```
┌─────────────────────────────────┐
│      Extras Layer (将来)          │  ← オプションの便利機能
│  Repository, CRUD, Relations    │
└─────────────────────────────────┘
               ↓
┌─────────────────────────────────┐
│         Core Layer              │  ← 必須のプリミティブ
│  Query → Compile → Execute      │
│  Expr, Dialect, Driver, Codec   │
└─────────────────────────────────┘
```

### Core Layer
- `Expr` – 式 AST（カラム参照、リテラル、演算子）
- `Query` – クエリ AST（FROM, WHERE, SELECT, JOIN など）
- `Dialect` – SQL 生成（SQLite, PostgreSQL, MySQL）
- `Driver` – 接続と実行
- `CodecRegistry` – 型変換

### Extras Layer（将来）
- Repository パターン
- CRUD ヘルパー
- リレーションのプリロード
- スキーママクロ

---

## 現在の実装状況

**完了フェーズ:** 11/12 | **総テスト数:** 1712 passing ✅

- ✅ **Phase 1: Expression AST** (268 tests)
  - カラム参照、リテラル、パラメータ
  - 自動ラップ付きの二項/単項演算子
  - 関数呼び出し
  - 型安全な合成
  - **Placeholder 構文（`p_`）** - カラム参照の糖衣構文
  - **LIKE/ILIKE 演算子** - パターンマッチング
  - **BETWEEN 演算子** - 範囲クエリ
  - **IN 演算子** - メンバーシップテスト
  - **CAST 式** - 型変換
  - **サブクエリ式** - ネストされたクエリ（EXISTS、IN サブクエリ）
  - **CASE 式** - 条件分岐ロジック

- ✅ **Phase 2: Query AST** (232 tests)
  - FROM, WHERE, SELECT, JOIN, ORDER BY
  - LIMIT, OFFSET, DISTINCT, GROUP BY, HAVING
  - **INSERT, UPDATE, DELETE**（DML 操作）
  - `|>` によるパイプライン合成
  - Shape-preserving と shape-changing セマンティクス
  - 型安全なクエリ変換
  - **カリー化 API** - 自然なパイプライン合成

- ✅ **Phase 3: Dialect Abstraction** (331 tests)
  - Dialect インターフェース（compile, quote_identifier, placeholder, supports）
  - 機能検出のための Capability システム
  - SQLite dialect 実装
  - クエリ AST からの完全な SQL 生成
  - **すべての式型**（CAST、Subquery、CASE、BETWEEN、IN、LIKE）
  - 式とクエリのコンパイル
  - **DML コンパイル（INSERT、UPDATE、DELETE）**
  - **Placeholder 解決**（`p_` → `col(table, column)`）

- ✅ **Phase 4: Driver Abstraction** (41 tests)
  - Driver インターフェース（connect, execute, close）
  - SQLiteDriver 実装
  - 接続管理（インメモリとファイルベース）
  - `?` プレースホルダーによるパラメータバインディング
  - SQLite の生結果を返すクエリ実行

- ✅ **Phase 5: CodecRegistry** (115 tests)
  - Julia と SQL 間の型安全なエンコード/デコード
  - 組み込みコーデック（Int, Float64, String, Bool, Date, DateTime, UUID）
  - NULL/Missing ハンドリング
  - NamedTuple と構造体への行マッピング

- ✅ **Phase 6: End-to-End Integration** (95 tests)
  - クエリ実行 API（`fetch_all`, `fetch_one`, `fetch_maybe`）
  - **DML 実行 API（`execute`）**
  - 型安全なパラメータバインディング
  - 完全なパイプライン: Query AST → Dialect → Driver → CodecRegistry
  - 可観測性 API（`sql`, `explain`）
  - 包括的な統合テスト
  - **完全な CRUD 操作**（SELECT、INSERT、UPDATE、DELETE）

- ✅ **Phase 7: Transaction Management** (26 tests)
  - **トランザクション API** (`transaction()`) - 自動コミット/ロールバック
  - **セーブポイント API** (`savepoint()`) - ネストされたトランザクション
  - トランザクション内でのクエリ実行サポート
  - ドライバー層での実装（SQLiteDriver）
  - 例外時の自動ロールバック
  - トランザクションハンドルを使った実行

- ✅ **Phase 8: Migration Runner** (79 tests)
  - **マイグレーション検出と適用** (`discover_migrations`, `apply_migrations`)
  - **タイムスタンプベースのバージョニング** (YYYYMMDDHHMMSS 形式)
  - **SHA256 チェックサム検証** - 変更されたマイグレーションを検出
  - **自動スキーマ追跡** (`schema_migrations` テーブル)
  - **トランザクション内での実行** - 失敗時の自動ロールバック
  - **マイグレーションステータスと検証** (`migration_status`, `validate_migration_checksums`)
  - **マイグレーション生成** (`generate_migration`) - タイムスタンプ付きマイグレーションファイルを作成
  - UP/DOWN マイグレーションセクションのサポート

- ✅ **Phase 8.5: Window Functions** (79 tests)
  - **Window function AST** (`WindowFrame`, `Over`, `WindowFunc`)
  - **ランキング関数** (`row_number`, `rank`, `dense_rank`, `ntile`)
  - **値関数** (`lag`, `lead`, `first_value`, `last_value`, `nth_value`)
  - **集約ウィンドウ関数** (`win_sum`, `win_avg`, `win_min`, `win_max`, `win_count`)
  - **フレーム指定** (ROWS/RANGE/GROUPS BETWEEN)
  - **OVER 句ビルダー** (PARTITION BY, ORDER BY, frame)
  - **完全な SQLite dialect サポート** - 完全な SQL 生成

- ✅ **Phase 8.6: Set Operations** (102 tests)
  - **Set operation AST** (`SetUnion`, `SetIntersect`, `SetExcept`)
  - **UNION / UNION ALL** - クエリ結果の結合
  - **INTERSECT** - 共通行の検索
  - **EXCEPT** - 差分の検索
  - **カリー化付きパイプライン API** - 自然な合成
  - **完全な SQLite dialect サポート** - 完全な SQL 生成

- ✅ **Phase 8.7: UPSERT (ON CONFLICT)** (86 tests)
  - **OnConflict AST 型** - UPSERT サポート
  - **ON CONFLICT DO NOTHING** - 競合を無視
  - **ON CONFLICT DO UPDATE** - 競合時に更新
  - **競合ターゲット指定** - カラムベースのターゲット
  - **WHERE 句による条件付き更新** - きめ細かい制御
  - **カリー化付きパイプライン API** - 自然な合成
  - **完全な SQLite dialect サポート** - 完全な SQL 生成

- ✅ **Phase 10: DDL Support** (227 tests)
  - **DDL AST** (`CreateTable`, `AlterTable`, `DropTable`, `CreateIndex`, `DropIndex`)
  - **カラム制約** (PRIMARY KEY, NOT NULL, UNIQUE, DEFAULT, CHECK, FOREIGN KEY)
  - **テーブル制約** (PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK)
  - **ポータブルなカラム型** (`:integer`, `:text`, `:boolean`, `:timestamp` など)
  - **カリー化付きパイプライン API** - 自然なスキーマ合成
  - **完全な SQLite DDL コンパイル** - 完全な DDL SQL 生成
  - **156 DDL AST 単体テスト** + **71 SQLite DDL コンパイルテスト**

- ✅ **Phase 11: PostgreSQL Dialect** (102 tests)
  - **PostgreSQLDialect 実装** - 完全な SQL 生成
  - **PostgreSQL 固有機能**
    - `"` (ダブルクォート) による識別子クォート
    - プレースホルダー構文 `$1`, `$2`, ... (番号付き位置指定)
    - ネイティブ `BOOLEAN` 型 (TRUE/FALSE)
    - ネイティブ `ILIKE` 演算子
    - ネイティブ `UUID` 型
    - `JSONB` サポート
    - `ARRAY` 型
    - `BYTEA` (バイナリデータ)
  - **PostgreSQLDriver 実装** (LibPQ.jl)
    - 接続管理 (libpq 接続文字列)
    - トランザクションサポート (BEGIN/COMMIT/ROLLBACK)
    - セーブポイントサポート (ネストされたトランザクション)
    - 位置パラメータによるクエリ実行
  - **PostgreSQL 固有コーデック**
    - ネイティブ UUID コーデック
    - JSONB コーデック (Dict/Vector シリアライゼーション)
    - Array コーデック (Integer[], Text[], 汎用配列)
    - ネイティブ Boolean/Date/DateTime コーデック
  - **完全な DDL サポート** - CREATE TABLE, ALTER TABLE, DROP TABLE, CREATE INDEX, DROP INDEX
  - **Capability サポート** - CTE, RETURNING, UPSERT, WINDOW, LATERAL, BULK_COPY, SAVEPOINT, ADVISORY_LOCK
  - **統合テスト** - 包括的な PostgreSQL 互換性テスト

- ⏳ **Phase 12: Documentation** - [`docs/roadmap.md`](docs/roadmap.md) と [`docs/TODO.md`](docs/TODO.md) を参照

---

## 使用例

```julia
using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers

# コアクエリ構築関数をインポート
import SQLSketch.Core: from, where, select, order_by, limit, offset, distinct, group_by, having
import SQLSketch.Core: innerjoin, leftjoin, rightjoin, fulljoin  # Base.joinとの衝突を避けるエイリアス
import SQLSketch.Core: col, literal, param, func, p_
import SQLSketch.Core: between, like, case_expr
import SQLSketch.Core: subquery, in_subquery

# DML 関数をインポート
import SQLSketch.Core: insert_into, insert_values  # insert_valuesはvaluesのエイリアス（Base.valuesとの衝突回避）
import SQLSketch.Core: update, set, delete_from

# DDL 関数をインポート
import SQLSketch.Core: create_table, add_column, add_foreign_key

# 実行関数をインポート
import SQLSketch.Core: fetch_all, fetch_one, fetch_maybe, execute, sql

# トランザクション関数をインポート
import SQLSketch.Core: transaction, savepoint

# データベースに接続
driver = SQLiteDriver()
db = connect(driver, ":memory:")
dialect = SQLiteDialect()
registry = CodecRegistry()

# DDL API を使ってテーブルを作成
users_table = create_table(:users) |>
    add_column(:id, :integer; primary_key=true) |>
    add_column(:email, :text; nullable=false) |>
    add_column(:age, :integer) |>
    add_column(:status, :text; default=literal("active")) |>
    add_column(:created_at, :timestamp)

execute(db, dialect, users_table)

orders_table = create_table(:orders) |>
    add_column(:id, :integer; primary_key=true) |>
    add_column(:user_id, :integer) |>
    add_column(:total, :real) |>
    add_foreign_key([:user_id], :users, [:id])

execute(db, dialect, orders_table)

# ========================================
# 基本クエリ - col() で明示的なカラム参照
# ========================================

# col() はテーブルとカラムの参照を明示的かつ明確にします
q1 = from(:users) |>
    where(col(:users, :status) == literal("active")) |>
    select(NamedTuple, col(:users, :id), col(:users, :email))

# 生成される SQL:
# SELECT `users`.`id`, `users`.`email`
# FROM `users`
# WHERE (`users`.`status` = 'active')

# ========================================
# Placeholder 構文 - 単一テーブルクエリでの便利な糖衣構文
# ========================================

# p_ は糖衣構文: p_.column は col(推論されたテーブル, :column) に展開されます
# シンプルなクエリではより簡潔ですが、テーブル名は暗黙的です
q2 = from(:users) |>
    where(p_.status == "active") |>
    select(NamedTuple, p_.id, p_.email)

# 生成される SQL（q1 と同じ）:
# SELECT `users`.`id`, `users`.`email`
# FROM `users`
# WHERE (`users`.`status` = 'active')

# ========================================
# 高度な機能 - CASE、BETWEEN、LIKE
# ========================================

q3 = from(:users) |>
    where(p_.age |> between(18, 65)) |>
    where(p_.email |> like("%@gmail.com")) |>
    select(NamedTuple,
           p_.id,
           p_.email,
           # CASE 式で年齢カテゴリを分類
           case_expr([
               (p_.age < 18, "minor"),
               (p_.age < 65, "adult")
           ], "senior")) |>
    order_by(p_.created_at; desc=true) |>
    limit(10)

# 生成される SQL:
# SELECT `users`.`id`, `users`.`email`,
#   CASE WHEN (`users`.`age` < 18) THEN 'minor'
#        WHEN (`users`.`age` < 65) THEN 'adult'
#        ELSE 'senior' END
# FROM `users`
# WHERE ((`users`.`age` BETWEEN 18 AND 65) AND (`users`.`email` LIKE '%@gmail.com'))
# ORDER BY `users`.`created_at` DESC
# LIMIT 10

# ========================================
# JOIN クエリ - 明示的な col() が明確性のために重要
# ========================================

# テーブルを結合する場合、明示的な col() により各カラムがどのテーブルに属するか明確になります
q4 = from(:users) |>
    innerjoin(:orders, col(:orders, :user_id) == col(:users, :id)) |>
    where(col(:users, :status) == literal("active")) |>
    select(NamedTuple,
           col(:users, :id),
           col(:users, :email),
           col(:orders, :total))

# 生成される SQL:
# SELECT `users`.`id`, `users`.`email`, `orders`.`total`
# FROM `users`
# INNER JOIN `orders` ON (`orders`.`user_id` = `users`.`id`)
# WHERE (`users`.`status` = 'active')

# ========================================
# サブクエリの例
# ========================================

active_users = subquery(
    from(:users) |>
    where(p_.status == "active") |>
    select(NamedTuple, p_.id)
)

q5 = from(:orders) |>
    where(in_subquery(p_.user_id, active_users)) |>
    select(NamedTuple, p_.id, p_.user_id, p_.total)

# 生成される SQL:
# SELECT `orders`.`id`, `orders`.`user_id`, `orders`.`total`
# FROM `orders`
# WHERE (`orders`.`user_id` IN (SELECT `users`.`id` FROM `users` WHERE (`users`.`status` = 'active')))

# ========================================
# 実行前に SQL を検査
# ========================================

sql_str = sql(dialect, q4)
println(sql_str)  # 生成された SQL を確認

# ========================================
# クエリを実行して型付き結果を取得
# ========================================

users = fetch_all(db, dialect, registry, q2)  # Vector{NamedTuple} を返す
user = fetch_one(db, dialect, registry, q2)   # NamedTuple を返す（厳密に1件でない場合エラー）
maybe_user = fetch_maybe(db, dialect, registry, q2)  # Union{NamedTuple, Nothing} を返す

# ========================================
# トランザクション管理
# ========================================

import SQLSketch.Core: transaction, savepoint

# トランザクション内で複数の操作を実行
result = transaction(db) do tx
    # トランザクション内で INSERT を実行
    insert_q = insert_into(:users, [:email, :age, :status]) |>
        values([[param(String, :email), param(Int, :age), param(String, :status)]])
    execute(tx, dialect, insert_q, (email = "tx@example.com", age = 40, status = "active"))

    # トランザクション内で UPDATE を実行
    update_q = update(:users) |>
        set(:status => literal("premium")) |>
        where(col(:users, :email) == param(String, :email))
    execute(tx, dialect, update_q, (email = "tx@example.com",))

    # 正常に完了すると自動的にコミットされます
    return "success"
end

# セーブポイントを使ったネストされたトランザクション
transaction(db) do tx
    execute(tx, dialect, insert_into(:users, [:email]) |> values([[literal("outer@example.com")]]))

    # セーブポイントを作成 - 内部操作のみをロールバック可能
    try
        savepoint(tx, :sp1) do sp
            execute(sp, dialect, insert_into(:users, [:email]) |> values([[literal("inner@example.com")]]))
            error("Simulated failure")  # これはセーブポイントまでロールバックされます
        end
    catch e
        # セーブポイントがロールバックされました、外部のトランザクションは継続します
    end

    # 外部のトランザクションはまだアクティブで、コミットされます
end

# ========================================
# マイグレーション
# ========================================

import SQLSketch.Core: apply_migrations, migration_status, generate_migration

# 新しいマイグレーションファイルを生成
migration_path = generate_migration("db/migrations", "add_user_roles")
# 生成されるファイル: db/migrations/20250120150000_add_user_roles.sql
# 内容:
# -- UP
#
# -- DOWN
#

# すべての保留中のマイグレーションを適用
applied = apply_migrations(db, dialect, "db/migrations")
println("Applied $(length(applied)) migrations")

# マイグレーションステータスを確認
status = migration_status(db, dialect, "db/migrations")
for s in status
    status_icon = s.applied ? "✓" : "✗"
    println("$status_icon $(s.migration.version) $(s.migration.name)")
end

# マイグレーション機能:
# - タイムスタンプベースのバージョニング (YYYYMMDDHHMMSS)
# - SHA256 チェックサム検証（変更されたマイグレーションを検出）
# - トランザクション内での実行（失敗時の自動ロールバック）
# - schema_migrations テーブルでの自動追跡
# - UP/DOWN セクションのサポート（DOWN は将来の機能）

# ========================================
# DML 操作（INSERT、UPDATE、DELETE）
# ========================================

# リテラルを使った INSERT
insert_q = insert_into(:users, [:email, :age, :status]) |>
    values([[literal("alice@example.com"), literal(25), literal("active")]])
execute(db, dialect, insert_q)
# 生成される SQL:
# INSERT INTO `users` (`email`, `age`, `status`) VALUES ('alice@example.com', 25, 'active')

# パラメータを使った INSERT（型安全なバインディング）
insert_q2 = insert_into(:users, [:email, :age, :status]) |>
    values([[param(String, :email), param(Int, :age), param(String, :status)]])
execute(db, dialect, insert_q2, (email="bob@example.com", age=30, status="active"))
# 生成される SQL:
# INSERT INTO `users` (`email`, `age`, `status`) VALUES (?, ?, ?)
# パラメータ: ["bob@example.com", 30, "active"]

# WHERE 句付き UPDATE
update_q = update(:users) |>
    set(:status => param(String, :status)) |>
    where(col(:users, :email) == param(String, :email))
execute(db, dialect, update_q, (status="inactive", email="alice@example.com"))
# 生成される SQL:
# UPDATE `users` SET `status` = ? WHERE (`users`.`email` = ?)
# パラメータ: ["inactive", "alice@example.com"]

# WHERE 句付き DELETE
delete_q = delete_from(:users) |>
    where(col(:users, :status) == literal("inactive"))
execute(db, dialect, delete_q)
# 生成される SQL:
# DELETE FROM `users` WHERE (`users`.`status` = 'inactive')

close(db)
```

---

## プロジェクト構造

```
src/
  Core/              # Core layer 実装
    expr.jl          # 式 AST ✅
    query.jl         # クエリ AST ✅
    dialect.jl       # Dialect 抽象化 ✅
    driver.jl        # Driver 抽象化 ✅
    codec.jl         # 型変換 ✅
    execute.jl       # クエリ実行 ✅
    transaction.jl   # トランザクション管理 ✅
    migrations.jl    # マイグレーションランナー ✅
    ddl.jl           # DDL サポート ✅
  Dialects/          # Dialect 実装
    sqlite.jl        # SQLite SQL 生成 ✅
    postgresql.jl    # PostgreSQL SQL 生成 ✅
    shared_helpers.jl # 共有ヘルパー関数 ✅
  Drivers/           # Driver 実装
    sqlite.jl        # SQLite 実行 ✅
    postgresql.jl    # PostgreSQL 実行 ✅
  Codecs/            # データベース固有コーデック
    postgresql.jl    # PostgreSQL 固有コーデック (UUID, JSONB, Array) ✅

test/                # テストスイート (1712 tests)
  core/
    expr_test.jl         # 式のテスト ✅ (268)
    query_test.jl        # クエリのテスト ✅ (232)
    window_test.jl       # Window 関数のテスト ✅ (79)
    set_operations_test.jl  # Set 操作のテスト ✅ (102)
    upsert_test.jl       # UPSERT のテスト ✅ (86)
    codec_test.jl        # Codec のテスト ✅ (115)
    transaction_test.jl  # トランザクションのテスト ✅ (26)
    migrations_test.jl   # マイグレーションのテスト ✅ (79)
    ddl_test.jl          # DDL のテスト ✅ (156)
  dialects/
    sqlite_test.jl       # SQLite dialect のテスト ✅ (331)
    postgresql_test.jl   # PostgreSQL dialect のテスト ✅ (102)
  drivers/
    sqlite_test.jl       # SQLite driver のテスト ✅ (41)
  integration/
    end_to_end_test.jl   # 統合テスト ✅ (95)
    postgresql_integration_test.jl  # PostgreSQL 統合テスト ✅

docs/                # ドキュメント
  design.md          # 設計ドキュメント
  roadmap.md         # 実装ロードマップ
  TODO.md            # タスク詳細
  CLAUDE.md          # Claude 向け実装ガイドライン
```

---

## 開発

### テスト実行

```bash
# 全テストを実行
julia --project -e 'using Pkg; Pkg.test()'

# 特定のテストファイルを実行
julia --project test/core/expr_test.jl
```

### REPL 起動

```bash
julia --project
```

### 現在のテスト状況

```
Total: 1712 tests passing ✅

Phase 1 (Expression AST):         268 tests (CAST、Subquery、CASE、BETWEEN、IN、LIKE)
Phase 2 (Query AST):              232 tests (DML、CTE、RETURNING)
Phase 3 (SQLite Dialect):         331 tests (DML + CTE + DDL コンパイル、すべての式型)
Phase 4 (Driver Abstraction):      41 tests (SQLite driver)
Phase 5 (CodecRegistry):          115 tests (型変換、NULL ハンドリング)
Phase 6 (End-to-End Integration):  95 tests (DML 実行、CTE、完全なパイプライン)
Phase 7 (Transactions):            26 tests (transaction、savepoint、ロールバック)
Phase 8 (Migrations):              79 tests (検出、適用、チェックサム検証)
Phase 8.5 (Window Functions):      79 tests (ランキング、値、集約ウィンドウ関数)
Phase 8.6 (Set Operations):       102 tests (UNION、INTERSECT、EXCEPT)
Phase 8.7 (UPSERT):                86 tests (ON CONFLICT DO NOTHING/UPDATE)
Phase 10 (DDL Support):           227 tests (CREATE/ALTER/DROP TABLE、CREATE/DROP INDEX)
Phase 11 (PostgreSQL Dialect):    102 tests (PostgreSQL SQL 生成、driver、codecs)
```

---

## ドキュメント

- [`docs/design.md`](docs/design.md) – 設計哲学とアーキテクチャ
- [`docs/roadmap.md`](docs/roadmap.md) – 段階的実装計画（10 フェーズ）
- [`docs/TODO.md`](docs/TODO.md) – 詳細タスク分解（400+ タスク）

---

## 設計原則

### 1. SQL は常に可視化可能

```julia
# 悪い例：隠された SQL
users = User.where(active: true).limit(10)

# 良い例：検査可能な SQL
q = from(:users) |> where(col(:users, :active) == true) |> limit(10)
sql(q)  # SQL を表示
```

### 2. 論理的評価順序

クエリ構築は SQL の**論理的評価順序**に従います。構文順序ではありません。

#### SQL の論理的評価順序（SQL が実際に行う処理順序）

```
1. WITH (CTE)              — 共通テーブル式を定義
2. FROM                    — ソーステーブルを特定
3. JOIN                    — テーブルを結合（INNER, LEFT, RIGHT, FULL）
4. WHERE                   — グループ化前の行フィルタリング
5. GROUP BY                — 集約のための行グループ化
6. HAVING                  — 集約後のグループフィルタリング
7. Window Functions        — パーティション上での計算（OVER 句）
8. SELECT                  — カラムの射影（shape-changing）
9. DISTINCT                — 重複行の削除
10. Set Operations         — クエリの結合（UNION, INTERSECT, EXCEPT）
11. ORDER BY               — 結果行のソート
12. LIMIT / OFFSET         — 結果セットサイズの制限
```

SQLSketch.jl のパイプライン API はこの論理的順序に従います：

```julia
# 論理的評価順序を使用したクエリ例
q = with(:recent_orders,
         from(:orders) |>
         where(col(:orders, :created_at) > literal("2024-01-01"))) |>
    from(:recent_orders) |>
    innerjoin(:users, col(:recent_orders, :user_id) == col(:users, :id)) |>
    where(col(:users, :active) == literal(true)) |>
    group_by(col(:users, :id), col(:users, :email)) |>
    having(func(:COUNT, col(:recent_orders, :id)) > literal(5)) |>
    select(NamedTuple,
           col(:users, :id),
           col(:users, :email),
           func(:COUNT, col(:recent_orders, :id))) |>
    order_by(func(:COUNT, col(:recent_orders, :id)); desc=true) |>
    limit(10)
```

これは SQL の**構文順序**（SQL の記述順序）と対照的です：

```sql
WITH recent_orders AS (...)
SELECT ...
FROM recent_orders
JOIN users ON ...
WHERE ...
GROUP BY ...
HAVING ...
ORDER BY ...
LIMIT ...
```

論理的順序に従うことで、SQLSketch.jl はクエリ変換を予測可能かつ型安全にします。

### 3. 境界での型安全性

```julia
# クエリは出力型を知っている
q::Query{User} = from(:users) |> select(User, ...)

# 実行は型安全
users::Vector{User} = fetch_all(db, dialect, registry, q)
```

### 4. 最小限の隠れた魔法

- 暗黙的なスキーマ読み込みなし
- 自動的なリレーション読み込みなし
- グローバル状態なし
- 明示的は暗黙的より良い

---

## SQLSketch.jl が _ではないもの_

- ❌ フル機能の ORM
- ❌ 生 SQL の置き換え
- ❌ スキーママイグレーションツール（マイグレーションは最小限）
- ❌ ActiveRecord クローン
- ❌ プロダクション対応（トイプロジェクトです！）

これは設計上、**型付き SQL クエリビルダー** です。

---

## 要件

- Julia **1.12+**（Project.toml で指定）

### 現在の依存関係

**データベースドライバ:**
- **SQLite.jl** - SQLite データベースドライバ ✅
- **LibPQ.jl** - PostgreSQL データベースドライバ ✅
- **DBInterface.jl** - データベースインターフェース抽象化 ✅

**型サポート:**
- **Dates**（stdlib）- Date/DateTime 型サポート ✅
- **UUIDs**（stdlib）- UUID 型サポート ✅
- **JSON3** - JSON/JSONB シリアライゼーション（PostgreSQL）✅
- **SHA**（stdlib）- マイグレーションチェックサム検証 ✅

**開発ツール:**
- **JET** - 静的解析と型チェック ✅
- **JuliaFormatter** - コードフォーマット ✅

### 将来の依存関係

- MySQL.jl（MySQL サポート）
- MariaDB.jl（MariaDB サポート）

---

## ロードマップ

完全な実装計画については [`docs/roadmap.md`](docs/roadmap.md) を参照してください。

**進捗状況:**
- ✅ Phase 1-3（式、クエリ、SQLite Dialect）: 6 週間 - **完了**
- ✅ Phase 4-6（Driver、Codec、統合）: 6 週間 - **完了**
- ✅ Phase 7-8（トランザクション、マイグレーション）: 2 週間 - **完了**
- ✅ Phase 8.5-8.7（Window Functions、Set Operations、UPSERT）: 1 週間 - **完了**
- ✅ Phase 10（DDL サポート）: 1 週間 - **完了**
- ✅ Phase 11（PostgreSQL Dialect）: 2 週間 - **完了**
- ⏳ Phase 12（ドキュメント）: 2+ 週間 - **次**

**現在のステータス:** 11/12 フェーズ完了（91.7%）

---

## ライセンス

MIT License
