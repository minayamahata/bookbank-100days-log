# BookBank 開発ログ

最終更新: 2026年01月15日

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
- 選択した口座の詳細表示
- その口座に紐づくUserBookの一覧表示
- 空状態の処理（「まだ本が登録されていません」）
- 右上の「+」ボタンから検索画面を開く

**表示項目**:
- 上部: 口座名、合計金額、登録書籍数
- 中央: UserBook一覧（タイトル、著者、価格、登録日）

---

### ✅ 本の検索画面（BookSearchView.swift）

**実装内容**:
- 検索バーでタイトル・ISBNを検索（API連携は今後実装予定）
- 検索結果が0件の場合、「手動で登録する」ボタンを表示
- 右上のペンシルアイコンからも手動登録が可能
- 検索結果から選択して登録（API実装後）

**表示項目**:
- 検索バー
- 検索結果リスト（タイトル、著者、価格）
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

## 未実装機能（次のステップ）

### 🔜 最優先

1. **楽天ブックスAPI連携**
   - BookSearchViewで実際の本を検索
   - タイトル・ISBN検索
   - 検索結果から選択して登録

2. **本の詳細画面**
   - UserBookをタップして詳細表示
   - メモの閲覧・編集
   - 削除機能

### 📋 後続機能

3. **検索機能**
   - タイトル・著者名での検索

4. **ソート機能**
   - 日付順、価格順、タイトル順

5. **グラフ表示**
   - Swift Chartsで月別累計グラフ

6. **統計画面**
   - 読んだ本の総数、平均価格など

7. **ISBN検索API連携**
   - OpenBD APIで本の情報を自動取得

8. **データエクスポート/インポート**
   - CSV形式でバックアップ

9. **設定画面**
   - テーマカラー変更、通知設定など

---

## ファイル一覧

### コア

```
BookBank/
├── BookBankApp.swift              # アプリエントリーポイント、SwiftData設定
├── ContentView.swift               # 口座一覧画面
└── Views/
    ├── PassbookDetailView.swift   # 通帳画面
    ├── BookSearchView.swift       # 本の検索画面
    └── AddBookView.swift          # 手動登録画面
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
