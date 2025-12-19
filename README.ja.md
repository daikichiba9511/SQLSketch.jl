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
- SQLite ファーストの開発、PostgreSQL / MySQL との互換性

---

## アーキテクチャ

SQLSketch は2層システムとして設計されています：

```
┌─────────────────────────────────┐
│      Easy Layer (将来)          │  ← オプションの便利機能
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

### Easy Layer（将来）
- Repository パターン
- CRUD ヘルパー
- リレーションのプリロード
- スキーママクロ

---

## 現在の実装状況

**完了フェーズ:** 6/10 | **総テスト数:** 662+ passing ✅

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

- ✅ **Phase 2: Query AST** (85 tests)
  - FROM, WHERE, SELECT, JOIN, ORDER BY
  - LIMIT, OFFSET, DISTINCT, GROUP BY, HAVING
  - **INSERT, UPDATE, DELETE**（DML 操作）
  - `|>` によるパイプライン合成
  - Shape-preserving と shape-changing セマンティクス
  - 型安全なクエリ変換
  - **カリー化 API** - 自然なパイプライン合成

- ✅ **Phase 3: Dialect Abstraction** (102 tests)
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

- ✅ **Phase 5: CodecRegistry** (112 tests)
  - Julia と SQL 間の型安全なエンコード/デコード
  - 組み込みコーデック（Int, Float64, String, Bool, Date, DateTime, UUID）
  - NULL/Missing ハンドリング
  - NamedTuple と構造体への行マッピング

- ✅ **Phase 6: End-to-End Integration** (54 tests)
  - クエリ実行 API（`fetch_all`, `fetch_one`, `fetch_maybe`）
  - **DML 実行 API（`execute_dml`）**
  - 型安全なパラメータバインディング
  - 完全なパイプライン: Query AST → Dialect → Driver → CodecRegistry
  - 可観測性 API（`sql`, `explain`）
  - 包括的な統合テスト
  - **完全な CRUD 操作**（SELECT、INSERT、UPDATE、DELETE）

- ⏳ **Phase 7-10:** [`docs/roadmap.md`](docs/roadmap.md) と [`docs/TODO.md`](docs/TODO.md) を参照

---

## 使用例

```julia
using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers

# 実行関数をインポート
import SQLSketch.Core: fetch_all, fetch_one, fetch_maybe, sql, explain

# データベースに接続
driver = SQLiteDriver()
db = connect(driver, ":memory:")
dialect = SQLiteDialect()
registry = CodecRegistry()

# テーブルを作成
execute(db, """
    CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        email TEXT NOT NULL,
        age INTEGER,
        status TEXT DEFAULT 'active',
        created_at TEXT
    )
""", [])

# 高度な機能を使った型安全なクエリを構築
q = from(:users) |>
    where(p_.status == "active") |>  # Placeholder 構文
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

# 実行前に SQL を検査
sql_str = sql(dialect, q)
println(sql_str)
# => SELECT `users`.`id`, `users`.`email`,
#    CASE WHEN (`users`.`age` < 18) THEN 'minor' WHEN (`users`.`age` < 65) THEN 'adult' ELSE 'senior' END
#    FROM `users` WHERE (`users`.`status` = 'active') ORDER BY `users`.`created_at` DESC LIMIT 10

# 高度な式の例
q2 = from(:users) |>
    where(p_.age |> between(18, 65)) |>  # BETWEEN 演算子
    where(p_.email |> like("%@gmail.com")) |>  # LIKE 演算子
    select(NamedTuple, p_.id, p_.email)

# サブクエリの例
active_users = subquery(
    from(:users) |>
    where(p_.status == "active") |>
    select(NamedTuple, p_.id)
)

q3 = from(:orders) |>
    where(in_subquery(p_.user_id, active_users)) |>  # IN サブクエリ
    select(NamedTuple, p_.id, p_.user_id)

# 実行して型付き結果を取得
users = fetch_all(db, dialect, registry, q)  # Returns Vector{NamedTuple}

# または、厳密に1件取得
user = fetch_one(db, dialect, registry, q)  # Returns NamedTuple（1件でない場合エラー）

