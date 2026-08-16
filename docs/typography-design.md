# BookBank タイポグラフィ設計メモ（R4.6「LINE Seed 全面移行」）

作成日: 2026-08-16
更新日: 2026-08-16（日本語の通常 SwiftUI 画面だけ `lineSpacing(1)`。共有 PNG と他言語は 0）
ステータス: **実装済み（2026-08-16）**
関連文書:

- `DESIGN_SYSTEM.md`（見た目の正。タイポグラフィ節は本書に同期する）
- `docs/monthly-log-share-design.md`（共有画像の文字）
- `docs/implementation-roadmap.md`（R4.6 の項目定義）
- `docs/agent-implementation-guide.md`
- `docs/r4-repository-abstraction-notes.md`（View は DTO のみ。データ層は触らない）

---

## 目的

BookBank が所有・描画する文字を、対応言語ごとの LINE Seed Regular / Bold へ統一する。
見た目のブランドを揃えつつ、Dynamic Type・混在言語の欠字回避・R6（クラウド移行）との非干渉を守る。

## 対象範囲

対象（アプリが所有する文字）:

- SwiftUI で表示するアプリ内 UI
- ナビゲーションタイトル
- ボタン、ラベル、入力欄
- 本のタイトル、著者、メモなどのユーザーデータ表示
- UIKit 製の `MemoEditorTextView`
- マンスリーログ共有画面
- `ImageRenderer` で生成する透明 PNG 4種
- スプラッシュ、オンボーディング、Paywall など、従来 Inter / Fearlessly Authentic を使っていた箇所（スプラッシュ中央のワードマークは `img_splash_logo.svg`）

対象外:

- iOS 共有シート、写真権限ダイアログ、キーボードなど、OS が所有する画面
- SF Symbols およびテンプレートアイコンのサイズ・ウェイト指定（`.font(.system(...))` はシステムフォントのまま）
- 見える文字ではない内部用途（メモ記号を 0.01pt＋透明で隠す指定など）
- Web 側（`bookbank-share`）
- スキーマ / DTO / リポジトリ公開契約 / 移行コード

## 使用ファイル（8つのみ）

`dev/BookBank/BookBank/Fonts/` に格納したファイルだけを使う。リソース権限は 0644 相当。

| 言語 | Regular | Bold | 入手元 |
|------|---------|------|--------|
| 日本語 | `LINESeedJP-Regular.ttf` | `LINESeedJP-Bold.ttf` | Google Fonts 公式（上流 2025年版 v1.008） |
| 英語 | `LINESeedSans_A_Rg.otf` | `LINESeedSans_A_Bd.otf` | 公式配布パッケージ |
| 韓国語 | `LINESeedKR-Rg.otf` | `LINESeedKR-Bd.otf` | 公式配布パッケージ |
| 繁体字 | `LINESeedTW_OTF_Rg.otf` | `LINESeedTW_OTF_Bd.otf` | 公式配布パッケージ |

日本語だけを Google Fonts 公式の新しいビルドへ差し替えた。英語・韓国語・繁体字は公式配布パッケージ版のまま維持する。簡体字ファイルはバンドルせず、PingFang SC／システムフォントを使う。

日本語の取得元:

- ディレクトリ: https://github.com/google/fonts/tree/main/ofl/lineseedjp
- Regular: https://raw.githubusercontent.com/google/fonts/main/ofl/lineseedjp/LINESeedJP-Regular.ttf
- Bold: https://raw.githubusercontent.com/google/fonts/main/ofl/lineseedjp/LINESeedJP-Bold.ttf
- メタデータ: https://github.com/google/fonts/blob/main/ofl/lineseedjp/METADATA.pb
- ライセンス: https://github.com/google/fonts/blob/main/ofl/lineseedjp/OFL.txt（SIL OFL 1.1）

`Font.custom` / `UIFont(name:)` にはファイル名ではなく、内部 PostScript 名を使う。ファイル名と PostScript 名を混同しない。2026-08-16 実測:

