# AGENTS.md

BookBank（iOSアプリ）のリポジトリ。100日チャレンジとして、日報・設計・コードを
1つのリポジトリで管理している。

役割（実装担当かレビュー担当か、コマンド実行やコミットの可否）は `CLAUDE.md` を見ること。
共通の約束（日本語で応答する／設計文書は `docs/` を正とする／指示されたスコープ外の
変更を先取りしない）も `CLAUDE.md` 側を正とする。**ここには写さない**——同じ文言を
2か所に置くと片方だけ古くなる。

## 作業前に読むもの

- `DEV_LOG.md` — 実装済み・未実装・現在のフェーズ（最優先）
- `docs/agent-implementation-guide.md` — (仮)の解釈・スコープ規律・テスト・人間タスクの扱い
- `docs/implementation-roadmap.md` — リリース単位（R4・R5…）とステップの並び
- 触る機能の設計メモ（例: メモのつながりなら `docs/memo-tagging-design.md`）

`docs/` 配下は最終仕様ではなく、思考整理のための事前設計。実装時に不備・矛盾・
改善点を見つけたら必ず指摘し、理由と具体的な代替案を示すこと。

## 進め方

- **実装の優先順位**: iOS / SwiftData として健全な設計が最優先。次に保守性・拡張性。
  「設計どおりに実装」は二の次
- **非エンジニアへの配慮**: 設計者は非エンジニア。技術的な説明はわかりやすい言葉と例えで書く
- 勝手にファイルを削除・リネームしない。影響の大きい変更は事前に確認を取る
- 作業の最後に「何が前進したのか」が分かる粒度で要約する
- 日付の判断は日本時間（JST）を基準にする。不明確なら推測せず確認を求める
- 日次ログは `days/DAY49.md` の形式（DAY＋連番、1ファイル1日）

## プロジェクト構成

```
BookBank-100days-log/
├── days/            # 100日チャレンジの日報
├── docs/            # 設計ドキュメント（事前設計）
├── DEV_LOG.md       # 開発状況まとめ（最優先参照）
├── Roadmap.md       # DAY54-100の開発計画
├── DESIGN_SYSTEM.md # 見た目の決まり（詳細版）
└── dev/BookBank/    # Xcodeプロジェクト
    └── BookBank/
        ├── Models/        # SwiftDataモデル
        ├── Repositories/  # DTOとリポジトリ（R4）
        ├── Utils/         # 純粋関数（パーサ・判定ロジック）
        └── Views/         # SwiftUI Views
```

Web側（共有API・書籍検索プロキシ・規約ページ）は別リポジトリ
`/Users/37/AYAME-Cursor/bookbank-share`（Next.js + Upstash Redis）。iOSの
`ShareService` / `RakutenBooksService` / `NaverBooksService` がこのAPIを使う。
**このワークスペースの外**にあるので、Web側のコードを読む必要があるときは
そのフォルダを別ウィンドウで開くこと。

## 技術スタック

Swift 5.0（MainActor デフォルト分離・Approachable Concurrency 有効）/ SwiftUI /
SwiftData / iOS 26.0以降 / Bundle ID `ayame-inc.BookBank` /
テストは Swift Testing（Unit）と XCTest（UI）/ 外部依存なし

## ビルドとテスト

```bash
cd dev/BookBank

# ビルド
xcodebuild build -scheme BookBank -configuration Debug

# テスト（実行先は固定）
xcodebuild test -scheme BookBank -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'

# 一部だけ（Swift Testing の関数名には () が要る）
xcodebuild test -scheme BookBank -only-testing:'BookBankTests/MemoQuoteGeometryTests' \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

**テストの実行方針**——毎回の全件テストは不要。変更の中身で判断すること。

- パーサ・判定ロジック（`Utils/` 配下の純粋関数。MemoLinkParser / MemoHiddenMarkers /
  MemoPageMarker / MemoTextBlocks / ShelfSearchMatcher など）に触れた回は全件実行
- ビューの見た目・レイアウト・アニメーションだけの変更は、ビルド確認のみでよい
- ステップやリリースの区切りでは全件実行する

テストを省略した回は、報告に「テストは省略（見た目のみの変更）」と明記すること。
検証済みと未検証の区別がつかなくなるのを防ぐため。

**実行環境**——iOS 26.5 / iPhone 17 に固定する。iOS 26.2 のシミュレータランタイムでは、
SwiftDataのインメモリ容器を使うテストクラスがテストホストごとクラッシュする既知事象がある
（`docs/implementation-roadmap.md`・コード側の問題ではない）。シミュレータがアプリを
起動できなくなったら（SpringBoardの RequestDenied）ビルド生成物の壊れを疑い、
`xcodebuild clean build` からやり直す。

## コードの約束

- 判定・変換のロジックはViewに書かず `Utils/` の純粋関数に出す。Viewに依存しない形なら
  ユニットテストで固定できる
- 配置: Models / Repositories / Utils / Views
- 命名: 型は PascalCase、変数・関数・定数は camelCase
- SwiftData: 取得・保存はリポジトリ（`Repositories/`）経由。`@Model` を直接扱うのは
  リポジトリ実装・移行コード・テスト／Preview に限る（R4で確立。View層は `@Query` を使わず
  DTOのみを扱う）。モデルを直接扱う側では、リレーションの比較は `persistentModelID` で行う
- 書いたら確認: 既存のモデル定義を尊重しているか／エラーハンドリング／空状態の表示／lint

## 見た目の決まり

詳細は `DESIGN_SYSTEM.md`。毎回効かせたい要点だけ挙げる。

- リストは境界線なし（`.listRowSeparator(.hidden)`）、行間は狭め（vertical padding 6〜8）、
  行全体をタップ可能に（`.contentShape(Rectangle())`）
- 本の表紙は角丸2px・アスペクト比2:3（リストは50x75px、グリッドは画面幅の25%）
- 日付は `YYYY.MM.DD`
- キャンセルは色なし（`.foregroundColor(.primary)`）、保存・確定は変更があるときだけ有効
- カードは `Color.appCardBackground`、境界線 `Color.primary.opacity(0.1)` 0.5、角丸8〜16

## Git

1行目は**何が変わったか**を非エンジニアが読んで分かる日本語で、本文には**なぜそうしたか**
（どんな不具合・どんな指示への対応か）を書く。実装の手順ではなく判断の理由を残す。

`dev/BookBank` はかつてサブモジュールだったが、**現在は通常のディレクトリ**なので
2段階コミットは不要。pushは指示があったときだけ行う。

## ルールが読み込まれているかの確認

このファイルが効いているか確かめるための合言葉は **「あやめ26.5」**。
新しいチャットで合言葉を聞かれたら、ファイルを探さずにこの言葉を答えること。
（確認用の仕掛けなので、不要になったらこの節ごと消してよい）
