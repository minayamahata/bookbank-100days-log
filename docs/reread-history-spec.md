# BookBank 再読履歴 仕様書

作成日: 2026-08-17
更新日: 2026-08-18（通帳の再読行は「再読」の左にテーマ色の丸＋`icn_repeat`。読書履歴の●と縦棒は透過なしの `Color.primary`。同日の再読は1件ずつ消す。詳細の「再読を記録」を削除。追加は検索、日付変更・削除は編集画面。読書履歴は詳細情報の上の別枠、初回表記は登録日）／2026-08-17（R4.7 / v1.7.0 初版）
ステータス: 実装完了（R4.7 / v1.7.0。残るのは人間タスク）
関連文書: `docs/implementation-roadmap.md` / `docs/cloud-migration-architecture.md` 3章 / `docs/r4-repository-abstraction-notes.md` / `docs/monthly-log-share-design.md` / `docs/agent-implementation-guide.md`

> **AI実装エージェントへ**: `docs/agent-implementation-guide.md` を先に読むこと。
> **確定判断**: (1) 別 `@Model` は作らず、`UserBook` に Codable 配列 `rereads` を足す。(2) 再読の追加・編集・削除では `updatedAt` を動かさない。(3) リポジトリの正準ソート `fetchSorted()` は変えない。(4) 過去の重複本は自動統合しない。(5) `N0SpikeExport.swift` は触らない。

---

## 1. 目的と位置づけ

**1冊の本に、初回読了日と複数の再読日を持たせる。** 本棚の書影は1つのまま、通帳・カレンダー・統計・口座集計・口座Markdown・マンスリーログ共有は読書回数分を冊数・金額に加算する。

同じ本を検索から再度登録しようとしたときは、新しい `UserBook` を作らず、既存本へ再読履歴を足す。意図しない二重登録（accidental duplicate）は従来どおり防ぐ。

リリース位置づけは **R4.7 / v1.7.0**。スキーマ変更があるため R4.6（View層完結のUIパッチ枠）には入れない。R6（クラウド移行）の前に独立リリースする。

---

## 2. データモデル

### 2.1 `RereadRecord`

`Codable` / `Hashable` / `Sendable` な struct。別 `@Model` にはしない。

| プロパティ | 型 | 説明 |
|---|---|---|
| `id` | `String` | UUID文字列。再読1件の安定ID |
| `date` | `Date` | 再読日 |

### 2.2 `UserBook`

```
var rereads: [RereadRecord]? = nil
```

- `= nil` を明示する。軽量移行・バックフィルは不要
- `nil` は履歴なし。旧ストアを新スキーマで開いた既存行も `nil`
- 再読自体に口座IDは持たない。本を別口座へ移すと履歴も一緒に移る

### 2.3 `BookDTO`

```
var rereads: [RereadRecord] = []
```

- デフォルト付きのため、既存の `BookDTO(...)` 構築箇所は原則変更しない
- モデルの `nil` は DTO では空配列として扱う

派生値（extension）:

| 名前 | 意味 |
|---|---|
| `allReadingDates` | `registeredAt` ＋各再読日 |
| `readCount` | `1 + rereads.count` |
| `latestReadDate` | `allReadingDates` の最大 |

### 2.4 マッピング

- モデル → DTO: `rereads` を読み出す（`nil` → `[]`）
- 通常の DTO → モデル更新 `apply(_:to:)`: **`rereads` に触れない**（`uuid`・`coverImageData` と同じ）。古い DTO で `updateBook` しても、専用APIで足した履歴を消さない
- `addBook`: 履歴付き DTO を受けたらそのまま保存する

### 2.5 `updatedAt`

再読の追加・編集・削除では `updatedAt` を変更しない。お気に入り・メモと同じ扱い。R6 の LWW 見直し対象として `docs/r4-repository-abstraction-notes.md` 10.3節へ申し送る。

### 2.6 `Passbook.bookCount` / `totalValue`

モデル層の計算値。View からは未使用（参照は `DataPersistenceTests` のみ）。**ユニーク本ベースのまま変更しない。** 将来の誤用を防ぐため、回数集計は `ReadingTally` を使う。

---

## 3. リポジトリAPI

`BookRepository` に次を追加する。成功時は既存の `saveAndNotify()` 相当で購読ストリームを再送する。`fetchSorted()` の正準ソート（`registeredAt` 降順 → `createdAt` 降順）は変えない。

| API | 失敗 |
|---|---|
| `addReread(bookId:date:)` | 本なし → `bookNotFound`。日付範囲外 → `invalidRereadDate` |
| `updateReread(bookId:rereadId:date:)` | 本なし → `bookNotFound`。履歴なし → `rereadNotFound`。日付範囲外 → `invalidRereadDate` |
| `deleteReread(bookId:rereadId:)` | 本なし → `bookNotFound`。履歴なし → `rereadNotFound`。一致する ID の先頭1件だけ消す（同日の他の再読は残す） |

削除系の本 not-found は既存どおり冪等（`deleteBook` は return）。再読削除の履歴 not-found は更新系に合わせ throw する。`addReread` は既存 ID と衝突したら採番し直す。

---

## 4. 日付

`Calendar.current` の日単位で検証する。クランプしない。

- 許可範囲: 初回登録日の日 〜 今日の日
- 範囲外は `invalidRereadDate` を throw
- 初回と同日の再読を許可する
- 同日複数回の再読を許可する
- 初回登録日の編集上限: `min(最初の再読日, 今日)`

---

## 5. occurrence と並び順

`Utils/ReadingTally.swift` に `BookReadingOccurrence` を置く。View に判定を書かない。

