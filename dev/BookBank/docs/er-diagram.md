# ER図

![ER Diagram](./er-diagram.png)

## 補足メモ

- users を起点にすべてのデータが紐づく
- user_books は「ユーザー × 書籍 × 口座」を表す中間テーブル
- passbooks はユーザーごとに必ず1つ overall が存在
- subscriptions は参照専用（外部課金連携前提）
