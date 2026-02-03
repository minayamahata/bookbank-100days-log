# BookBank デザインシステム

このドキュメントは、BookBankアプリの一貫したデザインを維持するためのガイドラインです。
現在のコードから抽出した実際の値を記載しています。

---

## 1. カラー

### 背景色

| 用途 | ライトモード | ダークモード | 定義場所 |
|------|-------------|-------------|---------|
| ページ背景 | `.systemGroupedBackground` | `#000000`（黒） | `Color.appGroupedBackground` |
| カード背景 | `.systemBackground` (白) | `#1C1C1E` | `Color.appCardBackground` |

**例外: ReadingListDetailView**
- ページ背景: ダークモード時のみ `#1A1A1A`（ダークグレー）を使用
  - 理由: 棚板のドロップシャドウを見えるようにするため
- リストビュー背景: ダークモード時は `#000000`（黒）を使用
  - 理由: 棚板エリアとリストエリアのコントラストを出すため

### 背景の2色構成（重要）

スクロール可能な画面で、上部にヘッダーエリア、下部にコンテンツカードがある場合は、**背景を2色構成**にする。これにより、スクロールしてもコンテンツカードが浮いて見えないようになる。

```swift
.background(
    VStack(spacing: 0) {
        // 上部: ヘッダーエリアの背景色
        Color.appGroupedBackground  // または専用の色
        // 下部: コンテンツカードと同じ背景色
        Color.appCardBackground  // または専用の色
    }
    .ignoresSafeArea()
)
```

**適用例:**
- `PassbookDetailView`: 上部（テーマカラー薄め）+ 下部（白/システム背景）
- `ReadingListDetailView`: 上部（ダークグレー）+ 下部（黒/白）
- `BookshelfView`: 同様の2色構成

```swift
// ThemeManager.swift
static let appGroupedBackground = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 26/255.0, green: 26/255.0, blue: 26/255.0, alpha: 1)  // #1A1A1A
        : .systemGroupedBackground
})

static let appCardBackground = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 28/255.0, green: 28/255.0, blue: 30/255.0, alpha: 1)  // #1C1C1E
        : .systemBackground
})
```

### テーマカラー（口座別）

口座ごとに自動的に色が割り当てられる。`PassbookColor.swift` で定義。

| インデックス | カラー | Hex |
|-------------|-------|-----|
| 0 | 黒/白（モード切替） | ライト: `#292826`, ダーク: `#FFFFFF` |
| 1 | 赤 | `#FE2B2C` |
| 2 | オレンジ | `#FD8E0F` |
| 3 | 黄色 | `#FDD00E` |
| 4 | 緑 | `#30CD47` |
| 5 | シアン | `#33C6DD` |
| 6 | 青 | `#1398FF` |
| 7 | 紫 | `#B780FF` |
| 8 | ピンク | `#FD82C3` |

```swift
// 使用例
let themeColor = PassbookColor.color(for: passbook, in: customPassbooks)
```

### テキストカラー

| 用途 | カラー |
|------|-------|
| 主要テキスト | `.primary` |
| 補助テキスト | `.secondary` |
| 金額表示 | テーマカラー or `.blue` |
| 無効状態 | `.primary.opacity(0.4)` |

### オーバーレイ

| 用途 | 値 |
|------|---|
| モーダル背景 | `Color.black.opacity(0.5)` |
| カスタムダイアログ背景 | `Color.black.opacity(0.4)` |
| ボタン背景（薄い） | `Color.primary.opacity(0.1)` |
| ボタン背景（追加で薄い） | `Color.primary.opacity(0.05)` |

---

## 2. タイポグラフィ

### フォントサイズ一覧

| 用途 | フォント | 例 |
|------|---------|---|
| 大きな金額表示 | `.system(size: 32)` | 総資産 |
| 中程度の金額表示 | `.system(size: 22)` | カード内金額 |
| タイトル（大） | `.title2` + `.fontWeight(.bold)` | リスト詳細タイトル |
| タイトル（中） | `.title3` | 本の詳細タイトル |
| 見出し | `.headline` | カルーセルタイトル |
| 本文 | `.subheadline` | リスト行タイトル |
| 補助テキスト | `.footnote` | 説明文、冊数 |
| キャプション | `.caption` | 著者名、日付 |
| 小さいキャプション | `.caption2` | 登録済みバッジ |

### 金額表示の統一パターン

```swift
// 金額 + 「円」のレイアウト
HStack(alignment: .lastTextBaseline, spacing: 2) {
    Text("\(amount.formatted())")
        .font(.system(size: 20))  // サイズは用途による
    Text("円")
        .font(.system(size: 13))  // 金額の約65%サイズ
}
.foregroundColor(themeColor)
```

