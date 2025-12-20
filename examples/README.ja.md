# SQLSketch.jl サンプル集

このディレクトリには、SQLSketch.jl のさまざまな機能を実演するサンプルスクリプトが含まれています。

## サンプルの実行方法

```bash
# リポジトリのルートから
julia --project=. examples/<サンプルファイル>.jl
```

## 利用可能なサンプル

### 1. 基本クエリ (`basic_queries.jl`)

基本的なクエリ操作を実演:
- シンプルな WHERE と ORDER BY 句
- JOIN クエリ
- パラメータを使った INSERT
- トランザクション
- UPDATE と DELETE 操作

**実行方法:**
```bash
julia --project=. examples/basic_queries.jl
```

### 2. JOIN 操作 (`join_examples.jl`)

すべての JOIN タイプの包括的な例:
- INNER JOIN - 一致する行のみ
- LEFT JOIN - 左側の全行、右側は一致するもの（NULL を含む）
- RIGHT JOIN - 右側の全行、左側は一致するもの（SQLite 制限の回避策）
- FULL JOIN - 両テーブルの全行
- Multiple JOINs - 複数の結合操作のチェーン
- Self-joins - テーブルを自身に結合
- JOIN with filtering - WHERE 句との組み合わせ

**実行方法:**
```bash
julia --project=. examples/join_examples.jl
```

### 3. ウィンドウ関数 (`window_functions.jl`)

SQL ウィンドウ関数の使い方を紹介:
- ROW_NUMBER, RANK, DENSE_RANK
- LAG と LEAD による連続比較
- SUM による累計
- AVG による移動平均
- NTILE によるパーセンタイル
- FIRST_VALUE と LAST_VALUE

**実行方法:**
```bash
julia --project=. examples/window_functions.jl
```

### 4. データベースマイグレーション (`migrations_example.jl`)

マイグレーションシステムを実演:
- マイグレーションファイルの生成
- マイグレーションの適用
- マイグレーションステータスの確認
- SHA256 チェックサム検証
- べき等性

**実行方法:**
```bash
julia --project=. examples/migrations_example.jl
```

### 5. PostgreSQL 機能 (`postgresql_example.jl`)

PostgreSQL 固有の機能:
- UUID プライマリーキー
- 構造化データ用の JSONB
- ARRAY 型
- TIMESTAMP WITH TIME ZONE
- RETURNING 句
- セーブポイント（ネストされたトランザクション）

**前提条件:**
- PostgreSQL サーバーが起動していること
- データベース `sqlsketch_test` が作成されていること

**セットアップ:**
```bash
# テストデータベースを作成
psql -c 'CREATE DATABASE sqlsketch_test;'

# 環境変数を設定（オプション）
export PGHOST=localhost
export PGPORT=5432
export PGDATABASE=sqlsketch_test
export PGUSER=postgres
export PGPASSWORD=your_password
```

**実行方法:**
```bash
julia --project=. examples/postgresql_example.jl
```

### 6. 手動統合テスト (`manual_integration_test.jl`)

完全なフローを示す低レベル統合テスト:
- データベースのセットアップ
- Query AST の構築
- SQL コンパイル
- ドライバー実行
- CodecRegistry による結果のデコード

このサンプルは、各レイヤーがどのように連携するかを理解するのに役立ちます。

**実行方法:**
```bash
julia --project=. examples/manual_integration_test.jl
```

### 7. テストデータベースの作成 (`create_test_db.jl`)

手動検査用の永続的な SQLite データベースを作成:
- `examples/test.db` を作成
- サンプルユーザーと投稿を格納
- 外部キーを実演

**実行方法:**
```bash
julia --project=. examples/create_test_db.jl

# その後 sqlite3 で検査
sqlite3 examples/test.db
```

## クイックスタート

```bash
# 基本クエリサンプルを実行
julia --project=. examples/basic_queries.jl

# JOIN サンプルを実行
julia --project=. examples/join_examples.jl

# ウィンドウ関数サンプルを実行
julia --project=. examples/window_functions.jl

# マイグレーションサンプルを実行
julia --project=. examples/migrations_example.jl

# 永続的なデータベースを作成して検査
julia --project=. examples/create_test_db.jl
sqlite3 examples/test.db
```

## サンプルの出力

各サンプルは以下を表示するフォーマット済み出力を生成します:
- 生成された SQL
- クエリ結果
- ステップバイステップの実行過程

## 共通パターン

すべてのサンプルは以下のパターンに従います:

```julia
using SQLSketch          # コアクエリ構築関数
using SQLSketch.Drivers  # データベースドライバ

# データベースに接続
driver = SQLiteDriver()  # または PostgreSQLDriver()
db = connect(driver, ":memory:")
dialect = SQLiteDialect()  # または PostgreSQLDialect()
registry = CodecRegistry()

# クエリを構築
q = from(:users) |>
    where(col(:users, :age) > literal(18)) |>
    select(NamedTuple, col(:users, :id), col(:users, :name))

# クエリを実行
results = fetch_all(db, dialect, registry, q)

# クリーンアップ
close(db)
```

## データベーススキーマ

`create_test_db.jl` サンプルは以下のテーブルを作成します:

### users テーブル
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

### posts テーブル
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

## サンプルへの貢献

新しいサンプルを追加する場合:
1. 標準的な import パターンを使用: `using SQLSketch` と `using SQLSketch.Drivers`
2. サンプルを説明する docstring を含める
3. `println` で明確なセクションヘッダーを追加
4. SQL と結果の両方を表示
5. `close(db)` でリソースをクリーンアップ
6. この README を更新

## 関連情報

- [入門ガイド](../docs/src/getting-started.md)
- [チュートリアル](../docs/src/tutorial.md)
- [API リファレンス](../docs/src/api.md)

## 注意事項

- データベースファイル (`*.db`) は `.gitignore` により git から除外されています
- リポジトリをクローンした後、`test.db` を再作成する必要があります
- ほとんどのサンプルはシンプルさと移植性のために SQLite を使用しています
- PostgreSQL サンプルは PostgreSQL サーバーの起動が必要です
