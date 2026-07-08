# バグレビュー一覧（2026-07-06 実施）

v1.3.0 リリース後の全コードレビューで見つかった不具合の一覧。
対象: iOS アプリ（`dev/BookBank/BookBank`）＋ Vercel プロキシ（別リポジトリ `bookbank-share`）。

- **優先度**: 高＝金額の誤表示・データ不整合・クラッシュ級 ／ 中＝機能不全・状況次第で顕在化 ／ 低＝限定的・軽微
- **状態**: ✅ 修正済み ／ ⬜ 未対応

> **AI実装エージェントへ**: `docs/agent-implementation-guide.md` を先に読むこと。各バグの対応リリースは `docs/implementation-roadmap.md` 第3章の割り当て表に従う（推奨対応順より優先）。修正したら本書の状態列を更新すること。

---

## グループA: 検索（非同期・ページング）

| # | 優先度 | 状態 | 内容 | 場所 |
|---|--------|------|------|------|
| A-1 | 高 | ✅ 修正済み (2026-07-08) | 検索中に別キーワードで再検索すると、遅れて返った古いタスクの結果が新しい結果を上書きする（Task のキャンセル・世代管理なし）。`loadMoreResults` / `enrichFormatsInBackground` も同様で、別クエリのページが混入し得る。→ `searchGeneration` カウンター導入・全4フローで await 後に世代照合・新検索時に旧Taskをキャンセル・`loadMoreResults` は `currentPage` 先行インクリメント廃止（R2ステップ2） | `Views/BookSearchView.swift` `performSearch` / `loadMoreResults` / `searchByISBN` / `enrichFormatsInBackground` |
| A-2 | 高 | ✅ 修正済み (2026-07-08) | ISBN 検索（バーコード）後に `currentPage` / `canLoadMore` / `isLoadingMore` がリセットされない。直前のキーワード検索の続きページを ISBN で取得してしまう。→ `beginNewSearch(canLoadMore: false)` で一元リセット（R2ステップ1） | `Views/BookSearchView.swift` `searchByISBN` |
| A-3 | 中 | ⬜ | 発行形態フィルター中にバックグラウンドの形態補完が完了すると `updateFilteredResults()` で全件再ソートされ、「もっと読み込む」で末尾に追加したページ順序が崩れる | `Views/BookSearchView.swift` `enrichFormatsInBackground` 内のフィルター分岐 |
| A-4 | 中 | ⬜ | キーワード検索の API エラー（429・ネットワーク断など）が「見つかりませんでした」表示になる。エラーと 0 件の区別がない | `Views/BookSearchView.swift` `performSearch` の catch と空状態 UI |
| A-5 | 中 | ⬜ | 楽天でローカルのキーワード絞り込み後 0 件でも `hasMorePages` が true のままになり、空の結果で「もっと読み込む」が出続けることがある（自動読み込みは上限 5 ページで停止） | `Services/RakutenBooksService.swift` `performRequest` |
| A-6 | 低 | ⬜ | 「もっと読み込む」失敗→再試行時、ISBN なし書籍（Google に多い）は重複排除が効かず `searchResults` に二重追加され得る | `Views/BookSearchView.swift` `loadMoreResults` の重複排除 |
| A-7 | 低 | ✅ 修正済み (2026-07-08) | 新しい検索開始時に `isLoadingMore` / `isAutoLoadingForFilters` をリセットしない（A-1 と同根）。→ `beginNewSearch()` に集約（`isSearchingByISBN` 残存も同時解消。R2ステップ1）。世代管理本体（A-1）はステップ2 | `Views/BookSearchView.swift` `performSearch` |
| A-8 | 低 | ⬜ | Google の `hasMorePages` が `totalItems` を照合せず、総件数が 20 の倍数ちょうどのとき空ページを 1 回余分に取得する | `Services/GoogleBooksService.swift` `performRequest` |

## グループB: 通貨・金額表示