| 用途 | 金額サイズ | 円サイズ |
|------|----------|---------|
| 総資産（大） | 32pt | 18pt |
| カード内 | 22pt | 14pt |
| リスト詳細 | 20pt | 13pt |
| リスト行 | `.subheadline` | `.caption2` |

---

## 3. 間隔（Spacing）

### 標準padding

| 用途 | 値 |
|------|---|
| 画面の水平padding | `16px` |
| カード内padding | `16px` or `24px` |
| セクション間spacing | `32px` |
| リスト行の垂直padding | `8px` |
| リスト行の水平padding | `24px`（統一） |
| ボタン内padding（水平） | `16px` |
| ボタン内padding（垂直） | `10px` or `14px` |

### コンポーネント間spacing

| 用途 | 値 |
|------|---|
| VStack（大セクション） | `32px` |
| VStack（中セクション） | `16px` or `20px` |
| VStack（小セクション） | `8px` or `12px` |
| VStack（タイトル内） | `4px` |
| HStack（ボタン並び） | `8px` |
| グリッド（本棚） | `2px` |

### リスト行のInsets

```swift
// 標準的なリスト行
.listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
```

---

## 4. 角丸（Corner Radius）

| 用途 | 値 |
|------|---|
| 本の表紙（グリッド） | `2px` |
| 本の表紙（リスト） | `4px` |
| 検索バー | `10px` |
| 入力フィールド | `8px` |
| カード/ウィジェット | `12px` or `16px` |
| モーダル/ポップアップ | `24px` |
| コンテンツカード（上部のみ） | `40px` (topLeading/topTrailing) |
| ボタン（カプセル型） | `Capsule()` |

### UnevenRoundedRectangle の使用

ページ下部に配置されるコンテンツカードは上部のみ角丸を適用：

```swift
.clipShape(
    UnevenRoundedRectangle(
        topLeadingRadius: 40,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: 40
    )
)
```

---

## 5. 影（Shadow）

### 標準的な影

| 用途 | color | radius | x | y |
|------|-------|--------|---|---|
| カード影 | `.black.opacity(0.1)` | `2` | `0` | `1` |
| 本の表紙（グリッド） | `.black.opacity(0.1)` | `1` | `0` | `1` |
| 本の表紙（詳細） | `.black.opacity(0.5)` | `20` | `0` | `8` |
| カルーセル画像 | `Color.primary.opacity(0.2)` | `20` | `0` | `10` |
| モーダル | `.black.opacity(0.2)` | `20` | `0` | `10` |

### 本棚の棚板影（奥行き表現）

```swift
// 行によって変化する影
let shadowOpacity = 0.08 + (0.08 * depth)  // 0.08 〜 0.16
let shadowY: CGFloat = 4 + (6 * depth)     // 4pt 〜 10pt

.shadow(
    color: Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.3)
            : UIColor.black.withAlphaComponent(shadowOpacity)
    }),
    radius: 6,
    x: 3,
    y: shadowY
)
```

---

## 6. 本棚のデザイン

### 本の表紙

| プロパティ | 値 |
|----------|---|
| アスペクト比 | `2:3`（すべての表示で統一） |
| 角丸 | `2px`（すべての表示で統一） |

#### 用途別サイズ

| 用途 | サイズ | 備考 |
|------|-------|------|
| リストビュー | `50x75px` | 行に小さく表示 |
| グリッドビュー | `幅 × 1.5` | 動的計算、本棚表示 |
| 単体表示（カルーセル） | `140x210px` | 詳細表示 |

### 棚板（thumbnailGrid）

5カラム2列のグリッドで、奥行きを表現：

```swift
// 奥行き係数: 0.0（最上段）〜 1.0（最下段）
let depth = CGFloat(row) / CGFloat(max(totalRows - 1, 1))

// 棚板の高さと厚み
let shelfHeight: CGFloat = 6 + (4 * depth)      // 6pt 〜 10pt
let shelfThickness: CGFloat = 2 + (2 * depth)   // 2pt 〜 4pt
```

| プロパティ | ライトモード | ダークモード |
|----------|-------------|-------------|
| 棚板上面 | 白 | 黒 |
| 棚板側面 | `white: 0.92` | `white: 0.15` |
| 影 | 黒（opacity変動） | 黒（opacity: 0.3） |

### 3x3グリッドサムネイル（ReadingListView）

```swift
let spacing: CGFloat = 2
let cellWidth: CGFloat = (size - spacing * 2) / 3
let cellHeight: CGFloat = cellWidth * 1.5  // 本の比率 2:3
```