| ファイル | PostScript 名 |
|----------|----------------|
| `LINESeedJP-Regular.ttf` | `LINESeedJP-Regular` |
| `LINESeedJP-Bold.ttf` | `LINESeedJP-Bold` |
| `LINESeedSans_A_Rg.otf` | `LINESeedSansApp-Regular` |
| `LINESeedSans_A_Bd.otf` | `LINESeedSansApp-Bold` |
| `LINESeedKR-Rg.otf` | `LINESeedSansKR-Regular` |
| `LINESeedKR-Bd.otf` | `LINESeedSansKR-Bold` |
| `LINESeedTW_OTF_Rg.otf` | `LINESeedTW_OTF-Regular` |
| `LINESeedTW_OTF_Bd.otf` | `LINESeedTW_OTF-Bold` |

使用ウェイトは Regular と Bold の 2段階だけ。存在しないウェイトを合成しない。

| 既存の指定 | 割り当て |
|------------|----------|
| thin / light / regular / medium | Regular |
| semibold / bold / heavy / black | Bold |

## 言語ごとの割り当て

`AppLanguage.effective`（「システム設定に従う」なら `AppLanguage.inferred()`）で選ぶ。

| 実効言語 | フォント |
|----------|----------|
| Japanese | LINE Seed JP |
| English | LINE Seed Sans EN |
| Korean | LINE Seed KR |
| Traditional Chinese | LINE Seed TW |
| Simplified Chinese | iOS 標準の PingFang SC。無ければシステムフォント |

簡体字へ繁体字用の LINE Seed TW を流用しない。簡体字と繁体字は字形が違うため、TW を当てると不自然な繁体字形が出る。LINE Seed の簡体字ファイルは今回の 8ファイルに含まれない。

アプリ内設定で言語を切り替えたら、再起動しなくても可能な範囲で表示フォントが追従する。
SwiftUI は `environment(\.locale)` の再描画時に共通 API を再評価する。UIKit のメモ編集は `updateUIView` で描画用フォントを当て直す。ナビバーは `UINavigationBar.appearance()` を言語変更時に再設定する（既に表示中のバーへは即時反映されない制約あり。後述）。

## 混在言語のフォールバック

書名やメモは UI 言語と異なる文字を含む。文字列を言語判定で分割しない。
1つのフォントを指定し、字形が無い文字は iOS / Core Text の標準フォールバックに任せる。欠字や豆腐を出さないことを、言語ごとの見た目の完全一致より優先する。

## Dynamic Type

- 意味付きスタイル（`.largeTitle` … `.caption2`）のサイズ階層は維持する
- iOS の `.headline` は強調（従来 semibold）なので、共通 API では headline の既定ウェイトを Bold にする
- 固定 pt 指定は、見た目を極端に変えず `relativeTo:` / `UIFontMetrics` で Dynamic Type に追従させる
- **共有画像は例外**: 1080×1920 の固定ピクセル出力なので Dynamic Type は掛けない。ユーザーの文字サイズで画像レイアウトが壊れないようにする

## 行送り（日本語はフォント差し替えで解消する）

2024年の公式配布 ZIP に含まれる App 用 OTF（`LINESeedJP_A_OTF_Rg.otf` / `LINESeedJP_A_OTF_Bd.otf`、PostScript 名 `LINESeedJPApp_OTF-Regular` / `LINESeedJPApp_OTF-Bold`）は、文字本体の大きさが Google Fonts 公式 TTF と同じでも、上下の見えない領域が大きい。

17pt での実測（Regular。cap height は Regular 約 12.77pt、Bold 約 12.89pt で両ビルドとも同じ）:

| 項目 | 2024年 App 用 OTF | Google Fonts 公式 TTF |
|------|-------------------|------------------------|
| ascender | 約 19.58pt | 約 15.84pt |
| descender | 約 7.79pt | 約 2.86pt |
| leading | 0pt | 0pt |
| 行高 | 約 27.37pt | 約 18.70pt |

