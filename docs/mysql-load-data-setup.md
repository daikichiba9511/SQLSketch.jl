# MySQL LOAD DATA LOCAL INFILE セットアップガイド

SQLSketchでMySQLの最速バルクインサート（LOAD DATA LOCAL INFILE）を有効化する方法。

## TL;DR - 現状

- **現在の性能:** 70-85K rows/sec (multi-row INSERT)
- **目標性能:** 300-500K rows/sec (LOAD DATA enabled)
- **必要な設定:** サーバー + クライアント両方
- **現状の問題:** MySQL.jlのクライアント設定が機能していない可能性
- **推奨:** 現在のmulti-row INSERTのまま使用（十分高速、設定不要）

---

## LOAD DATA LOCAL INFILEとは

MySQLの高速バルクローディング機能。PostgreSQLのCOPY FROM STDINに相当。

### 利点
- 300-500K rows/sec の超高速スループット
- クライアント側ファイルから直接ロード
- SQL解析オーバーヘッドなし

### 欠点
- サーバーとクライアント両方で有効化が必要
- セキュリティリスク（ローカルファイルアクセス）
- 環境によっては設定不可（managed DB等）

---

## 有効化手順

### ステップ1: MySQLサーバー側の設定

#### 方法A: 一時的に有効化（再起動で無効に戻る）

```sql
SET GLOBAL local_infile=1;
```

#### 方法B: 永続的に有効化

**my.cnf / my.ini に追加:**

```ini
[mysqld]
local-infile=1
```

**場所:**
- Linux: `/etc/mysql/my.cnf` または `/etc/my.cnf`
- macOS: `/usr/local/mysql/my.cnf`
- Windows: `C:\ProgramData\MySQL\MySQL Server 8.0\my.ini`
- Docker: `/etc/mysql/conf.d/custom.cnf` (ボリュームマウント)

**Docker Composeの例:**

```yaml
services:
  mysql:
    image: mysql:8.0
    command: --local-infile=1
    environment:
      MYSQL_ROOT_PASSWORD: secret
```

#### 確認

```sql
SHOW GLOBAL VARIABLES LIKE 'local_infile';
-- +---------------+-------+
-- | Variable_name | Value |
-- +---------------+-------+
-- | local_infile  | ON    |
-- +---------------+-------+
```

### ステップ2: MySQLクライアント側の設定（Julia/MySQL.jl）

**現在の実装（試験的）:**

```julia
using SQLSketch

# enable_local_infile=true で接続
conn = connect(MySQLDriver(), "localhost", "mydb";
              user="root",
              password="secret",
              enable_local_infile=true)  # ← これを追加
```

**内部実装:**

```julia
# src/Drivers/mysql.jl
conn = DBInterface.connect(MySQL.Connection, host, user, password;
                          db=db,
                          port=port,
                          local_files=true)  # ← MySQL.jlの local_files パラメータ
```

**問題:** MySQL.jlの`local_files`パラメータが正しく機能しない可能性があります。

### ステップ3: 動作確認

```julia
using SQLSketch
using SQLSketch.Core: insert_batch, CodecRegistry

driver = MySQLDriver()
dialect = MySQLDialect()
registry = CodecRegistry()

conn = connect(driver, "localhost", "mydb";
              user="root",
              password="secret",
              enable_local_infile=true)

# テストデータ
rows = [(id=i, name="User $i") for i in 1:1000]

# バッチインサート実行
result = insert_batch(conn, dialect, registry, :test_table,
                     [:id, :name], rows)

# 成功メッセージ（警告なし）なら LOAD DATA が動作
# 警告が出たら multi-row INSERT にフォールバック
```

**成功の場合:**
```
# 警告なし、300-500K rows/sec のスループット
```

**フォールバックの場合:**
```julia
┌ Warning: LOAD DATA LOCAL INFILE is disabled. Falling back to multi-row INSERT...
# 70-85K rows/sec のスループット（それでも十分高速）
```

---

## トラブルシューティング

### エラー1: "Loading local data is disabled"

**原因:** サーバー側で`local_infile`が無効

**解決策:**
```sql
SET GLOBAL local_infile=1;
```

### エラー2: "Load data local infile forbidden"

**原因:** クライアント側で LOAD DATA が許可されていない

