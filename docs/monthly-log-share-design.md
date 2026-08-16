# マンスリーログ共有 設計メモ（R4.6「スクリーンショットの画像候補」）

作成日: 2026-08-16
更新日: 2026-08-16
ステータス: **オーナー確定（2026-08-16）・実装済み**
関連文書:

- `docs/implementation-roadmap.md`（R4.6 の項目定義。本書はその設計メモ）
- `docs/memo-list-design.md`（R4.6 の体裁の参照）
- `docs/r4-repository-abstraction-notes.md`（View は DTO のみ・新しいデータ層は足さない）
- `docs/agent-implementation-guide.md`
- `DESIGN_SYSTEM.md`
- 参考画像: `docs/assets/monthly-log-share/`（アプリの Assets には入れない）

---

## 目的

本棚のマンスリーカレンダーをスクリーンショットした直後に、「マンスリーログを共有」画面を開く。対象月の本・金額・カレンダーから透明 PNG を4種類作り、横スワイプで選んでコピー・写真保存・iOS 共有シートへ渡せるようにする。シミュレータではスクリーンショット通知が来ないことがあるため、各月ヘッダーの共有ボタンからも同じ画面を開ける。

## 言語方針

| 対象 | 言語 |
|------|------|
| 通常画面の月名・曜日 | 従来どおりアプリ言語へ追従 |
| 共有画像の月名・曜日 | 英語固定（DateFormatter のロケール結果に依存しない） |
| 共有画像の曜日の並び順 | `Calendar.current.firstWeekday` にだけ追従 |
| 共有画像の合計金額・冊数・通貨単位 | アプリの5言語と表示通貨へ追従 |
| 共有画面 UI（タイトル・コピー／保存／その他など） | 5言語（`Localizable.xcstrings`） |

固定文字列（共有画像専用。`MonthlyLogShareEnglishLabels`）:

- 曜日: Sun / Mon / Tue / Wed / Thu / Fri / Sat
- 正式月名: January … December
- 月略称: Jan … Dec

日曜始まり端末の曜日行は `Sun … Sat`、月曜始まり端末は `Mon … Sat / Sun`。アプリ本体の曜日・月名表示は変更しない。

## R4.6 との関係

Utils の純粋関数と、クライアント内の画像生成・写真保存・共有シート提示は許可する。**新しいデータ層抽象化、DTO、リポジトリは追加しない。** `observeBooks()` の新しい購読も作らない。集計は `BookshelfView` が既に持っている `passbookBooks` を渡す。

## 確定仕様

### 集計範囲

- 総合口座: 全口座の対象月書籍
- カスタム口座: 表示中口座の対象月書籍
- お気に入り・メモあり・つながり等の一時フィルターは適用しない
- `MonthlyMemo` の本文は含めない
- 冊数は対象月の `books.count`（同日複数冊も全冊）
- 合計金額は既存の `Collection.totalDisplayAmount(in:exchangeRates:)` を使い、現在の表示通貨に合わせる。別の金額計算は作らない

### カレンダーの週始まり

月曜固定にはしない。`Calendar.current.firstWeekday` と端末のタイムゾーンを使う。

- 日曜始まりの端末: 画面も共有画像も日曜始まり
- 月曜始まりの端末: 画面も共有画像も月曜始まり
- アプリ本体の既存カレンダーの見た目・挙動は変えない
- 共有画像用に別の暦計算を複製しない

配置ロジックは任意の `Calendar` を受け取る `MonthlyCalendarLayout` にまとめ、通常画面と共有画像が同じ結果を使う。

画面と共有画像で一致させるもの:

- 曜日の開始位置
- 月初の空白数
- 日付位置
- 月による行数
- 登録日の表紙
- 同日複数冊の代表表紙（その日の最新 `registeredAt`）
- `+N` バッジ
- 表紙なしのプレースホルダー

一致対象は曜日の開始位置・日付・表紙配置。共有画像のセルサイズや透明度は参考デザインに合わせてよい。共有画像内の月名・曜日文字は英語固定。

### 4テンプレート

カルーセル順は固定。完成出力はすべて透明背景の 9:16・1080×1920 PNG。参考画像は約 3:5 だが、出力は 9:16 へ調整する。

参考画像（設計資料。Assets.xcassets には入れない）:

