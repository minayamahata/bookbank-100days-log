# マンスリーログ共有 設計メモ（R4.6「スクリーンショットの画像候補」）

作成日: 2026-08-16
更新日: 2026-08-17（3枚目を正方形から4:5へ。1・2枚目は9:16、4枚目は1:1を維持）
ステータス: **オーナー確定（2026-08-17）・実装済み**
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

カルーセル順は固定。キャンバス形式はテンプレート自身が持ち、表示順の index では決めない。全テンプレートを 9:16 にはしない。X など写真の上へ重ねる素材として使い、位置とサイズは各 SNS の編集画面で調整する。

参考画像（設計資料。Assets.xcassets には入れない）:

1. `docs/assets/monthly-log-share/01-calendar-summary.png`
2. `docs/assets/monthly-log-share/03-large-month.png`
3. `docs/assets/monthly-log-share/02-vertical-month.png`
4. `docs/assets/monthly-log-share/04-minimal-summary.png`

| 順 | ID | キャンバス | 論理サイズ | 内部マスター | 内容 |
|----|-----|------------|------------|--------------|------|
| 1 | `calendarSummary` | 9:16 | 360×640 | 1080×1920 | 先頭ゼロなしの月数字＋年（縦並び。間隔 4pt。大きな月数字の行箱を相殺するため年は上余白 -18pt）、合計金額と冊数、英語曜日、月間カレンダー、ワードマーク。金額あり・カレンダーあり |
| 2 | `largeMonth` | 9:16 | 360×640 | 1080×1920 | 英語月略称を大きく（例: Aug）＋年、英語曜日、カレンダー、ワードマーク。金額なし |
| 3 | `verticalMonth` | 4:5 | 360×450 | 1080×1350 | 正式英語月名を90度回転して左側へ（例: August）＋年、英語曜日、カレンダー、ワードマーク。金額なし。360×450 のネイティブ配置（正方形の引き伸ばしや切り抜きはしない）。追加の縦 90pt は主にカレンダーと上下余白へ使う |
| 4 | `minimalSummary` | 1:1 | 360×360 | 1080×1080 | 2桁月＋年、合計金額と冊数、ワードマーク。金額あり・カレンダーなし。正方形内で月・年は上、金額・冊数は中央、ロゴは下 |

キャンバス形式（`MonthlyLogShareCanvasFormat`）:

| 形式 | 論理サイズ | 内部マスター（scale 3） | 外部PNG |
|------|------------|--------------------------|---------|
| `portrait` | 360×640 | 1080×1920・透明 | alpha > 0 の最小矩形＋四辺 24 物理pxへトリミング |
| `portraitFourFive` | 360×450 | 1080×1350・透明 | トリミングしない。1080×1350 のキャンバス全体を出力 |
| `square` | 360×360 | 1080×1080・透明 | トリミングしない。1080×1080 のキャンバス全体を出力 |

マッピング: `calendarSummary` / `largeMonth` → `portrait`。`verticalMonth` → `portraitFourFive`。`minimalSummary` → `square`。表示順を変えても形式はテンプレートに付く。

全テンプレート共通:

- 背景は透明。市松模様はプレビュー専用で、PNG には含めない
- 1・2枚目の外部PNGだけ透明余白をトリミングする。3枚目は 4:5（1080×1350）、4枚目は 1:1（1080×1080）を維持するため `MonthlyLogShareImageTrimmer` を通さない
- 完全透明マスターは出力せず失敗とする
- 参考画像の相対的な配置・余白・白文字・半透明セルを尊重する
- 月名・曜日は英語固定
- 合計金額・冊数・通貨単位はアプリ言語と表示通貨
- BookBank ワードマークはオーナー提供の `img_bookbank_logo.svg`（Fearlessly Authentic の字形）を使う。高さは 16／18pt（3枚目は 14／16pt）
- 0冊でも生成可能
- 表紙取得失敗時はプレースホルダーで生成を続ける

3枚目（`verticalMonth`）の 4:5 専用レイアウト:

- 左側に回転した正式月名と年、右側に曜日とカレンダー、下部に BookBank
- 月名が細くカレンダーが重いため、左右同じ余白だと左が広く見える。月名＋カレンダーは左右の合計余白を変えず 6pt 左へ寄せ、視覚的に中央へ置く。ロゴは中央のまま
- セルは 2:3、表紙は aspectFill。日付・代表表紙・`+N`・プレースホルダーを維持。未登録日セルは白 20%
- 日曜始まり／月曜始まり、4行・5行・6行の月すべてを 360×450 内へ収める
- 月名の基準は 34pt、年は 12pt。カレンダー行数では変えない。曜日・日付・余白・cellScale などカレンダー側の compact 調整は維持する
- 正方形から増やした縦 90pt は、主にカレンダーが使える高さと上下余白へ使う。月名や文字は無理に拡大しない
- 6行月は余白・曜日／日付フォント・gridSpacing・cellScale を調整し、セルが極端に小さくならないようにする。ロゴや曜日は消さない
- 長い月名（January / February / September）が実測で列の長さに収まらない場合だけ `MonthlyLogShareVerticalMonthMetrics.fittedFontSize` で縮小し、最小フォントを下回らない。月名ごとの例外分岐はしない
- 360×360 を scaleEffect で 360×450 へ拡大したり、縦方向だけ引き伸ばしたり、clipped で切ったりしない

4枚目（`minimalSummary`）の正方形専用レイアウト:

- 月と年を上側、合計金額と冊数を中央付近、BookBank を下側。全体は中央揃え
- 縦長用の大きな Spacer をそのまま持ち込まず、360×360 の中で余白を取り直す
- 長い金額・通貨記号・韓国語・繁体字でも左右が切れないようにする

共有画像の文字:

- 月名・曜日・年（月の隣）・カレンダー日付・`+N` は LINE Seed Sans EN（固定サイズ。Dynamic Type は掛けない）
- BookBank ワードマークは `img_bookbank_logo.svg`。文字フォントでは描かない
- 金額・冊数・単位などローカライズ文字は `snapshot.locale` に対応するフォント
- SwiftUI の描画と `UIFont` による事前計測は同じ `AppTypography.fixedUIFont` を使う
- `MonthlyLogShareCanvas` は `lineSpacing(0)` で固定する。通常 UI の日本語 `lineSpacing(1)` を継承しない。共有画面のタイトルやボタンは通常 UI の行間を使ってよい

LINE Seed の再配布・画像焼き込み条件はリポジトリ内に無い。App Store 提出前のライセンス確認は `docs/typography-design.md` の人間タスクに集約する。

### 共有画面

画面タイトルは「マンスリーログを共有」。太字にはせず、`.headline` より一段階小さい `.subheadline`（Regular）にする。iPhone では large detent 固定のボトムシート（`.presentationDetents([.large])`）。medium は置かない。背景のカレンダーが上端に少し見え、下から出てきたことが分かる。システム標準どおり背景は暗くし、背後は操作できない。閉じるのは×ボタンと下スワイプ。月別メモと共有は同じ `.sheet(item:)` の route から出し、同時には開かない。

- 閉じるボタン
- 市松模様を背景にしたプレビュー。カード外形はテンプレートのキャンバス比率に合わせる（1・2枚目は 9:16、3枚目は 4:5、4枚目は 1:1）
- プレビューは内部マスター全体の `MonthlyLogShareCanvas` をカード内へ等比縮小して表示する。トリミングしない。外部PNGはプレビューへ流用しない
- 4:5 や正方形のカードを 9:16 の市松枠へ入れない。カードの上下へ別比率用の市松余白を足さない
- コピー／保存／共有は選択中テンプレートの同一 PNG Data を使う。1・2枚目だけアルファ境界＋24物理pxへトリミングし、3枚目は 1080×1350、4枚目は 1080×1080 のまま
- 4テンプレートのページ式カルーセル。全ページで同じカード幅を使い、高さだけ比率で変える。現在の9:16カードを基準幅にする。3・4枚目はカルーセル全体ではなく、1・2枚目の9:16カードに対して縦中央へ置く。次のカード本体が右端へ少なくとも28pt見える。2・3ページ目では前後のカードも少し見える
- ページドット
- おすすめ先「Instagram Stories」（文言のみ。`instagram-stories://` 直接連携は初版スコープ外。Meta app ID 登録もしない）
- コピー / 保存 / その他

