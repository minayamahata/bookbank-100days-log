# BookBank 開発ログ

最終更新: 2026年02月02日

---

## プロジェクト概要

**BookBank（読書銀行）**
読んだ本の金額を貯金のように積み立てていく、知的エンタメiOSアプリ

---

## プロジェクト構造

```
BookBank-100days-log/
├── days/                          # 100日チャレンジの開発記録日報
├── docs/                          # 設計ドキュメント
│   ├── table.md                  # テーブル設計概要
│   ├── tables-definition.md      # 詳細なテーブル定義
│   ├── er-diagram.md             # ER図
│   ├── crud.md                   # CRUD設計
│   └── screen-list.md            # 画面一覧
├── Roadmap.md                     # DAY54-100の開発計画
└── dev/BookBank/                  # 実際のXcodeプロジェクト
    ├── BookBank.xcodeproj
    ├── BookBank/
    │   ├── BookBankApp.swift     # アプリエントリーポイント
    │   ├── ContentView.swift      # 口座一覧画面
    │   ├── Models/                # データモデル
    │   └── Views/                 # 画面コンポーネント
    └── ...
```

---

## 技術スタック

- **言語**: Swift
- **UI**: SwiftUI
- **データ管理**: SwiftData
- **アーキテクチャ**: MVVM（予定）
- **iOS最小バージョン**: iOS 17.0以降

---

## データモデル（SwiftData）

### 1. Passbook（口座・通帳）

ユーザーの書籍を分類・管理するための論理的なグループ

**プロパティ**:
- `name: String` - 口座名（例: "総合口座", "技術書", "漫画"）
- `type: PassbookType` - 口座種別（overall/custom）
- `sortOrder: Int` - 表示順序
- `isActive: Bool` - 有効フラグ
- `createdAt: Date` - 作成日時
- `updatedAt: Date` - 更新日時

**リレーション**:
- `userBooks: [UserBook]` - この口座に登録されている書籍

**Computed Properties**:
- `isOverall: Bool` - 総合口座かどうか
- `bookCount: Int` - 登録書籍数
- `totalValue: Int` - 総額（登録時価格の合計）

**ファクトリーメソッド**:
- `createOverall()` - 総合口座を作成

---

### 2. UserBook（ユーザー登録書籍）

ユーザーが登録した書籍情報

**書籍マスター情報**:
- `title: String` - 書籍タイトル
- `author: String?` - 著者名
- `isbn: String?` - ISBN
- `publisher: String?` - 出版社
- `publishedYear: Int?` - 出版年
- `price: Int?` - 定価
- `thumbnailURL: String?` - 表紙画像URL
- `source: BookSource` - 登録元（api/manual）

**ユーザー固有情報**:
- `memo: String?` - ユーザーメモ
- `isFavorite: Bool` - お気に入りフラグ
- `priceAtRegistration: Int?` - 登録時点の価格（資産計算用）
- `registeredAt: Date` - 書籍登録日時
- `createdAt: Date` - 作成日時
- `updatedAt: Date` - 更新日時

**リレーション**:
- `passbook: Passbook?` - 所属口座

**Computed Properties**:
- `displayAuthor: String` - 表示用の著者名
- `displayPrice: String?` - 表示用の価格文字列
- `hasISBN13: Bool` - ISBN-13形式かどうか

---

### 3. Subscription（サブスクリプション）

課金状態を管理（StoreKit 2連携予定）

**プロパティ**:
- `plan: SubscriptionPlan` - プラン種別（free/pro）
- `status: SubscriptionStatus` - 課金状態
- `startedAt: Date` - 利用開始日時
- `endedAt: Date?` - 利用終了日時
- `createdAt: Date` - 作成日時
- `updatedAt: Date` - 更新日時

**Computed Properties**:
- `isProActive: Bool` - Pro機能が利用可能かどうか
- `isFree: Bool` - 無料プランかどうか

---

## 実装済み機能

### ✅ アプリ初期化（BookBankApp.swift）

**実装内容**:
- SwiftData ModelContainer設定
- Passbook, UserBook, Subscriptionの3モデルを管理
- 初回起動時にデフォルトの「総合口座」を自動作成

**コード抜粋**:
```swift
init() {
    let schema = Schema([
        Passbook.self,
        UserBook.self,
        Subscription.self
    ])
    modelContainer = try ModelContainer(for: schema, ...)
    initializeDefaultData()
}
```

---

### ✅ 口座一覧画面（ContentView.swift）

**実装内容**:
- NavigationStack導入
- @Queryで全Passbookを取得（sortOrder順）
- 各口座をタップで通帳画面に遷移

**表示項目**:
- 口座名
- 登録書籍数
- 総額

---

### ✅ 通帳画面（PassbookDetailView.swift）

**実装内容**:
- 総合口座の詳細表示
- その口座に紐づくUserBookの一覧表示
- iOS標準の`.listStyle(.insetGrouped)`スタイル
- 空状態の処理（「まだ本が登録されていません」）
- 本の詳細画面への遷移

**表示項目**:
- 上部: 口座名、合計金額、登録書籍数
- リスト: 2カラムレイアウト（左：日付・タイトル・著者、右：金額）
- 日付フォーマット: YYYY.MM.DD