1. `docs/assets/monthly-log-share/01-calendar-summary.png`
2. `docs/assets/monthly-log-share/02-vertical-month.png`
3. `docs/assets/monthly-log-share/03-large-month.png`
4. `docs/assets/monthly-log-share/04-minimal-summary.png`

| 順 | ID | 内容 |
|----|-----|------|
| 1 | `calendarSummary` | 先頭ゼロなしの月数字＋年、合計金額と冊数、英語曜日、月間カレンダー、ワードマーク。金額あり・カレンダーあり |
| 2 | `verticalMonth` | 正式英語月名を90度回転して左側へ（例: August）＋年、英語曜日、カレンダー、ワードマーク。金額なし |
| 3 | `largeMonth` | 英語月略称を大きく（例: Aug）＋年、英語曜日、カレンダー、ワードマーク。金額なし |
| 4 | `minimalSummary` | 2桁月＋年、合計金額と冊数、ワードマーク。金額あり・カレンダーなし |

全テンプレート共通:

- 1080×1920・透明 PNG
- 参考画像の相対的な配置・余白・白文字・半透明セルを尊重する
- プレビューの市松模様は出力画像へ含めない
- 月名・曜日は英語固定
- 合計金額・冊数・通貨単位はアプリ言語と表示通貨
- BookBank ワードマークは既存の `brand.bookbank` と既存ブランドフォント（Fearlessly Authentic）
- 0冊でも生成可能
- 表紙取得失敗時はプレースホルダーで生成を続ける

Fearlessly Authentic を画像へ焼き込んで外部配布できるか確認できるライセンス文書は、リポジトリ内にない。実装とテストは既存フォントで進める。ストア公開前の人間タスクとして残す。

### 共有画面

画面タイトルは「マンスリーログを共有」。iPhone では large detent 固定のボトムシート（`.presentationDetents([.large])`）。medium は置かない。背景のカレンダーが上端に少し見え、下から出てきたことが分かる。システム標準どおり背景は暗くし、背後は操作できない。閉じるのは×ボタンと下スワイプ。月別メモと共有は同じ `.sheet(item:)` の route から出し、同時には開かない。

- 閉じるボタン
- 市松模様を背景にした透明 PNG プレビュー
- 4テンプレートのページ式カルーセル。現在の9:16カードを中央に置き、次のカード本体が右端へ少なくとも28pt見える。2・3ページ目では前後のカードも少し見える
- ページドット
- おすすめ先「Instagram Stories」（文言のみ。`instagram-stories://` 直接連携は初版スコープ外。Meta app ID 登録もしない）
- コピー / 保存 / その他

プレビューと保存出力は同じテンプレート View を使う。共有画面を開いたあとに書籍データや為替レートが変わっても、4候補の内容はスナップショットで固定する。

### コピー

透明 PNG を `UIImage` としてではなく、PNG Data を `UTType.png.identifier` で `UIPasteboard` へ格納し、アルファを保持する。成功後は既存の `common.copied`（「コピーしました」）で短いフィードバックを出す。フィードバックはプレビュー画像の下端に重ね、おすすめ先「Instagram Stories」の文字にかぶせない。

### 保存

`PHPhotoLibrary` の add-only 権限で透明 PNG を写真へ保存する。

扱う状態: 未決定 / 許可済み / 拒否 / 制限 / 保存失敗 / 保存中の連打。成功時は `monthly_log_share.saved`（「保存しました」）を、コピーと同じ位置・同じ長さで出す。

拒否時は設定アプリへの導線を持つアラートを出す。`NSPhotoLibraryAddUsageDescription` を追加し、`InfoPlist.xcstrings` を新設して ja / en / ko / zh-Hans / zh-Hant の5言語で管理する。2026-08-16 のビルドで `xcstringstool compile` が `InfoPlist.xcstrings` を認識したため、別方式への切り替えは不要だった。

### その他

生成済みの透明 PNG を `UIActivityViewController` へ渡す。アルファ保持のため、一時 PNG ファイル URL または PNG Data を使う。iPad では Popover として提示する。一時ファイルは提示終了後に削除する。

### 表紙画像の解決

`ImageRenderer` の中で `LocalCoverImage` や `CachedAsyncImage` の非同期ロード完了を待たない。共有画面を開く前に `MonthlyLogShareCoverResolver` が必要な表紙を `UIImage` へ事前解決する。