---

## 7. カルーセルのデザイン

### BookCarouselView

```swift
// カード幅は画面の65%
let cardWidth = geometry.size.width * 0.65
let spacing: CGFloat = 16

// スクロールトランジション
.scrollTransition { content, phase in
    content
        .scaleEffect(phase.isIdentity ? 1 : 0.85)
        .opacity(phase.isIdentity ? 1 : 0.7)
}
```

| プロパティ | 値 |
|----------|---|
| カード幅 | 画面幅の65% |
| カード間spacing | `16px` |
| 非アクティブカードのスケール | `0.85` |
| 非アクティブカードの透明度 | `0.7` |
| カルーセル高さ | `450px` |
| 本の表紙サイズ | `140x200px` |

---

## 8. モーダル/ポップアップのデザイン

### 標準シートモーダル

```swift
.sheet(isPresented: $showModal) {
    NavigationStack {
        // コンテンツ
    }
    .navigationTitle("タイトル")
    .navigationBarTitleDisplayMode(.inline)
}
```

### フルスクリーンモーダル

```swift
.fullScreenCover(isPresented: $isPresented) {
    // コンテンツ
}
```

### カスタムダイアログ（ReorderBooksView）

```swift
ZStack {
    // 背景オーバーレイ
    Color.black.opacity(0.4)
        .ignoresSafeArea()
    
    // ダイアログ本体
    VStack(spacing: 20) {
        // タイトルとメッセージ
        VStack(spacing: 8) {
            Text("タイトル")
                .font(.headline)
            Text("メッセージ")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        
        // ボタン
        VStack(spacing: 12) {
            // プライマリボタン
            Button { } label: {
                Text("確定")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.blue))
            }
            
            // セカンダリボタン
            Button { } label: {
                Text("キャンセル")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
    }
    .padding(24)
    .background(
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.appCardBackground)
    )
    .padding(.horizontal, 40)
}
```

### カルーセルポップアップ（BookCarouselView）

```swift
.background(
    RoundedRectangle(cornerRadius: 24)
        .fill(.ultraThinMaterial)
)
.overlay(
    RoundedRectangle(cornerRadius: 24)
        .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
)
.padding(.horizontal, 16)
.padding(.vertical, 60)
.shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
```

---

## 9. アニメーション

### 標準アニメーション

| 用途 | 値 |
|------|---|
| フェードイン | `.easeIn(duration: 0.2)` |
| フェードアウト | `.easeOut(duration: 0.2)` |
| タブ切り替え | `.easeInOut(duration: 0.2)` |
| トースト表示 | `.move(edge: .top).combined(with: .opacity)` |

### 使用例

```swift
// カルーセル表示
withAnimation(.easeIn(duration: 0.2)) {
    showBookCarousel = true
}

// カルーセル非表示
withAnimation(.easeOut(duration: 0.2)) {
    showBookCarousel = false
}
```

---

## 10. コンポーネントの使い分け

### 選択UI

| ユースケース | コンポーネント |
|------------|--------------|
| 少数の選択肢（2-4個） | `Menu` |
| 多数の選択肢 | `Picker` |
| フィルター切り替え | `Toggle` + カスタムスタイル |
| 口座選択 | `Menu` |
| 並べ替えオプション | `Menu` |

### Menuの使用例

```swift
Menu {
    ForEach(options, id: \.self) { option in
        Button(action: { selectedOption = option }) {
            if selectedOption == option {
                Label(option.rawValue, systemImage: "checkmark")
            } else {
                Text(option.rawValue)
            }
        }
    }
} label: {
    HStack(spacing: 4) {
        Image(systemName: "arrow.up.arrow.down")
        Text(selectedOption.rawValue)
            .font(.system(size: 13))
    }
}
```

### ボタンスタイル

| 用途 | スタイル |
|------|---------|
| プライマリアクション | カプセル型 + 青背景 + 白文字 |
| セカンダリアクション | カプセル型 + `Color.primary.opacity(0.1)` + primary文字 |
| テキストボタン | `.plain` + `.foregroundColor(.primary)` |
| 破壊的アクション | `.destructive` role |

### ツールバーボタン（重要ルール）

モーダル/編集画面のキャンセル・保存ボタンは以下のルールに従う：

| ボタン | テキストカラー | 状態 |
|-------|--------------|------|
| キャンセル | `.primary`（色なし） | 常にアクティブ |
| 保存 | 変更あり: `.blue` / 変更なし: `.primary.opacity(0.4)` | 変更時のみアクティブ |

**適用画面:**
- 口座編集（EditPassbookView）
- 読了リスト編集（EditReadingListView）
- その他すべての編集モーダル