| 項目 | 値 |
|---|---|
| 持つもの | 本、読書日、初回／再読区分、安定ID |
| 初回ID | `bookId:initial` |
| 再読ID | `rereadId` |
| 表示順 | 日付降順。同じ暦日は初回を先。初回同士は既存の正準順。再読同士はID昇順 |

本棚だけ View 側で `latestReadDate` 降順に派生ソートする。同値なら既存順（正準ソート）を維持する。

金額は各 occurrence に、その本の同じ `priceAtRegistration` と `currencyCode` を適用する。価格未設定は 0 円。

---

## 6. 画面別の集計単位

### 6.1 回数ベース（occurrence）

| 画面 | 内容 |
|---|---|
| 通帳ヘッダー・行 | `PassbookDetailView`。行・通し番号・金額を occurrence 基準。行タップは同じ本の詳細へ。再読行は「再読」の左にテーマ色の丸（16pt）＋`icn_repeat`。丸とアイコンの色は展開時＋ボタンと同じ（黒テーマ＋ダークは白丸に黒アイコン） |
| カレンダー | `BookshelfCalendarView`。日別配置・`+N`・月ヘッダー |
| 統計 | `StatisticsView` の年間・月別・口座サマリー。`availableYears` は全読書日から算出 |
| 年別お気に入り・メモ数 | その年に1回以上読んだユニーク本数 |
| 口座一覧 | `AccountListView` の冊数・金額 |
| 口座リスト行 | `PassbookListView` の冊数・金額 |
| 口座Markdown | 見出しの冊数・合計。title-only はユニーク本1行のまま `タイトル ×N`。detailed は初回登録日＋各再読日。`EditPassbookView` のプレビューも同じ |
| マンスリーログ共有 | 対象月の occurrence。冊数・金額・日別表紙・`+N`。初回が月外でも再読が月内なら含める。同月複数回は回数分 |

### 6.2 ユニーク本ベース（据え置き）

| 対象 | 理由 |
|---|---|
| 本棚フィルター件数 | 「何冊持っているか」 |
| `ReadingListView` / `ReadingListDetailView` | リストは本の所属 |
| `ShareService` | 共有冊数はサーバー側で配列長から決まる契約。据え置きなら Web 変更不要 |
| 口座削除警告 | 削除される実冊数 |
| 読了リストMarkdown | 従来どおり |
| `Passbook.bookCount` / `totalValue` | View 未使用のモデル計算値。変更しない |

---

## 7. 登録導線

既存の同一本判定を使う。ISBN があれば ISBN。ISBN なしはタイトル＋著者の完全一致。

複数の既存重複がある場合の追加先（自動統合はしない）:

1. `registeredAt` 昇順
2. `createdAt` 昇順
3. `id` 昇順

判定は純関数に切り出す。

検索画面:

- 登録済み行をタップ可能にし、対象本の口座名を含む再読確認を出す
- 確認後、今日の日付で `addReread`
- ISBN／バーコードの1件ヒットでも、登録済みなら同じ確認を出す。未登録は従来どおり自動登録
- 検索結果ID単位の in-flight Set を持ち、新規登録・再読追加の await 中は該当操作を無効化する
- 新規保存待機中に別処理で登録済みになった場合は保存を中止する。自動で再読へ変換しない

---

## 8. 画面

- `UserBookDetailView`: 読書履歴を詳細情報の上の別枠にする。見出しは「読書履歴」。行は表示のみ（登録日＋各再読日）。初回行のラベルは「登録日」（詳細情報側の登録日行は出さない）。日付の左に6ptの塗り円と縦線の時系列マーカーを置く（円と線は同じ `Color.primary`。透過なし。アイコン・横罫線はなし）。「再読を記録」は置かない。追加は検索の再読確認、日付変更・削除は編集画面
- `EditBookView`: 「登録口座」はフォーム最上部。登録日の上限を `min(最初の再読日, 今日)`。再読の日付変更と確認付き削除はここでのみ行う。「読書履歴」見出しは出さない。削除は画面上の1行だけを外し、保存時はその行の ID だけを `deleteReread` する（日付一致や配列差分では消さない）。再読だけの保存では `updateBook` せず、専用APIだけを呼ぶ（`updatedAt` を動かさない）
- `BookCoverView`: 再読マークは出さない。右下のメモ・お気に入り HStack は変更しない

---

## 9. マンスリーログ共有

通常画面と共有画像で `MonthlyCalendarLayout` を共用する。入力を `BookReadingOccurrence` にする。

- `MonthlyLogShareSnapshot` は対象月の occurrence を持つ
- 表紙読み込み用の本はユニークな `BookDTO` 配列として持つ
- 冊数・金額・日別表紙配置・`+N` はすべて occurrence ベース
- 初回が対象月外でも、再読が対象月内なら共有画像へ含める
- 同じ本を同月に複数回読んだ場合は回数分の冊数・金額

詳細なテンプレート寸法は `docs/monthly-log-share-design.md` が正。集計単位だけ本仕様が上書きする。

---

## 10. 対象外

- 過去の重複 `UserBook` の自動統合
- リポジトリ正準ソートの変更
- `N0SpikeExport.swift` の入力スキーマ変更（R5まで凍結）
- `Passbook.bookCount` / `totalValue` の回数化
- 読了リスト・共有・本棚フィルター件数・口座削除警告の回数化
- `updatedAt` の自動更新（R6 の LWW 見直しまで触らない）
- Web 側（`bookbank-share`）の変更

---

## 11. 人間タスク

- 新規文字列5言語の訳レビュー
- TestFlight / 実機での旧スキーマ → 新スキーマ移行確認
- 受け入れ: 2回目の登録後も本棚の書影は1つ（再読マークなし）、通帳2行、カレンダー／マンスリーログ共有／月別統計は2回分、金額は2回分。再読日の変更で対象月と本棚順が移動。削除で1回分だけ戻る