# または、0件か1件取得
maybe_user = fetch_maybe(db, dialect, registry, q)  # Returns Union{NamedTuple, Nothing}

# DML 操作（INSERT、UPDATE、DELETE）
import SQLSketch.Core: execute_dml

# リテラルを使った INSERT
insert_q = insert_into(:users, [:email, :active]) |>
    values([[literal("alice@example.com"), literal(1)]])
execute_dml(db, dialect, insert_q)

# パラメータを使った INSERT
insert_q = insert_into(:users, [:email, :active]) |>
    values([[param(String, :email), param(Int, :active)]])
execute_dml(db, dialect, insert_q, (email="bob@example.com", active=1))

# WHERE 句付き UPDATE
update_q = update(:users) |>
    set(:active => param(Int, :active)) |>
    where(col(:users, :email) == param(String, :email))
execute_dml(db, dialect, update_q, (active=0, email="alice@example.com"))

# WHERE 句付き DELETE
delete_q = delete_from(:users) |>
    where(col(:users, :active) == literal(0))
execute_dml(db, dialect, delete_q)

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
    transaction.jl   # トランザクション管理 ⏳
    migrations.jl    # マイグレーションランナー ⏳
  Dialects/          # Dialect 実装
    sqlite.jl        # SQLite SQL 生成 ✅
  Drivers/           # Driver 実装
    sqlite.jl        # SQLite 実行 ✅

test/                # テストスイート (662+ tests)
  core/
    expr_test.jl     # 式のテスト ✅ (268)
    query_test.jl    # クエリのテスト ✅ (85)
    codec_test.jl    # Codec のテスト ✅ (112)
  dialects/
    sqlite_test.jl   # SQLite dialect のテスト ✅ (102)
  drivers/
    sqlite_test.jl   # SQLite driver のテスト ✅ (41)
  integration/
    end_to_end_test.jl  # 統合テスト ✅ (54)

docs/                # ドキュメント
  design.md          # 設計ドキュメント
  roadmap.md         # 実装ロードマップ
  TODO.md            # タスク詳細
  CLAUDE.md          # 実装ガイドライン
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
Total: 662+ tests passing ✅

Phase 1 (Expression AST):        268 tests (CAST、Subquery、CASE、BETWEEN、IN、LIKE)
Phase 2 (Query AST):              85 tests (DML: INSERT/UPDATE/DELETE を含む)
Phase 3 (Dialect Abstraction):   102 tests (DML コンパイル + すべての式型)
Phase 4 (Driver Abstraction):     41 tests
Phase 5 (CodecRegistry):         112 tests
Phase 6 (End-to-End Integration): 54 tests (DML 実行を含む)
Phase 7 (Transactions):           ⏳ 未実装
Phase 8 (Migrations):             ⏳ 未実装
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

クエリ構築は SQL の論理的順序に従う：
```
FROM → WHERE → SELECT → ORDER BY → LIMIT
```

SQL の構文順序ではなく：
```
SELECT → FROM → WHERE → ORDER BY → LIMIT
```

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

- Julia **1.9+**（Project.toml で指定）

### 現在の依存関係

- **SQLite.jl** - SQLite データベースドライバ ✅
- **DBInterface.jl** - データベースインターフェース抽象化 ✅
- **Dates**（stdlib）- Date/DateTime 型サポート ✅
- **UUIDs**（stdlib）- UUID 型サポート ✅

### 将来の依存関係

- LibPQ.jl（Phase 9 - PostgreSQL サポート）
- MySQL.jl（将来 - MySQL サポート）

---

## ロードマップ

完全な実装計画については [`docs/roadmap.md`](docs/roadmap.md) を参照してください。

**進捗状況:**
- ✅ Phase 1-3（式、クエリ、Dialect）: 6 週間 - **完了**
- ✅ Phase 4-6（Driver、Codec、統合）: 6 週間 - **完了**
- ⏳ Phase 7-8（トランザクション、マイグレーション）: 2 週間 - **次**
- ⏳ Phase 9（PostgreSQL）: 2 週間
- ⏳ Phase 10（ドキュメント）: 2+ 週間

**推定合計:** Core layer で約 18 週間（60% 完了）

---

## ライセンス

MIT License