| # | 優先度 | 状態 | 内容 | 場所 |
|---|--------|------|------|------|
| B-1 | 高 | ✅ 修正済み (2026-07-06) | 為替レート未取得時（初回起動直後・オフライン）に未換算の金額をそのまま返し、「15,000 KRW → ¥15,000」のような桁違い表示になる。→ 概算フォールバックレートで必ず換算するよう修正 | `Services/RakutenBooksModels.swift` `ExchangeRateService.convert` |
| B-2 | 高 | ✅ 修正済み (2026-07-07) | Paywall の価格表示が `product.displayPrice` を使わず整数切り捨て＋「円」固定表記。日本以外の App Store 地域では "$9.99" が「9円/年」になる。→ `product.displayPrice`（ロケール・通貨対応）に変更し、年額は通貨中立の期間サフィックス `paywall.per_year` を付与 | `Views/UnlimitedPaywallView.swift` planCard |
| B-3 | 中 | ✅ 修正済み (2026-07-06) | 手入力価格アラートで未入力・不正入力のまま登録でき、金額 nil の本が保存され 0 円トーストが出る。→ 未入力・非数値・負数は登録せず入力アラートを開き直すよう修正 | `Views/BookSearchView.swift` `registerWithManualPrice` |
| B-4 | 中 | ⬜ | Markdown エクスポート／プレビューの合計行で通貨記号が二重になる（表示通貨が USD 等のとき「$12.99円」「$12.99 JPY」） | `Utils/MarkdownExporter.swift` 59–65, 132–138行付近 |
| B-5 | 低 | ⬜ | Google Books の価格換算が `Double` 経由で、小数通貨で 1 最小単位の丸め誤差が起き得る | `Services/GoogleBooksService.swift` `GoogleSaleInfo.resolvedPrice` |
| B-6 | 中 | ✅ 修正済み (2026-07-07) | NAVER 検索で `discount: "0"`（未販売・輸入書に多い）の本が「0 won」と表示され、手入力アラートも出ずに 0 円で登録される。他プロバイダは価格情報なしを `nil`＝「-」＋手入力にしているが、NAVER のみ "0" を実価格 0 として扱う非対称（`Int("0")` = 0 で非 nil。空文字 `""` は正しく nil になる）。→ `toRakutenBook` の価格マッピングを「0 超のみ採用、空・0 以下は nil」に変更し、他プロバイダと挙動を統一 | `Services/NaverBooksService.swift` `NaverBookItem.toRakutenBook`（`itemPrice` マッピング） |

## グループC: 口座・ナビゲーション状態

| # | 優先度 | 状態 | 内容 | 場所 |
|---|--------|------|------|------|
| C-1 | 中 | ✅ 修正済み (2026-07-06) | 口座削除後も `selectedPassbook` / `isOverallMode` が更新されず、削除済みモデルを参照し続ける（空表示・不正表示・クラッシュリスク）。→ 口座リストの変化を監視し、選択中の口座が消えたら総合口座モードへ戻すよう修正 | `Views/MainTabView.swift` `validateSelectedPassbook` |
| C-2 | 中 | ✅ 修正済み (2026-07-06) | ツールバーの口座切替時に各タブの `NavigationPath` をクリアしないため、旧口座の画面（検索など）が残ったままになる。→ 切替時に通帳・本棚・集計タブのパスをルートへ戻すよう修正 | `Views/MainTabView.swift` `switchToPassbook` / `switchToOverall` |
| C-3 | 中 | ✅ 修正済み (2026-07-06) | 二重タップで同一書籍を重複登録できる（`saveBook` が保存直前に登録済み再チェックをしない。DB ユニーク制約もなし）。→ 保存直前に `isBookRegistered` で再チェックするよう修正 | `Views/BookSearchView.swift` `saveBook` |
| C-4 | 低 | ⬜ | 通帳の並びが `registeredAt` のみのソートで、同秒登録時に通帳番号が再描画で入れ替わる可能性 | `Views/PassbookDetailView.swift` `@Query` ソート |

## グループD: カレンダー・統計

| # | 優先度 | 状態 | 内容 | 場所 |
|---|--------|------|------|------|
| D-0 | −（新規方針） | ✅ 実装済み (2026-07-06) | 本の登録日に未来日を選べないようにする方針を導入。DatePicker の上限は従来から「今日」だったが、保存時にも `min(registeredAt, Date())` で保証するよう追加。※過去に未来日で保存された既存データは編集画面で保存し直した時点で補正される | `Views/AddBookView.swift` `saveBook` ／ `Views/EditBookView.swift` `saveChanges` |
| D-1 | 中 | ✅ 対応不要化 (2026-07-06) | 登録日を当年の未来月にした本が本棚カレンダーに表示されない（当年は「今月→1月」しか月グループを生成しない）。→ 登録日の未来日禁止（下記 D-0）により新規発生しなくなったため個別対応なし | `Views/BookshelfCalendarView.swift` `booksByYear` |
| D-2 | 中 | ✅ 対応不要化 (2026-07-06) | 統計の年間合計は未来月の本を含むが、月別グラフは未来月を 0 にするため、年間サマリーとグラフ合計が食い違う。→ 登録日の未来日禁止（下記 D-0）により新規発生しなくなったため個別対応なし | `Views/StatisticsView.swift` `yearlyAmount` / `chartData` |
| D-3 | 中 | ⬜ | 統計タブの `selectedYear` が、その年の本が全削除されても `availableYears` に自動追従せず、空ページ・表示不整合になる | `Views/StatisticsView.swift` |
| D-4 | 中 | ⬜ | 同一日に複数冊登録した場合、カレンダーから開けるのは最新 1 冊のみ（+N バッジは出るが他の本への導線がない） | `Views/BookshelfCalendarView.swift` 日セルの NavigationLink |

## グループE: 課金（StoreKit）

| # | 優先度 | 状態 | 内容 | 場所 |
|---|--------|------|------|------|
| E-1 | 中 | ✅ 修正済み (2026-07-06) | 購入・復元の失敗時に Paywall 上で何も通知されない（`errorMessage` を設定するが表示していない。購入の catch も空） | `Views/UnlimitedPaywallView.swift` ＋ `Services/UnlimitedManager.swift` |
| E-2 | 中 | ✅ 修正済み (2026-07-06) | StoreKit の商品読み込み失敗時、購入ボタンが永久に無効のままリカバリー手段がない（再読み込み導線なし） | `Views/UnlimitedPaywallView.swift` |

