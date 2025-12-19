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

**完了フェーズ:** 6/10 | **総テスト数:** 544 passing ✅

- ✅ **Phase 1: Expression AST** (135 tests)
  - カラム参照、リテラル、パラメータ
  - 自動ラップ付きの二項/単項演算子
  - 関数呼び出し
  - 型安全な合成

- ✅ **Phase 2: Query AST** (85 tests)
  - FROM, WHERE, SELECT, JOIN, ORDER BY
  - LIMIT, OFFSET, DISTINCT, GROUP BY, HAVING
  - `|>` によるパイプライン合成
  - Shape-preserving と shape-changing セマンティクス
  - 型安全なクエリ変換

- ✅ **Phase 3: Dialect Abstraction** (102 tests)
  - Dialect インターフェース（compile, quote_identifier, placeholder, supports）
  - 機能検出のための Capability システム
  - SQLite dialect 実装
  - クエリ AST からの完全な SQL 生成
  - 式とクエリのコンパイル

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
  - 型安全なパラメータバインディング
  - 完全なパイプライン: Query AST → Dialect → Driver → CodecRegistry
  - 可観測性 API（`sql`, `explain`）
  - 包括的な統合テスト

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
        active INTEGER DEFAULT 1,
        created_at TEXT
    )
""", [])

# 型安全なクエリを構築
q = from(:users) |>
    where(col(:users, :active) == literal(1)) |>
    select(NamedTuple, col(:users, :id), col(:users, :email)) |>
    order_by(col(:users, :created_at); desc=true) |>
    limit(10)

# 実行前に SQL を検査
sql_str = sql(dialect, q)
println(sql_str)
# => "SELECT `id`, `email` FROM `users` WHERE `active` = 1 ORDER BY `created_at` DESC LIMIT 10"

# 実行して型付き結果を取得
users = fetch_all(db, dialect, registry, q)  # Returns Vector{NamedTuple}

# または、厳密に1件取得
user = fetch_one(db, dialect, registry, q)  # Returns NamedTuple（1件でない場合エラー）

# または、0件か1件取得
maybe_user = fetch_maybe(db, dialect, registry, q)  # Returns Union{NamedTuple, Nothing}

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

test/                # テストスイート (544 tests)
  core/
    expr_test.jl     # 式のテスト ✅ (135)
    query_test.jl    # クエリのテスト ✅ (85)
    codec_test.jl    # Codec のテスト ✅ (115)
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
Total: 544 tests passing ✅

Phase 1 (Expression AST):        135 tests
Phase 2 (Query AST):              85 tests
Phase 3 (Dialect Abstraction):   102 tests
Phase 4 (Driver Abstraction):     41 tests
Phase 5 (CodecRegistry):         115 tests (includes 112 codec + 3 map_row)
Phase 6 (End-to-End Integration): 54 tests
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

将来の依存関係（実装の進行に応じて追加されます）：
- SQLite.jl (Phase 4)
- DBInterface.jl (Phase 4)
- Dates (Phase 5)
- UUIDs (Phase 5)

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
