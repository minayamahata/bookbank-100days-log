# メモ一覧ページ設計メモ（R4.6「メモのノートページ」）

作成日: 2026-08-15
ステータス: **オーナー確定（2026-08-15）・実装済み**
関連文書:

- `docs/implementation-roadmap.md`（R4.6 の項目定義。本書はその設計メモ）
- `docs/memo-tagging-design.md`（`[[ ]]` 装飾の対象範囲。一覧は着色しない）
- `docs/r4-repository-abstraction-notes.md`（`observeBooks()` / `latestSnapshot`）
- `docs/agent-implementation-guide.md`

---

## 目的

本に書いたメモ（`UserBook.memo`）だけを一覧する独立ページを置き、「言葉のリストから本に辿れる」ようにする。表紙・タイトル・著者は出さない。メモ本文だけを見せ、タップでその本の詳細へ戻る。

## 導線

総合口座のアクションボタン「口座管理」を「メモ一覧」へ差し替える。

- 遷移先: `PassbookActionDestination.memos` → `MemoListView`
- ラベル: `passbook.view_memos`
- アイコン: SF Symbol `quote.opening`

`AccountListView` は残す。口座タブ（タブ0）と、口座切り替えメニュー最下部の「口座一覧」から引き続き到達できる。

## データ取得

View層は `@Model` / `@Query` を使わない。`repos.books.observeBooks()` を購読し、初回yield前は `repos.books.latestSnapshot` で埋める（既存画面と同じ `hasResolvedBooks` 判定）。新しい抽象化は追加しない。

対象は `UserBook.memo` のみ。`MonthlyMemo` は含めない。

## プレーンテキスト化の規則

新しいパーサは作らない。既存の `MemoPlainText.stripped(from:)` をそのまま使う。

- `[[ ]]`・`**`・行頭の `> ` を隠す
- `p.数字` は数字ごと取り除く
- `MemoFormattedText` は使わない（装飾は描画しない）

処理順は固定する。

1. `memo != nil && !memo.isEmpty`
2. `MemoPlainText.stripped(from:)` でプレーン化
3. プレーン化後が空白・改行だけなら除外
4. 表示にはトリミング前のプレーン化結果を使う

## 並び順

`observeBooks()` の正準順を維持する。再ソートしない。

- `registeredAt` 降順
- 同値時は `createdAt` 降順

## カードと空状態

- 背景: `Color.appGroupedBackground`
- 1冊1枚のカード（角丸12・`Color.appCardBackground`・境界線 `Color.primary.opacity(0.1)` 幅0.5）
- 本文は `.subheadline` / `.primary` / 左寄せ / 全文表示（`lineLimit` なし）

初回データ受信前は空状態を出さず、透明な領域だけを置く（ローディング表示はなし）。受信後に該当メモが0件なら、中央に `quote.opening` と `memo.list.empty` を出す。

## 詳細画面への遷移

カードをタップすると `selectedBook` に対象の `BookDTO` を入れ、`UserBookDetailView` へ push する。一覧からの直接編集はしない。

## スコープ外

- 装飾レンダリング / `MemoFormattedText`
- 新しいメモパーサ・書式除去関数
- 検索・絞り込み・並び替えUI
- 一覧からの直接編集
- `MonthlyMemo` / メモのブロック単位分割
- スキーマ・DTO・リポジトリ・移行コードの変更
- `AccountListView` の削除

## R6への申し送り

`MemoListView` は初回表示補完に `repos.books.latestSnapshot` を使用する。これはSwiftData期限定の暫定APIであるため、R6で書籍購読をFirestoreのスナップショットリスナーへ置き換える際は、この画面も解体・追従対象に含める。R4.6では新しい抽象化を追加しない。