優先順位:

1. キャッシュ済み画像を最優先で即時解決（手動表紙は `LocalCoverDataCache`、外部表紙は `BookCoverImageCache`）
2. 手動登録表紙のキャッシュミス時は既存 `repos.books.loadCoverImage(bookId:)`（ローカルは直列）
3. リモート取得が必要な URL だけを最大4件の上限付き並列処理。同じ URL は1回だけ取得し、該当する複数の本へ同じ画像を割り当てる
4. 取得失敗はプレースホルダーで続行（辞書に載せない）

リモート取得のテスト用クロージャは `@Sendable (URL) async -> Data?`。`UIImage` 変換とキャッシュ格納は MainActor 上で行う。`Task` のキャンセルを尊重し、カレンダーから離れたら準備 Task を止める。

準備中は `ProgressView` と `monthly_log_share.preparing`（ja / en / ko / zh-Hans / zh-Hant）を重ねて、無反応に見えないようにする。成功・失敗・キャンセルのすべてで準備中フラグを戻す。

リポジトリ・DTO・モデルへ新しい画像バイナリ項目は追加しない。

### 画像生成

`MonthlyLogShareRenderer` が SwiftUI テンプレートを `ImageRenderer` で出力する。

- 論理サイズ 360×640pt
- `scale = 3`
- 出力 1080×1920
- `isOpaque = false`
- PNG エンコード
- 背景は透明のまま

共有カレンダーのセルはアプリ画面と同じ 2:3（`MonthlyLogShareCalendarMetrics`）。表紙セル・日付付きの空セル・月初の空白セルを同じ比率にし、表紙は aspectFill を維持する。日付のないセル（月初の空白、最終週の余り）は色を塗らない。セルは枠内計算の約86%にして書影を一回り小さくする。1枚目の合計金額・冊数の両端は、縮小後のカレンダー幅に揃える。4〜6行の月すべてで枠内に収め、6行月はテンプレートごとにグリッド幅・余白・文字サイズを縮小する。日付位置、週始まり、代表表紙、`+N` は既存仕様のまま。

### スクリーンショット検知

`UIApplication.userDidTakeScreenshotNotification` を購読する。通知は撮影後に来るため、元のスクリーンショットを置き換えたり削除したりしない。

自動表示する条件（すべて満たすとき）:

- アプリが active
- `BookshelfView.showCalendarView == true`（カレンダーモード。`BookshelfChromeState.isCalendar` は Chrome 同期用の補助情報であり、これだけを正にしない）
- `BookshelfCalendarView` が実際に前面（`isCalendarInForeground`。`onAppear` / `onDisappear` で更新）
- 共有画面が未表示
- 表紙準備中でない（準備の二重開始はしない）
- 月別メモ編集シートが未表示
- 同日複数冊の `selectedDay` シートが未表示
- その他、カレンダーを覆う UI が未表示

`showCalendarView` だけでは足りない。カレンダーから別画面へ push したあとも `showCalendarView` は true のまま残るため、View が実際に前面かを別状態で持つ。次では自動表示しない。

- 1冊の日から直接開いた `UserBookDetailView`
- 同日複数冊経由で開いた詳細
- `BookSearchView`
- 別タブやその他の push 先
- 月別メモ・同日複数冊シートなど既存のモーダル

「カレンダーを覆う UI」には、月別メモシート・同日複数冊シートに加え、カレンダーから push した書籍詳細（`selectedDetailBook`）と検索登録（`searchRegistrationTarget`）も含める。

スクリーンショット通知を受けた時点だけでなく、表紙準備完了後に `MonthlyLogShareSession` を載せる直前にも前面条件を再確認する（`canCommitPreparedSession`）。カレンダーから離れたら準備 Task をキャンセルし、キャンセルされた準備結果から遅れて共有画面を出さない。判定は `MonthlyLogShareScreenshotGate` の純粋関数として固定する。

対象月は、月セクションの表示領域を PreferenceKey で測り、画面との交差面積が最大の月。同率なら画面中央へ近い月を優先する。`LazyVStack` で未レイアウトの画面外月は候補に含めない。候補が1つも無いとき（本が0冊で月セクション自体が無い等）は、端末タイムゾーンの今月を対象にする。