---

### ✅ 本棚画面（BookshelfView.swift）

**実装内容**:
- 全書籍を4カラムグリッド表示
- iOS写真アプリスタイル（2pxギャップ、2px角丸）
- レスポンシブ対応（画面幅の25%）
- お気に入りマーク表示
- 本の詳細画面への遷移

**表示項目**:
- 表紙画像（アスペクト比2:3）
- お気に入りマーク（右上）
- 薄いドロップシャドウ

---

### ✅ 本の検索画面（BookSearchView.swift）

**実装内容**:
- 楽天Books API連携で実際の本を検索
- タイトル・著者名の両方で検索（並行実行してマージ）
- 発売日順（新しい順）でソート
- 無限スクロール（ページング機能）
- 検索結果から選択して連続登録可能
- 入金トースト通知（¥XXX 入金しました！）
- 登録済み本のグレーアウト + 「登録済み」バッジ表示
- 「未登録のみを表示」フィルター機能
- 検索結果が0件の場合、「手動で登録する」ボタンを表示
- 右上のペンシルアイコンからも手動登録が可能

**表示項目**:
- 検索バー（タイトルまたは著者名）
- 検索結果リスト（表紙画像、タイトル、著者、価格）
- 空状態のメッセージ

---

### ✅ 手動登録画面（AddBookView.swift）

**実装内容**:
- タイトル（必須 *）
- 著者名（任意）
- 価格（必須 * - 読書銀行のコンセプトに必須）
- メモ（任意）
- お気に入りフラグ
- 保存後、自動的に通帳画面に戻る

**バリデーション**:
- タイトルと価格の両方が入力されていないと保存不可

---

### ✅ 本の詳細画面（UserBookDetailView.swift）

**実装内容**:
- 表紙画像（ドロップシャドウ、角丸なし、サイズ200px）
- お気に入りボタン（画像右上にオーバーレイ）
- 削除ボタン（価格の右、グレーで控えめ）
- 基本情報（タイトル、著者、価格）
- 詳細情報（登録日、出版社、出版年、発行形態、ページ数）
- メモ機能（全画面モーダルで編集）

**表示項目**:
- 表紙画像（薄いドロップシャドウ）
- タイトル・著者・価格
- 登録日（YYYY.MM.DD形式）
- 出版社・出版年
- 発行形態・ページ数
- メモ（12pt、120px高さ）

---

### ✅ メモ編集モーダル（MemoEditorView.swift）

**実装内容**:
- 全画面モーダル形式
- ナビゲーションバー（キャンセル・完了ボタン）
- 全画面TextEditor
- プレースホルダー「メモを入力...」
- 自動フォーカス
- 変更確認アラート（変更がある場合のみ）

**動作**:
- 「完了」ボタンで保存して閉じる
- 「キャンセル」ボタンで変更を破棄（確認あり）
- 下スワイプでも閉じられる

---

### ✅ 集計画面（StatisticsView.swift）

**実装内容**:
- Swift Chartsで年別の読書統計をグラフ表示
- TabViewで年をスワイプ切り替え
- 上段：金額の折れ線グラフ（緑色・直線・ポイントマーカー付き）
- 下段：冊数の棒グラフ（緑色半透明・細い棒・角丸）
- Y軸は右側配置、X軸は日本語表記（1月〜12月）
- 未来の月は非表示、過去の年は全月表示

**表示項目**:
- 年表示（固定）
- 金額グラフ（月別推移）
- 冊数グラフ（月別推移）
- ページインジケーター（ドット）
- 読書レポートへのリンク

**デバッグ機能**:
- デバッグビルド時に過去3年分のテストデータを自動生成
- テスト口座3つ（技術書、漫画、小説）
- 各月1-3冊のランダムデータ

---

## 未実装機能（次のステップ）

### 🔜 最優先

1. **ソート機能（通帳画面）**
   - 日付順、価格順、タイトル順

3. **グラフ表示**
   - Swift Chartsで月別累計グラフ

4. **統計画面**
   - 読んだ本の総数、平均価格など

5. **ISBN検索API連携**
   - OpenBD APIで本の情報を自動取得

6. **データエクスポート/インポート**
   - CSV形式でバックアップ

7. **設定画面**
   - テーマカラー変更、通知設定など

---

## ファイル一覧

### コア

```
BookBank/
├── BookBankApp.swift              # アプリエントリーポイント、SwiftData設定、RootView
├── ContentView.swift               # （未使用）
├── Views/
│   ├── OnboardingView.swift       # オンボーディング画面
│   ├── MainTabView.swift          # タブバー（通帳・本棚・集計の3つ）
│   ├── PassbookSelectorView.swift # 口座選択画面
│   ├── PassbookDetailView.swift   # 通帳画面（総合口座・カスタム口座対応）
│   ├── BookshelfView.swift        # 本棚画面（口座別）
│   ├── OverallBookshelfView.swift # 総合口座の本棚画面
│   ├── StatisticsView.swift       # 集計画面（年別グラフ表示）
│   ├── AddPassbookView.swift      # 口座追加画面
│   ├── BookSearchView.swift       # 本の検索画面（口座選択機能付き）
│   ├── AddBookView.swift          # 手動登録画面（口座選択機能付き）
│   ├── UserBookDetailView.swift   # 本の詳細画面
│   └── MemoEditorView.swift       # メモ編集モーダル
└── Services/
    ├── RakutenBooksService.swift  # 楽天Books API通信
    └── RakutenBooksModels.swift   # APIレスポンスモデル
```