`leading(.tight)` では ascender／descender を変えられない。両フォントとも leading は 0 なので、実機ではほぼ変化がなかった。`leading(.loose)` も、この LINE Seed JP では 1行・複数行ともレイアウト寸法が変わらない。どちらも採用しない。

正しい対応は、日本語だけを Google Fonts 公式の新しいビルドへ差し替えること。文字サイズ、semantic text style、リストやカードの padding、VStack／HStack の spacing、`baselineOffset`、frame、clipping は変えない。

差し替え後の 17pt 行高は約 18.70pt（SwiftUI 上はおおむね 19pt）。SF Pro の 17pt は約 20.0pt。複数行が少し詰まりすぎて見えるため、**日本語の通常 SwiftUI 画面だけ** `lineSpacing(1)` をルートで一度適用する。

- 1行テキストの高さ、文字サイズ、字形、外側余白、ボタンのタップ領域、リスト／カードの padding は変わらない（行と行の間だけ +1pt）
- 英語・韓国語・繁体字・簡体字は 0pt
- 「システム設定に従う」は `AppLanguage.inferred()` へ解決してから判定する。アプリ内の言語変更は再起動なしで追従する
- マンスリーログ共有キャンバスは `lineSpacing(0)` で固定し、通常 UI の値を継承しない
- UIKit（`MemoEditorTextView` / `uiFont` / ナビバー / `NSParagraphStyle`）は今回変更しない
- Dynamic Type の倍率を行間へ重ねない。行間は 1pt 固定

英語・韓国語は公式配布パッケージのまま（行ボックスは JP App 用 OTF ほど極端ではない）。繁体字は現在の公式 TW フォントを維持し、行高の実機確認は人間タスクとして残す。簡体字は PingFang SC のまま。

## SwiftUI と UIKit の共通化

`Utils/AppTypography.swift` に一元化する。

- 言語選択（`AppLanguage` / `Locale`）
- Regular / Bold
- SwiftUI `Font`（`Font.app` / `Font.appFixed`）
- UIKit `UIFont`（`UIFontMetrics` 付き）
- semantic text style
- 固定サイズ＋ Dynamic Type 基準
- 簡体字のシステムフォールバック

View はフォント名を直接書かない。メモ編集と共有画像の計測も同じ定義を使う。

## メモ編集（`MemoEditorTextView`）

表示用フォントだけを共通定義へ置き換える。パーサとメモ本文の保存形式は変更しない。

維持するもの: 本文 Regular、太字 Bold、引用、リンク装飾、ページ番号、隠し記号、キャレット、行間、保存→再編集、Dynamic Type、既存テスト。

変更する判断:

- 従来の太字は「`bold` では差が弱い」ため `.heavy` を合成していた。LINE Seed には Heavy が無いので、実在する Bold 面を使う（擬似 Bold / Heavy 合成をしない）
- ページ番号の `.medium` は Regular へ割り当てる
- 記号を隠す 0.01pt のシステムフォントは残す。見える文字ではなく、幅を潰す内部用途のため
- `textContainerInset` の更新は `NSTextStorage.beginEditing()` の外で行う。LINE Seed の行高で先頭引用の inset が変わり、編集中に layoutManager が動いて落ちたため。余白の量そのものは変えない

## マンスリーログ共有画像

| 対象 | フォント |
|------|----------|
| 月名・曜日（英語固定） | LINE Seed Sans EN |
| BookBank ワードマーク | `img_bookbank_logo.svg`（Fearlessly Authentic の字形。高さ 18／22pt） |
| 金額・冊数・単位・その他のローカライズ文字 | `snapshot.locale` に対応するフォント |
| 数字・カレンダー日付 | 同じロケールフォント。計測と描画で同一の `UIFont` / `Font` を使う |