## グループF: 共有（Web 連携・bookbank-share）

| # | 優先度 | 状態 | 内容 | 場所 |
|---|--------|------|------|------|
| F-1 | 高 | ⬜ | 共有ページが価格を最小通貨単位のまま「円」で表示（$12.99＝1299 が「1,299円」）。根本原因は共有 API のペイロードに通貨コードが無いこと。iOS 側 `ShareBookItem` と Web 側の両方の修正が必要 | iOS: `Services/ShareService.swift` ／ Web: `app/share/[id]/page.tsx` |
| F-2 | 中 | ⬜ | Redis 書き込みが失敗しても共有 URL を 200 で返すため、リンク先が 404 になる | Web: `app/api/lists/route.ts` ＋ `lib/redis.ts` |
| F-3 | 低 | ⬜ | 共有リスト GET API に CORS ヘッダーがない（現行 iOS クライアントは POST のみ使用のため実害小） | Web: `app/api/lists/[id]/route.ts` |

## グループG: ローカライズ・日付・軽微

| # | 優先度 | 状態 | 内容 | 場所 |
|---|--------|------|------|------|
| G-1 | 低 | ⬜ | Google Books の `publishedDate` がタイムスタンプ形式（`2009-05-15T00:00:00Z` 等）だと日付変換が壊れ、不正な発売日文字列になる | `Services/GoogleBooksService.swift` `formattedSalesDate` |
| G-2 | 低 | ⬜ | 年のみの発売日（「2020年」等）が、端末タイムゾーンが JST より西（米国等）だと `publishedYear` が 1 年ずれる（`Calendar.current` を使用） | `Services/RakutenBooksModels.swift` `SalesDateParser.year` |
| G-3 | 低 | ⬜ | 検索結果件数の `L10n.format` に `Int` を `%d` で渡している（他箇所は `Int64`＋`%lld`。統一推奨） | `Views/BookSearchView.swift` 件数表示 |
| G-4 | 低 | ⬜ | L10n の `.lproj` バンドル解決に失敗すると端末言語にフォールバックし、アプリ内言語設定が一部文字列に効かない可能性 | `Utils/L10n.swift` |
| G-5 | 低 | ⬜ | 検索データベース設定の補足行（「楽天ブックス」等）が非ローカライズの固定文字列 | `Services/BookSearchService.swift` `displayProviderName` |
| G-6 | 低 | ⬜ | `Color.luminance` がダイナミックカラーで 0 を返すことがあり、ボタン文字色のコントラストが稀に逆転 | `Utils/Color+Luminance.swift` |
| G-7 | 低 | ✅ 修正済み (2026-07-06) | `MonthlyMemo` の `try? context.save()` が保存失敗を握りつぶす。→ OSLog でエラーを記録し、失敗時は `rollback()` して成否を `Bool` で返すよう修正 | `Models/MonthlyMemo.swift` `MonthlyMemoRepository.save` |
| G-8 | 低 | ⬜ | 未使用キー `search_database.auto` が xcstrings に残存（削除漏れ。動作影響なし） | `Localizable.xcstrings` |

---

## 誤検知・仕様として棄却したもの

| 指摘 | 判断 |
|------|------|
| 設定画面で旧保存値 `"auto"` だとチェックマークが付かない | **誤検知**。`selected` は `deviceDefault` にフォールバックするため、該当行にチェックが付く（コードで確認済み） |
| 総合口座×ライトモードでカレンダー切替アイコンが白背景に埋もれる | 白はユーザー指定の意図的な変更。ただし総合口座（シルバー地）での視認性は実機確認を推奨 |
| NAVER 検索が最大 20 件まで | プロキシが `display=20` 固定・ページング未対応のための**既知の制限**（iOS 側は page>1 を空返しで安全に処理） |
| `ReadingList.totalValue` / `displayTotalValue` が未使用 | レガシーコード。現行 UI は `totalDisplayAmount` を使用しており動作影響なし |

---

## 推奨対応順

1. **B-1** 為替フォールバック — ✅ 対応済み (2026-07-06)
2. **B-3 / C-1 / C-2 / C-3 / G-7 / D-0（未来日禁止）** — ✅ 対応済み (2026-07-06)。D-1 / D-2 は D-0 により対応不要化
3. **A-1 / A-2 / A-7** 検索の非同期競合・状態リセット（v1.3.0 の検索改修とまとめて対応予定）
4. **B-2** Paywall 価格表示（日本のみ販売なら優先度を下げてよい）
5. **F-1 / F-2** 共有の通貨対応と Redis エラー処理（iOS・Web 両リポジトリの修正）
6. **D-3 / D-4** 統計の年選択・カレンダー同日複数冊
7. **A-3〜A-5** その他の中優先度（E-1 / E-2 は対応済み）
8. グループG の残り（G-1〜G-6, G-8）は手が空いたときに
