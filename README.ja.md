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

**完了フェーズ:** 1/10

- ✅ **Phase 1: Expression AST**（135 テスト全てパス）
  - カラム参照、リテラル、パラメータ
  - 自動ラップ付きの二項/単項演算子
  - 関数呼び出し
  - 型安全な合成

- ⏳ **Phase 2-10:** [`docs/roadmap.md`](docs/roadmap.md) と [`docs/TODO.md`](docs/TODO.md) を参照

---

## 使用例（将来の API）

```julia
using SQLSketch

# データベースに接続
db = connect(SQLiteDriver(), ":memory:")

# 型安全な合成でクエリを構築
q = from(:users) |>
    where(col(:users, :active) == true) |>
    select(User, col(:users, :id), col(:users, :email)) |>
    order_by(col(:users, :created_at), desc=true) |>
    limit(10)

# 実行前に SQL を検査
println(sql(q))
# => "SELECT `users`.`id`, `users`.`email` FROM `users`
#     WHERE `users`.`active` = ? ORDER BY `users`.`created_at` DESC LIMIT 10"

# 実行して型付き結果を取得
users = all(db, q)  # Vector{User} を返す
```

---

## プロジェクト構造

```
src/
  Core/              # Core layer 実装
    expr.jl          # 式 AST ✅
    query.jl         # クエリ AST ⏳
    dialect.jl       # Dialect 抽象化 ⏳
    driver.jl        # Driver 抽象化 ⏳
    codec.jl         # 型変換 ⏳
    execute.jl       # クエリ実行 ⏳
    transaction.jl   # トランザクション管理 ⏳
    migrations.jl    # マイグレーションランナー ⏳
  Dialects/          # Dialect 実装
    sqlite.jl        # SQLite SQL 生成 ⏳
  Drivers/           # Driver 実装
    sqlite.jl        # SQLite 実行 ⏳

test/                # テストスイート
  core/
    expr_test.jl     # 式のテスト ✅
  dialects/
  drivers/
  integration/

docs/                # ドキュメント
  design.md          # 設計ドキュメント
  roadmap.md         # 実装ロードマップ
  TODO.md            # タスク詳細
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
Test Summary:  | Pass  Total
Expression AST |  135    135
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
users::Vector{User} = all(db, q)
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

**推定タイムライン:**
- Phase 1-3（式、クエリ、Dialect）: 6 週間 ✅ (1/3 完了)
- Phase 4-6（Driver、Codec、統合）: 6 週間
- Phase 7-8（トランザクション、マイグレーション）: 2 週間
- Phase 9（PostgreSQL）: 2 週間
- Phase 10（ドキュメント）: 2+ 週間

**合計:** Core layer で約 16 週間

---

## ライセンス

MIT License
