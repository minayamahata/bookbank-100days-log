# テーブル定義書ß

## users

### テーブル概要

| 項目 | 内容 |
|---|---|
| テーブル名 | users |
| 役割 | ユーザーを一意に識別する |
| 備考 | 認証は外部サービスを利用 |

### カラム定義

| No. | カラム | データ型 | PK | NULL可 | FK | 説明 |
|---:|---|---|:--:|:--:|---|---|
| 1 | id | UUID | ○ | NO |  | ユーザーID（主キー） |
| 2 | created_at | datetime |  | NO |  | 作成日時 |
| 3 | updated_at | datetime |  | NO |  | 更新日時 |

---

## user_books

### テーブル概要

| 項目 | 内容 |
|---|---|
| テーブル名 | user_books |
| 役割 | ユーザーが登録した書籍の情報 |
| 備考 | 同一ユーザー × 同一書籍は1件のみ |

### カラム定義

| No. | カラム | データ型 | PK | NULL可 | FK | 説明 |
|---:|---|---|:--:|:--:|---|---|
| 1 | id | UUID | ○ | NO |  | 主キー |
| 2 | user_id | UUID |  | NO | users.id | ユーザー |
| 3 | book_id | UUID |  | NO | books.id | 書籍 |
| 4 | passbook_id | UUID |  | NO | passbooks.id | 所属口座 |
| 5 | memo | text |  | YES |  | メモ |
| 6 | is_favorite | boolean |  | NO |  | お気に入り |
| 7 | price_at_registration | int |  | YES |  | 登録時点の価格 |
| 8 | registered_at | datetime |  | NO |  | 登録日時 |
| 9 | created_at | datetime |  | NO |  | 作成日時 |
|10 | updated_at | datetime |  | NO |  | 更新日時 |

**制約**
- UNIQUE: `(user_id, book_id)`

---

## books

### テーブル概要

| 項目 | 内容 |
|---|---|
| テーブル名 | books |
| 役割 | 書籍マスター |
| 備考 | API検索・手動入力で登録された書籍を一元管理 |

### カラム定義

| No. | カラム | データ型 | PK | NULL可 | FK | 説明 |
|---:|---|---|:--:|:--:|---|---|
| 1 | id | UUID | ○ | NO |  | 書籍ID（主キー） |
| 2 | title | string |  | NO |  | 書籍タイトル |
| 3 | author | string |  | YES |  | 著者名 |
| 4 | isbn | string |  | YES |  | ISBN（あれば） |
| 5 | publisher | string |  | YES |  | 出版社 |
| 6 | published_year | int |  | YES |  | 出版年 |
| 7 | price | int |  | YES |  | 定価 |
| 8 | thumbnail_url | string |  | YES |  | 表紙画像URL |
| 9 | source | string |  | NO |  | 登録元（api / manual） |
|10 | created_at | datetime |  | NO |  | 作成日時 |
|11 | updated_at | datetime |  | NO |  | 更新日時 |

---

## passbooks

### テーブル概要

| 項目 | 内容 |
|---|---|
| テーブル名 | passbooks |
| 役割 | ユーザーの口座（総合・個別）を管理 |
| 備考 | ユーザーごとに総合口座は必ず1件存在する |

### カラム定義

| No. | カラム | データ型 | PK | NULL可 | FK | 説明 |
|---:|---|---|:--:|:--:|---|---|
| 1 | id | UUID | ○ | NO |  | 口座ID（主キー） |
| 2 | user_id | UUID |  | NO | users.id | ユーザーID |
| 3 | name | string |  | NO |  | 口座名（総合口座 / 漫画 / 仕事など） |
| 4 | type | string |  | NO |  | 口座種別（overall / custom） |
| 5 | sort_order | int |  | NO |  | 表示順 |
| 6 | is_active | boolean |  | NO |  | 有効フラグ |
| 7 | created_at | datetime |  | NO |  | 作成日時 |
| 8 | updated_at | datetime |  | NO |  | 更新日時 |

**制約**
- UNIQUE: `(user_id, name)`


## subscriptions

### テーブル概要

| 項目 | 内容 |
|---|---|
| テーブル名 | subscriptions |
| 役割 | ユーザーの課金状態を管理する |
| 備考 | 課金処理は外部サービスを利用 |

### カラム定義

| No. | カラム | データ型 | PK | NULL可 | FK | 説明 |
|---:|---|---|:--:|:--:|---|---|
| 1 | id | UUID | ○ | NO |  | サブスクリプションID |
| 2 | user_id | UUID |  | NO | users.id | ユーザーID |
| 3 | plan | string |  | NO |  | プラン種別（free / pro など） |
| 4 | status | string |  | NO |  | 状態（active / canceled / trial など） |
| 5 | started_at | datetime |  | NO |  | 利用開始日時 |
| 6 | ended_at | datetime |  | YES |  | 利用終了日時 |
| 7 | created_at | datetime |  | NO |  | 作成日時 |
| 8 | updated_at | datetime |  | NO |  | 更新日時 |

**制約**
- UNIQUE: `(user_id, status = 'active')`