スプラッシュの「BookBank your mind」は `img_splash_logo.svg`、共有画像の「BookBank」は `img_bookbank_logo.svg`（いずれもオーナー提供・Fearlessly Authentic の字形）を使う。`icon-logo.svg` はシンボルであり文字ロゴではない。Fearlessly Authentic の字形をこちらでトレースしたり、新しいロゴ SVG を自動生成したりしない。

維持: 1080×1920、透明 PNG、4テンプレート、セル 2:3、4〜6行月、日曜始まり／月曜始まり。
`MonthlyLogShareView.swift` の未コミットのレイアウト・カルーセル・トースト変更は残す。

## システム UI と SF Symbols

変更しない。`Image(systemName:)` やテンプレートアイコンに付いている `.font(.system(...))` はアイコンのサイズ指定であり、本文フォントではない。

## 旧フォントを削除する条件

次をすべて満たしてから削除する。

- コード内の `Fearlessly Authentic` / `Inter-Regular` / 旧 `UIAppFonts` 参照がゼロ
- ビルドが通る
- テストで未使用を確認できる
- ビルド済み `.app` に Inter / Fearlessly が含まれない

削除対象:

- `Fonts/Fearlessly Authentic OTF.otf`
- `Fonts/Fearlessly Authentic Italic OTF.otf`
- `Fonts/Inter-Regular.otf`
- `Info.plist` の上記 3ファイル登録
- `BookBankApp` の Fearlessly / Inter 限定デバッグ列挙

## Markdown プレビューの例外

`MarkdownExporter` のコードプレビューは、VSCode 風の等幅表示が目的の画面である。ここだけ `.system(size: 11, design: .monospaced)` を残す。本文 UI のブランドフォントへ寄せると、エクスポート内容の「コード」としての可読性が落ちる。プレビュー見出しやダウンロードボタンなど、コードブロックの外の文字は LINE Seed へ移す。

## ナビバーの言語追従

`BookBankApp.configureNavigationBarAppearance()` を共通タイポグラフィへ移し、言語変更時に再設定する。
`UINavigationBar.appearance()` は既に画面上にあるバーへは即時反映されないことがある。新しい画面を開くか、バーが再生成されるまで、タイトルフォントが前の言語のまま残る制約がある。タイトルサイズ（15pt・Regular、従来の subheadline 相当）は変えない。

## R6 への影響

なし。スキーマ・DTO・リポジトリ・移行コードは変更しない。フォントはバンドル内の描画リソースだけを替える。

## 人間タスク

日本語 Google Fonts 版の OFL テキストは公式リポジトリで公開されている（上記 URL）。英語・韓国語・繁体字の公式配布パッケージ側の再配布条件は、リポジトリ内にライセンス文書が無い。文言は推測して作らない。確認できていない言語を完了扱いにしない。

- 日本語: Google Fonts `ofl/lineseedjp`（SIL OFL 1.1、© LY Corporation）。格納日 2026-08-16
- 英語・韓国語・繁体字: オーナーが公式配布パッケージから取得。ファイルに残る日付（取得日そのものではない）: Sans 2023-09-07、KR 2023-08-25、TW 2025-04-08
- 簡体字: システムフォント（PingFang SC）

**App Store 提出前に、各フォントの公式ライセンス文書を確認すること。** 画像への焼き込み（マンスリーログ共有 PNG）とアプリバンドルへの埋め込みの両方が許されるかを人間が確認する。

そのほか実機確認（自動テストで完了扱いにしない）:

- 日本語のリスト行が以前より自然な高さになったこと
- 2行以上の書名や説明文、書籍詳細、設定、Paywall、オンボーディング
- 日本語の行間が約 1pt だけ広がっていること、広がりすぎていないこと
- 1行のリストやボタンの高さが変わっていないこと
- Dynamic Type 標準／最大付近、文字の上下欠け、行の重なり、タップ領域
- 英語・韓国語・繁体字・簡体字の行間が変わっていないこと
- MemoEditor は今回変わっていないこと
- マンスリーログ共有 PNG の文字配置が変わっていないこと
- 繁体字 UI の行高
