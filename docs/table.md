# テーブル一覧

| No | テーブル名 | 役割 |
|----|------------|------|
| 1 | users | ユーザー情報 |
| 2 | books | 書籍マスター |
| 3 | user_books | ユーザーが登録した本の情報 |
| 4 | passbooks | 総合口座・個別口座の管理 |
| 5 | subscriptions | 課金管理 |

## 補足
- `user_books` は `users` と `books` を紐づける中間テーブル  
- `passbooks` は「読書銀行」というUI / 概念を成立させるための中核テーブル  
- `subscriptions` は有料プラン・課金状態の管理を担う