プレビューと外部出力は同じ `MonthlyLogShareCanvas` を描画元とする。プレビューは内部マスター全体、外部出力はテンプレート形式に応じてトリミング有無を分ける。PNG 生成完了前後でプレビューのサイズや位置は変わらない。共有画面を開いたあとに書籍データや為替レートが変わっても、4候補の内容はスナップショットで固定する。

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

`MonthlyLogShareRenderer` が SwiftUI テンプレートを `ImageRenderer` でマスター描画する。トリミングは `portrait` だけ `MonthlyLogShareImageTrimmer` を通す。

- 論理サイズとマスター画素は `template.canvasFormat` に従う（9:16 は 360×640 / 1080×1920、4:5 は 360×450 / 1080×1350、1:1 は 360×360 / 1080×1080）
- `scale = 3`
- `isOpaque = false`
- 背景は透明のまま
- 1・2枚目のエクスポートはマスターを再描画せず、アルファ境界＋24px で切り出した可変サイズ PNG
- 3枚目は 1080×1350、4枚目は 1080×1080 のマスターをそのまま PNG 化する。一度トリミングして余白を足し直さない
- コピー・写真保存・iOS 共有シートは選択中テンプレートの同一 PNG Data を使う

共有カレンダーのセルはアプリ画面と同じ 2:3（`MonthlyLogShareCalendarMetrics`）。表紙セル・日付付きの空セル・月初の空白セルを同じ比率にし、表紙は aspectFill を維持する。日付のないセル（月初の空白、最終週の余り）は色を塗らない。本が登録されていない日付セルの背景は白 20%（`Color.white.opacity(0.20)`）。アプリ本体のカレンダー色は変えない。セルは枠内計算の約86%にして書影を一回り小さくする。1枚目の合計金額・冊数の両端は、縮小後のカレンダー幅に揃える。4〜6行の月すべてで枠内に収め、6行月はテンプレートごとにグリッド幅・余白・文字サイズを縮小する。日付位置、週始まり、代表表紙、`+N` は既存仕様のまま。

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
- `MonthlyLogShareImageTrimmerTests` — 不透明矩形の検出、24px 余白、端でのクランプ、半透明を含む、完全透明は失敗、ピクセル形式の正規化、クロップ後のアルファと非スケール
- `MonthlyLogShareRendererTests` — キャンバス形式（9:16／4:5／1:1）、内部マスターは portrait 1080×1920 / portraitFourFive 1080×1350 / square 1080×1080、1・2枚目はトリミング済み、3枚目は 1080×1350 維持、4枚目は 1080×1080 維持、透明保持、市松を含めない、金額は template 1 と 4 のみ、カレンダーは 1〜3 のみ、表紙なし、0冊、月名・曜日がアプリ言語に依存しない、4〜6行の共有セルが 2:3、4:5 の verticalMonth が 4〜6行で収まる、長い英語月名、LINE Seed の計測と描画の一致
- `MonthlyLogSharePreviewMetricsTests` — portrait は 9:16、portraitFourFive は 4:5、square は 1:1、カード幅は同じ、4:5 の height は width×5/4、利用可能領域を超えない、0以下でクラッシュしない
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
- 実機の X で 2:3 写真へ重ね、以前より大きくピンチアウトできること
- Instagram Stories への貼り付け・拡大・移動
- 透明 PNG の保持（Stories / 写真アプリ）
- 1・2枚目が 9:16、3枚目が 4:5、4枚目が 1:1 に見えること。3枚目に 9:16 や 1:1 用の市松余白が付かないこと
- 4〜6行月の3枚目、12か月の月名、February と August の月名サイズ、写真アプリで 3枚目が 1080×1350・4枚目が 1080×1080
- 4テンプレートで文字・影・表紙が切れていないこと
- コピー、保存、その他の3経路で同じ見た目になること
- 5言語での金額・冊数・通貨単位の文字収まり
- 英語固定の月名・曜日のデザイン確認
- App Store 提出前の写真権限文言確認