```swift
// キャンセルボタン（色なし）
ToolbarItem(placement: .cancellationAction) {
    Button("キャンセル") { dismiss() }
        .foregroundColor(.primary)
}

// 保存ボタン（変更時のみアクティブ）
ToolbarItem(placement: .confirmationAction) {
    Button("保存") { save() }
        .disabled(!hasChanges || title.isEmpty)
        .foregroundColor(hasChanges && !title.isEmpty ? .blue : .primary.opacity(0.4))
}
```

**変更検知の実装パターン:**

```swift
// 元の値を保存
@State private var originalName: String = ""
@State private var originalColorIndex: Int = 0

// 変更があるかどうか
private var hasChanges: Bool {
    name != originalName || colorIndex != originalColorIndex
}

// initで初期化
init(item: Item) {
    _name = State(initialValue: item.name)
    _originalName = State(initialValue: item.name)
}
```

---

## 11. リスト表示

### 基本ルール

| プロパティ | 値 |
|----------|---|
| 境界線（Divider） | **なし**（必ず非表示にする） |
| リスト間のspacing | `0`（LazyVStackで指定） |
| 行の垂直padding | `8px`（実質16pxの行間） |
| 行の水平padding | `24px` |

### LazyVStack を使用する場合（推奨）

```swift
LazyVStack(spacing: 0) {
    ForEach(items) { item in
        itemRow(item)
    }
}

// 各行のスタイル
.padding(.horizontal, 24)
.padding(.vertical, 8)
.contentShape(Rectangle())  // 行全体をタップ可能に
```

### List を使用する場合

```swift
List {
    // コンテンツ
}
.listStyle(.plain)
.listRowSeparator(.hidden)  // 境界線を非表示
.scrollContentBackground(.hidden)
.background(Color.appCardBackground)
```

### List 行の標準スタイル

```swift
.listRowBackground(Color.appCardBackground)
.listRowSeparator(.hidden)  // 境界線を非表示
.listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
```

### 行全体をタップ可能に

```swift
.contentShape(Rectangle())
```

---

## 12. 空状態（Empty State）

### 標準パターン

```swift
VStack(spacing: 16) {
    Image(systemName: "books.vertical")
        .font(.system(size: 60))
        .foregroundColor(.gray)
    
    Text("本棚が空です")
        .font(.headline)
        .foregroundColor(.secondary)
    
    Text("先に本を登録してください")
        .font(.subheadline)
        .foregroundColor(.secondary)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

---

## 13. トースト通知

### ToastView

```swift
Text("\(amount.formatted())円 入金しました！")
    .font(.system(size: 13))
    .foregroundColor(.white)
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .glassEffect(.regular.tint(themeColor))
    .clipShape(Capsule())
```

### 表示・非表示

```swift
// 表示
withAnimation {
    showToast = true
}

// 2秒後に非表示
Task {
    try? await Task.sleep(for: .seconds(2))
    withAnimation {
        showToast = false
    }
}
```

---

## 14. 日付フォーマット

### 統一フォーマット

```swift
private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy.MM.dd"
    return formatter.string(from: date)
}
```

出力例: `2026.01.31`

---

## 15. アイコンサイズ

| 用途 | サイズ |
|------|-------|
| チェックボタン | `20px` |
| 削除ボタン | `18px` |
| 閉じるボタン（xmark） | `.title3` or `.body` |
| 口座アイコン | `20x20px` |
| 空状態アイコン | `60px` |
| バーコードアイコン | `20px` |

---

## 16. LiquidGlass ボタン

iOS標準の`glassEffect`を使用した登録ボタン：

```swift
struct LiquidGlassButton: View {
    let color: Color
    let size: CGFloat = 56
    
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 16))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(color))
            .clipShape(Circle())
    }
}
```

---

## 17. キーボード（重要ルール）

### 入力エリア外タップでキーボードを閉じる

テキスト入力がある画面では、**入力エリア以外をタップしたらキーボードを閉じる**ようにする。

```swift
// View全体に適用
.onTapGesture {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
```

**適用画面:**
- 口座編集（EditPassbookView）
- 読了リスト編集（EditReadingListView）
- 手動登録（AddBookView）
- 口座追加（AddPassbookView）
- その他すべてのテキスト入力画面

### キーボードによるレイアウト崩れを防ぐ

画面下部に固定要素（削除ボタンなど）がある場合、キーボード表示時にせり上がらないようにする。

```swift
.ignoresSafeArea(.keyboard, edges: .bottom)
```

---

## 更新履歴

- 2026.02.02: 初版作成