### モデル

```
BookBank/Models/
├── Passbook.swift                 # 口座モデル
├── UserBook.swift                 # ユーザー登録書籍モデル
└── Subscription.swift             # サブスクリプションモデル
```

---

## 開発の進め方

### 現在のフェーズ: DAY54-70（実装初期フェーズ）

**進捗**:
- ✅ DAY54: Xcodeプロジェクト作成
- ✅ DAY55: アプリ構造設計（SwiftData設定）
- ✅ DAY56: データモデル実装
- 🔜 DAY57-: UI実装、機能追加

---

## 注意事項

### SwiftDataの使い方

**@Query でデータ取得**:
```swift
@Query(sort: \Passbook.sortOrder) private var passbooks: [Passbook]
```

**データ保存**:
```swift
context.insert(newPassbook)
try context.save()
```

**リレーションのフィルタリング**:
```swift
private var userBooks: [UserBook] {
    allUserBooks.filter { 
        $0.passbook?.persistentModelID == passbook.persistentModelID 
    }
}
```

---

## Git構成

- **リポジトリ**: `BookBank-100days-log`（日報・設計ドキュメント・Xcodeプロジェクト）
- **管理方法**: 1つのリポジトリで統合管理（2026-01-15にサブモジュール構成から変更）

**コミット時**:
```bash
# プロジェクトルートで
cd /Users/37/AYAME-Cursor/BookBank-100days-log
git add .
git commit -m "メッセージ"
git push origin main
```

---

## 参考リンク

- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Swift Charts Documentation](https://developer.apple.com/documentation/charts)
- [OpenBD API](https://openbd.jp/)

---

## 開発履歴

### 2026-02-02（DAY72）
- ✅ **デザインシステム（DESIGN_SYSTEM.md）の作成**
  - 既存コードからデザインルールを抽出しドキュメント化
  - カラー、タイポグラフィ、間隔、角丸、影、コンポーネントの使い分けを定義
  - 背景2色構成パターンを追記

- ✅ **本の表紙デザインの統一**
  - 全画面で角丸を2pxに統一（BookSearchView、BookSelectorView、ReadingListDetailView等）
  - アスペクト比を2:3に統一
  - サイズを3パターンに整理（リスト: 50x75px、グリッド: 幅×1.5、単体: 140x210px）

- ✅ **リストビューの間隔統一**
  - 水平パディングを24pxに統一（PassbookDetailView、BookSelectorView等）
  - 垂直パディング8px、スペーシング0で統一

- ✅ **ダークモードの色調整**
  - Color.appGroupedBackgroundを#000000（純黒）に変更
  - ReadingListDetailViewの背景を2色構成に変更（上部: #1A1A1A、下部: #000000）
  - ReadingListDetailViewの棚板をダークモードで黒に変更
  - ReadingListDetailViewのリストビュー背景をダークモードで黒に変更

- ✅ **ReadingListDetailViewの改善**
  - 上段・下段の本棚の間隔を16pxに拡大
  - 下段の本棚をセンタリング
  - スクロール時の背景処理を改善（2色構成で浮きを防止）
  - 編集モーダルのキャンセルボタンの色を削除、保存ボタンを変更時のみアクティブに

- ✅ **本棚ページ（BookshelfView）の改善**
  - 上部の金額セクションを削除
  - フィルターボタンを追加（お気に入り、メモあり）
  - コンテンツカードの角丸と背景を削除
  - 背景色をテーマカラー（opacity: 0.1）に変更
  - お気に入りアイコンをカスタムアイコン（icon-favorite）に統一

- ✅ **本の詳細画面（UserBookDetailView）の改善**
  - 画像なし時のアイコンを削除（「画像なし」テキストのみ残す）

### 2026-02-02（DAY72続き）
- ✅ **口座編集画面（EditPassbookView）の改善**
  - キャンセルボタンの色を削除（.primary）
  - 保存ボタンを変更時のみアクティブに（hasChanges検知）
  - Formを自前レイアウトに変更（口座名入力の角丸16px、境界線追加）
  - キーボード外タップで閉じる機能を追加
  - 削除ボタンを角丸12px＋境界線デザインに変更

- ✅ **マークダウンダウンロード機能の実装**
  - MarkdownExporter.swiftを新規作成
  - MarkdownDocument（FileDocument準拠）でファイル出力対応
  - 口座・読了リストをMarkdown形式でダウンロード可能に
  - タイトルと著者名のみ（無料）/ 詳細情報（Pro）の2段階ダウンロード
  - VSCode風プレビューカード（シンタックスハイライト風）
  - 実際の登録データからプレビュー表示
  - Pro版: 表紙画像URL、メモ、お気に入りフラグも出力

- ✅ **ダウンロードUI（ExportSheetView）**
  - ボトムシート形式でプレビュー表示
  - VSCode風コードブロック（ダーク背景、3つのドット、markdownラベル）
  - タイトルと著者名のみ / 詳細情報を含めるの選択
  - Proボタンにグラデーション（#2280e2→#fd7020）
  - ダークモード対応（背景を黒に）
  - 「エクスポート」表現を「ダウンロード」に統一

- ✅ **読了リストのアクションボタン整理**
  - 「追加」「並べ替え&削除」と三点リーダーの3ボタン構成
  - 三点リーダーでボトムシート表示（MoreActionsSheet）
  - シェア / ダウンロード / 名前と詳細の編集 / このリストを削除

- ✅ **読了リスト詳細画面（ReadingListDetailView）の改善**
  - リスト形式を通帳ページと同じスタイルに変更（右側に金額表示）
  - 背景色をsystemGroupedBackground（#1C1C1E）に変更
  - 「このリストを削除」機能を追加

- ✅ **カスタムアイコンの追加**
  - icon-download.svg（ダウンロードボタン用）
  - icon-more.svg（三点リーダー用）

- ✅ **デザインシステムの更新**
  - ツールバーボタンのルール追加（キャンセル色なし、保存は変更時のみアクティブ）
  - キーボード関連ルール追加（外タップで閉じる、レイアウト崩れ防止）

- ✅ **Pro機能制限の追加**
  - 口座一覧ページ・口座選択ページで4つ目以降の口座作成時にPro案内を表示
  - 外側タップで閉じるconfirmationDialogを使用

- ✅ **画像表示の安定化（CachedAsyncImage）**
  - CachedAsyncImage.swiftを新規作成
  - URLSessionで画像を手動ロードし、@Stateで保持
  - タブ切り替え時の画像消失問題を解決
  - BookCoverView、PassbookDetailViewで使用
  - BookshelfViewのLazyVGridに.animation(nil)を追加

- ✅ **本の検索ページの改善**
  - リスト境界線を削除、間隔をDESIGN_SYSTEMに準拠
  - 「未登録のみ」を「登録済みを除外」にテキスト変更
  - 「登録済み」バッジをオーバーレイ表示に変更（レイアウトシフト防止）
  - パフォーマンス改善（ソート結果キャッシュ、登録済みISBNのSet化）
  - 無限スクロールを「次の30件を読み込む」ボタン方式に変更

- ✅ **統計ページの改善**
  - お気に入り数、メモ数の表示を追加

- ✅ **バーコードスキャナーの改善**
  - ガイド枠のアライメントを修正

- ✅ **本棚ページの改善**
  - フィルターボタンのテキストサイズを13pxに変更
  - 非選択時の背景を白、テキストを黒に変更

- ✅ **本の詳細ページの改善**
  - メモ欄の背景色をsecondarySystemGroupedBackgroundに変更

### 2026-01-31（DAY70続き）
- ✅ **読了リスト詳細画面（ReadingListDetailView）の大幅改善**
  - 本棚グリッドに奥行き表現を追加（斜め上から見下ろすデザイン）
  - 上段は棚板が薄く・小さく、下段は濃く・大きく
  - 棚板の高さ: 6pt→10pt、厚み: 2pt→4pt（上段→下段）
  - シャドウの強さ・長さも行ごとに変化
  - ダークモード対応: 棚板を白に、シャドウを白い光に反転
  - listInfoSectionの背景色・角丸を削除（シンプル化）
  - listContentの背景色をappCardBackgroundに変更（ダークモード対応）
  - listContentのパディング調整（top: 16px、左右: 24px）
  - スクロール最下部の背景処理を改善（100pxの余白追加）
  - 本棚とリストタイトルの間隔を狭く調整

- ✅ **本選択画面（BookSelectorView）の改善**
  - グリッド形式からリスト形式に変更
  - 口座別にスワイプで切り替え可能に
  - スティッキーヘッダーに読了リストのタイトルを表示
  - キャンセル・追加ボタンをヘッダーに統合
  - 日付フォーマットをYYYY.MM.DDに統一
  - チェックボタンのサイズ・境界線を調整
  - リスト間の境界線を削除（デザインシステム統一）

- ✅ **読了リストのテストデータ自動生成**
  - BookBankApp.swiftにgenerateReadingListTestData()を追加
  - 「2024年ベスト」「技術書まとめ」「おすすめ小説」の3リストを自動生成
  - 既存データがあっても読了リストがなければ自動追加

- ✅ **デザインシステムの統一（.cursorrules更新）**
  - リストビューの境界線は一切不要
  - 本の表紙は角丸2px
  - 日付フォーマットはYYYY.MM.DD
  - カード/ウィジェットはappCardBackground使用
  - アイコンサイズは14-18pt

### 2026-01-31（DAY70）
- ✅ **読了リスト機能（Myリスト）の実装**
  - Spotifyのプレイリストのような機能を新規追加
  - 本棚から好きな本を選んで「読了リスト」を作成できる
  - リストは複数作成可能

- ✅ **ReadingListモデルの作成**
  - `Models/ReadingList.swift`を新規作成
  - title, listDescription, createdAt, updatedAtプロパティ
  - UserBookへの多対多リレーション（本が削除されるとリストからも消える）
  - bookCount, totalValue, displayTotalValueの計算プロパティ
  - UserBookに`readingLists`逆参照を追加
  - BookBankApp.swiftのスキーマにReadingListを追加

- ✅ **リスト一覧画面（ReadingListView）**
  - 2カラムのカード形式で表示
  - 3x3グリッドの本の表紙サムネイル（2:3の本のアスペクト比）
  - タイトル・冊数・合計金額を表示
  - iOSウィジェット風の境界線
  - 長押しで削除可能
  - 右上にThemeToggleButton

- ✅ **リスト作成画面（AddReadingListView）**
  - Spotifyスタイルのステップ形式UI
  - Step 1: リスト名入力（デフォルト名「Myリスト#1」自動設定）
  - Step 2: 作成後、本を追加する画面に自動遷移
  - 「スキップ」で本を追加せずに完了も可能

- ✅ **リスト詳細画面（ReadingListDetailView）**
  - 本棚形式（4カラムグリッド）で本を表示
  - 合計金額・冊数をヘッダーに表示
  - 「本を追加」ボタンで本選択画面へ
  - 長押しで「リストから削除」（本棚からは削除されない）
  - 編集ボタンでタイトル・説明の編集、リスト削除が可能

- ✅ **本の詳細カルーセル（BookCarouselView）**
  - 本をタップするとカルーセル形式のポップアップ表示
  - ZStackオーバーレイで背景透過対応（thinMaterial）
  - GeometryReaderでカード幅を65%に設定（前後の本が見える）
  - scrollTargetLayout + scrollTargetBehaviorでスナップ動作
  - scrollTransitionで非アクティブなカードを縮小表示
  - initで初期スクロール位置を設定（2冊目以降も正しく中央表示）
  - 角丸24px、iOSウィジェット風の境界線、シャドウ付き

- ✅ **本選択画面（BookSelectorView）**
  - 全口座の本を4カラムグリッドで表示
  - 複数選択可能（チェックマーク表示）
  - 既にリストにある本はグレーアウト
  - 「完了」ボタンでまとめて追加

- ✅ **タブバーの更新**
  - 「Myリスト」タブを追加（5タブ構成に）
  - タブ順序: 口座 → 通帳 → 本棚 → 集計 → Myリスト
  - カスタムアイコン（icon-tab-mylist）を追加

- ✅ **Myリストタブの+ボタン改善**
  - Myリストタブでも右下の+ボタンを表示
  - タップするとMenuで「本を登録する」「読了リストを作成する」を選択可能
  - アイコンはタブバーと同じカスタムアイコンを使用

### 2026-01-29（DAY69）
- ✅ **ダークモード対応（ThemeManager）**
  - ThemeManager（@Observable）を新規作成、UserDefaultsで設定を永続化
  - AppTheme enum（system/light/dark）でテーマ状態を管理
  - カスタム背景色（Color.appGroupedBackground, Color.appCardBackground）を定義
  - ダークモード時はダークグレー系カラー（#1C1C1E, #2C2C2E）を使用
  - BookBankApp.swiftで`.preferredColorScheme`を適用
  - 全画面のColor(UIColor.systemBackground)等をカスタムカラーに置き換え

- ✅ **テーマ切替ボタン（ThemeToggleButton）**
  - ナビゲーションバー右上にテーマ切替メニューを配置
  - 通帳・本棚・集計・口座一覧の全タブに追加
  - SF Symbolsアニメーション付きアイコン切替（sun/moon/circle）

- ✅ **タブバーアイコンをオリジナルSVGに変更**
  - icon-tab-account、icon-tab-passbook、icon-tab-bookshelf、icon-tab-statisticsを追加
  - SF Symbolsから独自アセットに差し替え

- ✅ **削除アイコンをオリジナルSVGに変更**
  - icon-deleteアセットを追加（imageset + Contents.json）
  - UserBookDetailViewの削除ボタンをカスタムアイコンに差し替え

- ✅ **口座テーマカラーの適用範囲拡大**
  - 本検索画面：口座セレクタ・入金トースト・価格表示に口座カラーを反映
  - 手動登録画面：口座セレクタ・保存ボタンに口座カラーを反映
  - 本の詳細画面：口座テーマカラーを取得する仕組みを追加

- ✅ **UIの細かい調整**
  - LiquidGlassButtonのプラスアイコンを18pt→12ptに縮小
  - 通帳画面の日付フォントを.caption→.system(size: 10)に変更
  - 口座一覧・口座選択の三点リーダーを.system(size: 10)に変更
  - 口座行のpadding調整（trailing: 16→8）
  - 集計画面の背景をテーマカラーの薄い色に変更
  - 折れ線グラフの線幅を2→1に変更
  - 棒グラフにchartYScale(includesZero: true)を追加
  - 本棚グリッドに角丸2pxのclipShapeを追加
  - 手動登録フォームのセクション構成を変更（各項目を独立セクションに）
  - トースト通知のデザインを簡素化（アイコン削除、フォント縮小）

### 2026-01-29（DAY69）
- ✅ **ダークモード対応の改善**
  - ダークモード時の背景色を純粋な黒（#000000）に変更
  - 通帳・本棚ページのコンテンツ背景をColor(.systemBackground)に変更
  - スクロールバウンス時に背景が浮かない対策（GeometryReader使用）

- ✅ **口座テーマカラーの刷新**
  - 9色のカラーパレットに変更（赤、オレンジ、黄、緑、シアン、青、紫、ピンク、グレー/白）
  - 最初の色はライト/ダークモードで自動切り替え（ライト: 黒、ダーク: 白）
  - カラー選択UIを1列表示に変更
  - 新規口座追加ページにもカラー選択を追加

- ✅ **口座アイコンの改善**
  - fill + stroke の2層構造で表現（fill: opacity(0.1)、stroke: テーマカラー）
  - icon-tab-account-fill.imageset を新規追加

- ✅ **UIの統一・改善**
  - アプリ全体のフォント太字を削除（レギュラーに統一）
  - 三点リーダーのタップエリア拡大（44x44）
  - 「新しい口座を追加」ボタンの色をprimaryに変更
  - LiquidGlassButton を iOS標準 glassEffect に変更
  - トースト通知を glassEffect でリキッドガラス化

### 2026-01-26（DAY68）
- ✅ **スプラッシュスクリーン（SplashScreenView）の実装**
  - カスタムオープニングアニメーション付きスプラッシュ画面を作成
  - ドット → BookBank → your mind. → 四隅テキストの順にフェードイン
  - GeometryReaderでセーフエリアを考慮した配置
  - 6種類の背景画像からランダムに選択される機能
  - LaunchScreen.storyboardを削除し、SwiftUIベースに移行

- ✅ **カスタムフォントの導入**
  - 「Fearlessly Authentic」フォントを追加（ロゴ用）
  - 「Fearlessly Authentic Italic」フォントを追加（タグライン用）
  - 「Inter-Regular」フォントを追加（四隅テキスト用）
  - Info.plistにフォント登録

- ✅ **集計ページの改善**
  - 資産ポートフォリオセクションを削除

- ✅ **口座一覧ページの改善**
  - 円グラフのドーナツの太さを調整（innerRadius: 0.6）

### 2026-01-25（DAY67）
- ✅ **口座テーマカラー選択機能の実装**
  - Passbookモデルに`colorIndex: Int?`プロパティを追加
  - PassbookColorを8色から12色に拡張（red, yellow, teal, brownを追加）
  - 口座編集画面にカラーパレットUIを追加（グリッド表示で選択）
  - AccountListView、PassbookSelectorViewでcolorIndexを反映
  
- ✅ **口座一覧ページの円グラフ改善**
  - 総資産・金額・冊数を円グラフの中央に配置
  - グラフの高さを160px→220pxに拡大
  - ドーナツの太さを細く調整（innerRadius: 0.6→0.75）
  - 線の間隔を調整（angularInset: 1.5）
  
- ✅ **手動登録画面（AddBookView）の改善**
  - キャンセルボタンの色を削除（.primary）
  - 口座名の色を削除（.tint(.primary)）
  - 入力エリア以外タップでキーボードを閉じる機能
  - メモとお気に入りセクションを削除
  - セクションヘッダーを.footnoteに変更
  
- ✅ **本検索画面（BookSearchView）の改善**
  - 右上の鉛筆アイコンを「手動登録」テキストに変更
  - フォントサイズを.footnote、色を.primaryに変更
  
- ✅ **全ページのNavigationTitleフォント統一**
  - BookBankApp.swiftでUINavigationBarAppearanceを設定
  - 全ページのタイトルを.subheadline相当（15pt）に変更
  
- ✅ **ページタイトルの変更**
  - 通帳ページ：「BookBank」→「通帳」
  - 本棚ページ：「BookBank」→「本棚」
  
- ✅ **口座選択・一覧ページの細かいUI調整**
  - 色を表す●を12px→8pxに変更
  - 口座名のフォントを.body→.subheadlineに変更
  - 三点リーダーを.body→.captionに変更
  - グラフ中央の「総資産」を.headline、色を.primaryに変更

### 2026-01-24（DAY66）
- ✅ **楽天Books API を総合検索APIに変更**
  - 書籍専用API（BooksBook/Search）から総合検索API（BooksTotal/Search）に変更
  - コミック・雑誌も検索可能に（booksGenreId="001"で本カテゴリに絞る）
  - formatVersion=2でシンプルなJSON形式に対応
  - タイトル・著者の並行検索からキーワード検索に一本化（検索精度向上）
  - `RakutenTotalBookItem`モデルを追加し、`RakutenBook`に変換する仕組みを実装
  
- ✅ **UserBookDetailViewのカスタムヘッダー実装**
  - 標準のNavigationBarを非表示にし、自前のヘッダーを実装
  - `.ultraThinMaterial`背景でガラス風エフェクトを維持
  - 戻るボタンを自前で実装（chevron + "戻る"テキスト）
  - safeAreaInsetでヘッダーを配置（ノッチ対応）

### 2026-01-22（DAY64）
- ✅ **口座削除機能の実装**
  - PassbookDetailViewに口座編集機能を追加
  - 編集モーダルに「この口座を削除」ボタンを配置
  - 削除確認アラート実装（登録書籍数を表示）
  - 「この口座に登録されている○冊の本も削除されます」とアナウンス
  - Passbookモデルのリレーションシップを`.cascade`に変更
  - 削除後は自動的に口座一覧画面に戻る
  
- ✅ **楽天Books API検索の精度改善**
  - キーワード検索を追加（広範囲検索）
  - 検索結果が関連性の低い本を含む問題を修正
  - キーワード検索を削除し、タイトル・著者検索のみに絞る
  - ソート順を関連度順（`standard`）に変更
  - 検索結果の並び順を最適化（タイトル検索を優先）
  - デバッグログを追加（検索件数の確認）
  
- ✅ **UserBookDetailViewのデザイン改善**
  - リキッドグラスデザインを適用
  - `.ultraThinMaterial`背景でガラス風のエフェクト
  - 本の画像を白いカードの外に配置（フローティング）
  - 本の角丸を2pxに変更、サイズを一回り小さく調整
  - メモセクションに`.thinMaterial`を適用
  - カード周りに余白を追加（horizontal: 20, vertical: 20）
  
- ✅ **本棚のサムネイル表示問題を修正**
  - BookshelfViewのAsyncImageに`.id(imageURL)`を追加
  - 本を登録後、即座にサムネイルが表示されるように改善
  - アプリを閉じなくても画像が反映される

### 2026-01-21（DAY63）
- ✅ **集計ページ（StatisticsView）の完全実装**
  - Swift Chartsで年別グラフ機能を実装
  - 金額の折れ線グラフ（緑色・直線・小さいポイント）
  - 冊数の棒グラフ（緑色半透明・細い棒・角丸2pt）
  - Y軸を右側に配置、X軸を日本語表記（1月、2月...）
  - グリッドラインは水平方向のみ表示
  
- ✅ **年別スワイプ機能**
  - TabViewでページング実装
  - 左右スワイプで前年/翌年に切り替え
  - ページインジケーター（ドット）でナビゲーション
  - 年表示は固定、グラフ部分のみTabView化
  
- ✅ **データ表示ロジック**
  - 未来の月を表示しない（現在の年は今月まで）
  - 過去の年は1-12月すべて表示
  - データがない月は0として表示
  - X軸は常に12ヶ月分のラベルを表示
  
- ✅ **読書レポートへの入口追加**
  - グラフの下に「あなたの読書レポートを見る→」カード
  - NavigationLinkで別ページに遷移
  - ReadingReportView（プレースホルダー）を作成
  
- ✅ **デバッグ機能の強化**
  - デバッグビルド時にテストデータを自動生成
  - 過去3年分のランダムなデータを作成
  - 3つのテスト口座（技術書、漫画、小説）
  - 各月1-3冊、価格800-8,000円のランダムデータ
  
- ✅ **UIの細かい調整**
  - グラフとラベルの間隔調整
  - フォントサイズ最適化（軸ラベル9pt）
  - ページインジケーターの配置調整
  - 年数表示のカンマ削除

### 2026-01-20（DAY62）
- ✅ **検索画面のUX改善**
  - 検索画面をモーダル表示に戻して`.searchable`の自動配置を活用
  - `.searchable(isPresented:)`パラメータで検索バーに自動フォーカス
  - 登録ボタンを押すと即座にキーボードが表示される体験を実現
  - キャンセルボタンを追加してモーダルを閉じられるように改善
  
- ✅ **MainTabViewの改善**
  - `.navigationDestination`から`.sheet`に変更
  - タブごとの重複を避けるためZStackレベルで`.sheet`を管理
  - より自然なモーダル表示の実装

### 2026-01-19（DAY61）
- ✅ **口座管理機能の完全実装**
  - カスタム口座の作成・削除機能
  - 総合口座 = すべてのカスタム口座の合計表示（仮想口座）
  - UserBookは必ずどこかのカスタム口座に所属
  
- ✅ **タブバー構成の大幅変更**
  - 3タブ（ホーム・口座・本棚）→ 2タブ（通帳・本棚）に変更
  - 口座切り替えボタンを左上に配置（口座名▼）
  - 総合口座の復活（デフォルト表示）
  - 各口座で通帳・本棚を切り替え可能
  
- ✅ **オンボーディング画面（OnboardingView）**
  - 初回起動時に最初の口座開設を促す
  - おすすめ口座名の候補表示（プライベート、漫画、仕事用）
  - FlowLayoutでレスポンシブなボタン配置
  - キーボードに「完了」ボタン表示（submitLabel）
  - 入力欄の右に「口座」ラベル表示
  
- ✅ **口座選択画面（PassbookSelectorView）**
  - フルスクリーンページとして実装
  - 総合口座とカスタム口座をセクション分け
  - NavigationLinkで口座追加画面に遷移（モーダルが重ならない）
  - チェックマークで選択中の口座を表示
  
- ✅ **口座追加画面（AddPassbookView）**
  - キャンセルボタン削除（戻るボタンと重複）
  - おすすめボタンを横スクロールから折り返し表示に変更
  - キーボードに「完了」ボタン表示
  - 入力欄の右に「口座」ラベル表示
  
- ✅ **本登録時の口座選択機能**
  - BookSearchViewに口座選択プルダウン追加
  - AddBookViewに口座選択プルダウン追加
  - 現在開いている口座がデフォルト値として設定
  - どの画面からでも好きな口座に登録可能
  
- ✅ **PassbookDetailViewの総合口座対応**
  - `passbook: Passbook?` で総合口座（nil）とカスタム口座の両方に対応
  - `isOverall: Bool` フラグで表示を切り替え
  - 総合口座: 全カスタム口座の書籍数・金額を集計表示
  - カスタム口座: その口座の書籍のみ表示
  - ナビゲーションタイトルに口座名を表示
  
- ✅ **BookshelfViewの口座対応**
  - 選択中の口座の本のみを表示
  - 総合口座用の本棚ビュー（OverallBookshelfView）を作成
  
- ✅ **重複登録防止機能**
  - 全口座を対象に重複チェック
  - 同じ本を複数の口座に登録できないように変更
  - ISBNまたはタイトル+著者で判定
  
- ✅ **BookBankApp.swiftの初期化ロジック変更**
  - 総合口座の自動作成を廃止
  - カスタム口座がない場合はオンボーディングを表示
  - RootViewで起動時の分岐処理

### 2026-01-18（DAY60）
- ✅ **タブバーのUI改善**
  - カスタムタブバーから標準TabViewに変更
  - 独立した登録ボタン（右下の青い丸ボタン）を配置
  - ホームと本棚は標準タブバーで管理
  
- ✅ **通帳ページの大幅改善**
  - NavigationBarのスタイルを統一（本棚ページと同じに）
  - HomeViewから口座スワイプ機能を削除（シンプル化）
  - 総合口座のみを表示する構造に変更
  - `.listStyle(.insetGrouped)`でiOS標準のグループ化リストスタイルに変更
  - 通帳ページから削除機能を削除（口座スワイプとの競合回避）
  - ScrollViewの挙動修正（タブバーの下まで表示）
  
- ✅ **本棚ページのUI改善**
  - ギャップを2pxに変更（iOS写真アプリスタイル）
  - 角丸を2pxに追加
  - 本のサイズを画面幅の25%に変更（レスポンシブ対応）
  
- ✅ **コードのクリーンアップ**
  - 余分なpadding、ignoresSafeAreaなどを削除
  - iOS標準のListコンポーネントを活用
  - NavigationStackの二重化問題を解消

### 2026-01-17（DAY59）
- ✅ **本の詳細画面完成**
  - UserBookDetailView.swiftの実装
  - 表紙画像（ドロップシャドウ、角丸なし、200px）
  - お気に入りボタン（画像右上）
  - 削除ボタン（価格の右、控えめデザイン）
  - 詳細情報表示（登録日、出版社、出版年、発行形態、ページ数）
- ✅ **メモ編集モーダル実装**
  - MemoEditorView.swiftの作成
  - 全画面モーダル形式
  - キャンセル・完了ボタン
  - 変更確認アラート
  - 即座に保存（ラグなし）
- ✅ **UserBookモデル拡張**
  - imageURL（大サイズ画像のみ保存で効率化）
  - bookFormat（発行形態）
  - pageCount（ページ数）
- ✅ **楽天Books API拡張**
  - 発行形態（size）の取得
  - ページ数の抽出（itemCaptionから正規表現で）
  - 画像は大サイズ優先、なければ中サイズ
- ✅ **UX改善**
  - 通帳画面でスワイプ削除時の確認ダイアログを削除（即削除）
  - 日付フォーマット統一（YYYY.MM.DD）
  - ミニマルなデザイン（アイコン削減、シリーズ削除）

### 2026-01-15（DAY58）
- ✅ **楽天Books API連携完了**
  - RakutenBooksService, RakutenBooksModelsの実装
  - タイトル・著者名での検索（並行実行）
  - 発売日順（新しい順）ソート
  - 無限スクロール（ページング）実装
- ✅ **UX改善**
  - 連続登録機能（検索画面を閉じない）
  - 入金トースト通知（¥XXX 入金しました！）
  - 登録済み本のグレーアウト + 「登録済み」バッジ
  - 「未登録のみを表示」フィルター機能
- ✅ **通帳画面の改善**
  - スワイプで削除機能（確認ダイアログ付き）
  - 銀行通帳風2カラムレイアウト
  - 日付フォーマット変更（YYYY.MM.DD）
  - コンパクトなデザイン

### 2026-01-15（DAY57）
- ✅ 本の検索画面（BookSearchView）作成
- ✅ 手動登録画面（AddBookView）作成 - タイトル・金額必須
- ✅ 通帳画面の+ボタンを検索画面に変更
- ✅ 登録後に通帳画面に戻るUX改善
- ✅ Git構成の修正（サブモジュール→通常のフォルダ管理）
- ✅ 消失ファイルの再作成（BookBankApp.swift, ContentView.swift, Models/など）

### 2026-01-14（DAY55-56）
- ✅ SwiftData ModelContainer設定
- ✅ 総合口座の自動作成機能
- ✅ 口座一覧画面（ContentView）
- ✅ 通帳画面（PassbookDetailView）

### 2026-01-11（DAY54）
- ✅ Xcodeプロジェクト作成
- ✅ SwiftDataモデル定義（Passbook, UserBook, Subscription）