**解決策（現在調査中）:**

MySQL.jlの制限により、クライアント側の設定が正しく機能していない可能性があります。

**回避策:**
- SQLSketchは自動的にmulti-row INSERTにフォールバックします
- 70-85K rows/sec は実用的に十分高速です

### エラー3: "The used command is not allowed"

**原因:** MySQLサーバーがLOAD DATA LOCAL INFILEを完全に無効化

**解決策:**
- Managed DBサービスでは有効化できない場合があります
- SQLSketchの自動フォールバックをそのまま使用してください

---

## MySQL.jlの制限について

### 現状

MySQL.jlパッケージは`local_files`パラメータをサポートしていますが、正しく動作しない可能性があります。

**関連コード（MySQL.jl）:**
```julia
function clientflags(;
    local_files::Bool=false,  # Allows LOAD DATA LOCAL statements
    # ...
)
```

### 代替案

1. **C APIレベルでの設定（高度）**
   ```c
   // libmysqlclient で設定
   mysql_options(conn, MYSQL_OPT_LOCAL_INFILE, &enable);
   ```

2. **MySQL.jlへの貢献**
   - GitHub Issue作成
   - Pull Request提出
   - ドキュメント改善

3. **現実的な選択**
   - **multi-row INSERTのまま使う** ← 推奨
   - 70-85K rows/sec は十分実用的
   - 設定不要で確実に動作

---

## パフォーマンス比較

| 方式 | スループット | 設定 | 互換性 |
|------|-------------|------|--------|
| Individual INSERT | ~750 rows/s | 不要 | ◎ 全環境 |
| Multi-row INSERT | 70-85K rows/s | 不要 | ◎ 全環境 |
| LOAD DATA (目標) | 300-500K rows/s | 必要 | △ 限定的 |

**実測値（1,000行）:**
- Individual INSERT: 1,319 ms
- Multi-row INSERT: 7.3 ms ← **現在の実装**
- LOAD DATA (推定): 2-3 ms

**スピードアップ:**
- Multi-row vs Individual: **180倍**
- LOAD DATA vs Multi-row: 2-3倍（追加改善）

---

## 推奨事項

### 開発環境

```julia
# デフォルト設定で使用（設定不要）
conn = connect(MySQLDriver(), "localhost", "mydb"; user="root", password="secret")
result = insert_batch(conn, dialect, registry, :users, [:id, :email], users)
# → 自動的にmulti-row INSERT（70-85K rows/sec）
```

### 本番環境

**オプション1: そのまま使う（推奨）**
- 設定不要
- 70-85K rows/sec で十分高速
- 確実に動作

**オプション2: LOAD DATAに挑戦**
- サーバー側: `SET GLOBAL local_infile=1`
- クライアント側: MySQL.jlの対応待ち
- 成功すれば 300-500K rows/sec

### 最適なチャンクサイズ

**Multi-row INSERT使用時:**
```julia
# チャンクサイズ最適化
result = insert_batch(conn, dialect, registry, :users, columns, rows;
                     chunk_size=100)  # 小さめが最適
```

**チャンクサイズの影響（10,000行）:**
- 100行: 55ms ← **最速**
- 500行: 60ms
- 1,000行: 87ms
- 2,000行: 137ms

---

## まとめ

### 現在の状態

✅ **Multi-row INSERT実装完了**
- 70-85K rows/sec の高速スループット
- 50-180倍の高速化
- ゼロ設定で動作
- 全環境で互換性あり

⏳ **LOAD DATA実装済みだが未稼働**
- コード実装済み（自動検出）
- MySQL.jlのクライアント設定が課題
- サーバー側設定は可能
- 動作すれば 300-500K rows/sec

### 次のステップ

**ユーザー向け:**
1. そのままmulti-row INSERTを使う（推奨）
2. サーバー側で`local_infile=1`を設定してみる
3. LOAD DATAが動作したら報告してください！

**開発者向け:**
1. MySQL.jlのIssue/PRで`local_files`パラメータ改善を提案
2. C APIレベルでの`MYSQL_OPT_LOCAL_INFILE`設定を調査
3. 成功事例があればドキュメント更新

---

**最終更新:** 2025-12-21
**SQLSketch バージョン:** Development (MySQL Phase 13 complete)
