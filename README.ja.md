**[English README is available here / 英語版 README](README.md)**

---

⚠️ **メンテナンスに関する注意**

**これはトイプロジェクトであり、積極的にメンテナンスされていません。**

このパッケージは、Julia で型付き SQL クエリビルダーの設計を探求するための教育的/実験的なプロジェクトとして作成されました。
コードは機能しますが、本番環境での使用は推奨しません。
Issue や Pull Request には対応しない可能性があります。

---

> ⚠️ **ステータス**
>
> SQLSketch.jl は現在、[@daikichiba9511](https://github.com/daikichiba9511)が開発している**サンプル/実験的なパッケージ**です。
>
> このリポジトリの主な目的は、以下に焦点を当てた *Julia ネイティブな SQL クエリビルディングのアプローチ*を探求し、文書化することです：
>
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

SQLSketch は 2 層システムとして設計されています：

```
┌─────────────────────────────────┐
│      Extras Layer (将来)         │  ← オプションの便利機能
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

## ステータス

**完了:** 12/12 フェーズ | **テスト:** 1712 passing ✅

実装済みのコア機能:

- ✅ 式 & クエリ AST (500 tests)
- ✅ SQLite & PostgreSQL dialects (433 tests)
- ✅ 型安全な実行 & codecs (251 tests)
- ✅ トランザクション & マイグレーション (105 tests)
- ✅ Window 関数、集合演算、UPSERT (267 tests)
- ✅ DDL サポート (227 tests)

詳細な内訳は [**実装ステータス**](docs/implementation-status.md) を参照。

---

## 使用例

### クイックスタート

```julia
using SQLSketch
using SQLSketch.Core        # コアクエリ構築型
using SQLSketch.Drivers     # データベースドライバ

# クエリ構築用:
import SQLSketch.Core: from, where, select, col, literal, p_

# データベースに接続
driver = SQLiteDriver()
db = connect(driver, ":memory:")
dialect = SQLiteDialect()
registry = CodecRegistry()

# クエリを構築して実行
q = from(:users) |>
    where(p_.status == "active") |>
    select(NamedTuple, p_.id, p_.email)

users = fetch_all(db, dialect, registry, q)
# => Vector{NamedTuple{(:id, :email), ...}}

close(db)
```

### よくあるユースケース

**1. WHERE と ORDER BY を使った基本クエリ**

```julia
# 必要な import:
using SQLSketch.Core
import SQLSketch.Core: from, where, select, order_by, col, literal

q = from(:users) |>
    where(col(:users, :age) > literal(18)) |>
    select(NamedTuple, col(:users, :id), col(:users, :name)) |>
    order_by(col(:users, :name))
```

**2. JOIN クエリ**

```julia
# 必要な import:
import SQLSketch.Core: from, innerjoin, where, select, col, literal

q = from(:users) |>
    innerjoin(:orders, col(:orders, :user_id) == col(:users, :id)) |>
    where(col(:users, :status) == literal("active")) |>
    select(NamedTuple, col(:users, :name), col(:orders, :total))
```

**3. パラメータを使った INSERT**

```julia
# 必要な import:
import SQLSketch.Core: insert_into, insert_values, param, execute

insert_q = insert_into(:users, [:email, :age]) |>
    insert_values([[param(String, :email), param(Int, :age)]])

execute(db, dialect, insert_q, (email="alice@example.com", age=25))
```

**4. 複数操作のトランザクション**

```julia
# 必要な import:
import SQLSketch.Core: transaction, insert_into, insert_values, literal, execute

transaction(db) do tx
    execute(tx, dialect,
        insert_into(:users, [:email]) |>
        insert_values([[literal("user@example.com")]]))

    execute(tx, dialect,
        insert_into(:orders, [:user_id, :total]) |>
        insert_values([[literal(1), literal(99.99)]]))
end
```

**5. データベースマイグレーション**

```julia
# 必要な import:
using SQLSketch.Extras: apply_migrations, migration_status

# 保留中のマイグレーションを適用
applied = apply_migrations(db, "db/migrations")

# ステータスを確認
status = migration_status(db, "db/migrations")
```

**6. DDL - テーブル作成**

```julia
# 必要な import:
import SQLSketch.Core: create_table, add_column, add_foreign_key, literal, execute

table = create_table(:users) |>
    add_column(:id, :integer; primary_key=true) |>
    add_column(:email, :text; nullable=false) |>
    add_column(:status, :text; default=literal("active"))

execute(db, dialect, table)
```

より詳細な例は [`examples/`](examples/) を参照してください。

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

詳細なテスト内訳は [`docs/implementation-status.md`](docs/implementation-status.md) を参照してください。

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

完全な実装計画と詳細なステータスについては [`docs/roadmap.md`](docs/roadmap.md) と [`docs/implementation-status.md`](docs/implementation-status.md) を参照してください。

---

## ライセンス

MIT License
