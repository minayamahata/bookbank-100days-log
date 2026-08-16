# BookBank タイポグラフィ設計メモ（R4.6「LINE Seed 全面移行」）

作成日: 2026-08-16
更新日: 2026-08-16
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
- スプラッシュ、オンボーディング、Paywall など、従来 Inter / Fearlessly Authentic を使っていた箇所

対象外:

- iOS 共有シート、写真権限ダイアログ、キーボードなど、OS が所有する画面
- SF Symbols およびテンプレートアイコンのサイズ・ウェイト指定（`.font(.system(...))` はシステムフォントのまま）
- 見える文字ではない内部用途（メモ記号を 0.01pt＋透明で隠す指定など）
- Web 側（`bookbank-share`）
- スキーマ / DTO / リポジトリ公開契約 / 移行コード

## 使用ファイル（8つのみ）

オーナーが公式配布元から取得し、`dev/BookBank/BookBank/Fonts/` に格納したファイルだけを使う。
再ダウンロード・置換・改変はしない。実行ビットが付いているものがあるため、リソースとして 0644 相当に揃える。

| 言語 | Regular | Bold |
|------|---------|------|
| 日本語 | `LINESeedJP_A_OTF_Rg.otf` | `LINESeedJP_A_OTF_Bd.otf` |
| 英語 | `LINESeedSans_A_Rg.otf` | `LINESeedSans_A_Bd.otf` |
| 韓国語 | `LINESeedKR-Rg.otf` | `LINESeedKR-Bd.otf` |
| 繁体字 | `LINESeedTW_OTF_Rg.otf` | `LINESeedTW_OTF_Bd.otf` |

`Font.custom` / `UIFont(name:)` にはファイル名ではなく、OTF の内部 PostScript 名を使う。2026-08-16 実測:

| ファイル | PostScript 名 |
|----------|----------------|
| `LINESeedJP_A_OTF_Rg.otf` | `LINESeedJPApp_OTF-Regular` |
| `LINESeedJP_A_OTF_Bd.otf` | `LINESeedJPApp_OTF-Bold` |
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
| BookBank ワードマーク（英語） | LINE Seed Sans EN Bold |
| 金額・冊数・単位・その他のローカライズ文字 | `snapshot.locale` に対応するフォント |
| 数字・カレンダー日付 | 同じロケールフォント。計測と描画で同一の `UIFont` / `Font` を使う |

完成済みの BookBank ワードマーク SVG はリポジトリに無い。`icon-logo.svg` はシンボルであり文字ロゴではない。Fearlessly Authentic の字形をトレースしたり、自動で新しいロゴ SVG を作ったりしない。ワードマークは LINE Seed Sans EN Bold の文字で描く。完成 SVG が来たら差し替えは別作業。

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

LINE Seed の再配布条件・ライセンス文書はリポジトリ内に無い。文言は推測して作らない。

- 配布元: LINE Seed 公式（オーナーが公式配布から取得）
- リポジトリ格納日: 2026-08-16
- ファイル名: 上記 8ファイル
- ファイルに残る日付（取得日そのものではない）: JP 2024-11-04、Sans 2023-09-07、KR 2023-08-25、TW 2025-04-08

**App Store 提出前に、公式のライセンス文書を確認すること。** 画像への焼き込み（マンスリーログ共有 PNG）とアプリバンドルへの埋め込みの両方が許されるかを人間が確認する。