共有シート表示中の再スクリーンショットでは二重表示しない。閉じたあと、カレンダーでもう一度スクショすれば再表示できる。準備中はこれまでどおりカレンダー上に ProgressView を出し、完了後にシートを下から出す。

### 手動導線

各月ヘッダーに共有ボタンを追加する。既存の月別メモ編集ボタンは残す。共有ボタンはその月を明示的に対象にして同じ共有画面を開く。

## エラー・空状態

- 0冊の月でも4テンプレートを生成する（カレンダーは空セル、金額は 0）
- 表紙取得失敗はプレースホルダーで続行する
- 写真権限の拒否・制限は設定アプリへの導線付きアラート
- 保存失敗は短いエラー表示
- 保存中はボタンを無効化し、連打で二重保存しない
- コピー成功・保存成功はプレビュー上の短いフィードバック（おすすめ先の文字には重ねない）

## スコープ外

- `instagram-stories://` による Instagram Stories 直接連携
- Meta app ID 登録
- 元スクリーンショットの置き換え・削除
- カレンダーの週始まりを月曜固定へ変更
- 通常画面の月名・曜日のローカライズ変更
- 新しい `observeBooks()` 購読
- SwiftData モデル / DTO データ契約 / RepositoryProtocols / 既存リポジトリの公開契約 / 移行コード
- `ShareService` および `bookbank-share` Web リポジトリ
- 課金仕様
- 月別メモ保存仕様
- 外部依存の追加
- 完成画像を `Assets.xcassets` へ静的リソースとして入れること

## テスト

最低限:

- `MonthlyCalendarLayoutTests` — 日曜始まり / 月曜始まり、月初が各曜日、4〜6行、うるう年、同日複数冊、最新表紙の代表、`+N`、画面用と共有用が同じ配置結果
- `MonthlyLogShareEnglishLabelsTests` — 12か月の正式名と略称、7曜日、アプリロケールを変えても不変、`firstWeekday` 1 で Sun 始まり / 2 で Mon 始まり、曜日文字は固定でも日付配置は Calendar と一致
- `MonthlyLogShareSnapshotTests` — 総合口座 / カスタム口座、対象月外の除外、月初・月末、0冊・1冊、同日複数冊、価格なし、表示通貨での合計、`MonthlyMemo` 本文を保持しない
- `MonthlyLogShareRendererTests` — 4テンプレート、1080×1920、PNG デコード、アルファ保持、金額は template 1 と 4 のみ、カレンダーは 1〜3 のみ、表紙なし、0冊、月名・曜日がアプリ言語に依存しない、4〜6行の共有セルが 2:3、4行月も 1080×1920 の透明 PNG
- `MonthlyLogShareCoverResolverTests` — キャッシュ／ローカル／リモート／失敗の優先順位、同一 URL の重複取得防止、最大同時リモート取得数 4、リモートキャッシュ
- 保存・共有 — `PhotoLibrarySaving`（または同等）で許可 / 拒否 / 保存失敗 / 連打防止、コピー用 PNG Data、共有用 PNG 生成
- スクリーンショット通知はテスト内で `NotificationCenter` へ投稿し、条件判定を固定する
- `MonthlyLogShareScreenshotGate` — カレンダーが実際に前面のときだけ許可、1冊日から開いた詳細では不許可、検索や別タブでは不許可、準備完了後の再確認、キャンセル時は準備中解除かつ遅延表示なし

## R6への申し送り

- 新しい `observeBooks` 購読は作らない。`BookshelfView` から `BookDTO` を渡す接続を維持する
- `repos.books.loadCoverImage(bookId:)` が Firestore / Storage 実装へ差し替わっても、表紙生成の優先順位（キャッシュ → `loadCoverImage` → URL → プレースホルダー）はそのまま使える
- これはサーバ不関与のクライアント内画像生成であり、`ShareService` の URL 共有とは別機能
- `LocalCoverDataCache` は R4（SwiftData 期）限定の暫定配置。R6 ではキャッシュミス時の非同期フォールバックが主経路になる

## 人間タスク

- 実機のハードウェア操作でスクリーンショット検知
- Instagram Stories への貼り付け
- 透明 PNG の保持（Stories / 写真アプリ）
- 5言語での金額・冊数・通貨単位の文字収まり
- 英語固定の月名・曜日のデザイン確認
- Fearlessly Authentic の画像焼き込み配布ライセンス
- App Store 提出前の写真権限文言確認
