# AI実装エージェント向け 実行ガイド

作成日: 2026-07-07
対象: 本リポジトリの設計書・ロードマップを実装するAIコーディングエージェント（Opus等）
位置づけ: **各設計書より優先して読むこと**。設計書の内容とこのガイドが矛盾する場合は、作業を止めてユーザーに確認する。

---

## 1. 文書の優先順位と読み方

1. **実行順序の正**: `docs/implementation-roadmap.md`（R1→R2→…の順。飛ばさない）
2. **各リリースの仕様の正**: ロードマップの各Rが参照する設計書
   - バグ修正 → `docs/bug-review-2026-07-06.md`
   - クラウド移行 → `docs/cloud-migration-architecture.md`
   - ノード機能 → `docs/node-graph-feature-design.md`
   - 発見機能 → `docs/discovery-feature-design.md`
   - マネタイズ → `docs/monetization-model-design.md`
   - 本棚内検索 → `docs/bookshelf-search-spec.md`
   - 読了リスト公開・埋め込み → `docs/embed-share-feature-design.md`
3. **UI実装の正**: `DESIGN_SYSTEM.md`（トークン・パターンから逸脱しない）
4. 無料/Unlimited境界の記述が文書間で食い違う場合は `docs/monetization-model-design.md` 第7章が正

## 2. 「(仮)」と複数案の解釈ルール（最重要）

設計書には「案A/B/Cの比較＋推奨(仮)」という形式が多用されている。これは人間（プロダクトオーナー）が選び直せるように残したものであり、**AIエージェントへの選択の委任ではない**。

- **(仮) が付いた推奨案 = 確定仕様として実装する**。他の案を選ばない・混ぜない
- 実装中に推奨案が技術的に成立しないと判明した場合（API廃止・OS制約等）は、**勝手に代替案へ切り替えず、作業を止めて状況と選択肢を報告する**
- 「実装時に判断」「実装時に確認」と書かれた箇所に到達したら、その判断内容を明示してユーザーに確認する（例: 移行設計書 3.4節の entitlement 保護方式、6.4節のリポジトリ統合）
- 数値パラメータ（k=8・M=30・IDF閾値25%・3票・quota=10 等）は設計書の値をそのまま定数化する。チューニングは指示があるまで行わない

## 3. スコープの規律

- **1タスク = ロードマップ表の1行**を基本単位とする。表の行に書かれていない改善・リファクタリング・コメント追加はしない（過去の修正依頼でも「指定項目以外に手を触れないこと」が一貫した運用ルール）
- 大型リリース（特にR4・R6）は、**着手前にタスク分解（実装順・ファイル一覧・リスク）を提示してユーザーの承認を得てから**コードに触る
- 設計書に無い仕様判断が必要になったら、小さくても止めて聞く。「たぶんこうだろう」で進めない

## 4. このプロジェクトの実装規約

### 4.1 構成

- iOSアプリ: このリポジトリの `dev/BookBank/`（Swift / SwiftUI / SwiftData / StoreKit 2）
- Webプロキシ・共有ページ: **別リポジトリ** `/Users/37/AYAME-Cursor/bookbank-share`（Next.js App Router + Upstash Redis + Vercel）。F系バグ・Web系タスクはこちら。コミットも別
- 状態管理は `@Observable` シングルトン（`UnlimitedManager` / `ExchangeRateService` 等）のパターンに合わせる

### 4.2 ローカライズ（毎回必須）

- ユーザー向け文字列は必ず `Localizable.xcstrings` にキーを追加し、**5言語（ja / en / ko / zh-Hans / zh-Hant）を同時に埋める**。ja だけ追加して他言語を残さない
- キー命名は既存に倣う（`bookshelf.search.placeholder` のようなドット区切り小文字）
- コードからの参照: SwiftUIの `Text("key")` / `LocalizedStringKey`、動的文字列は `L10n.string(_:)` / `L10n.format(_:_:)`。数値は `%lld`（`Int64` にキャスト）で統一
- 編集後は `python3 -m json.tool` でJSON妥当性を確認する

### 4.3 テスト・検証（完了の定義）

タスク完了と報告する前に、必ず以下を通すこと:

```bash
cd dev/BookBank
xcodebuild test -scheme BookBank -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:BookBankTests
```

- exit code 0 を確認する（3分前後かかる）
- リンタエラーが新規に出ていないこと
- ロードマップ各Rの「完了条件」のうち、**シミュレータ/コードで検証可能なものは検証する**。実機・課金サンドボックス・TestFlightが必要な項目は「人間の確認待ち」として明示的に残す
- ロジックを新設したら（例: `ShelfSearchMatcher`・シリーズ判定・スコア計算）、ユニットテストを同時に書く。純関数として切り出せる設計が各仕様書で指定されているのはこのため

### 4.4 Git

- コミットメッセージは日本語1行・変更の目的を書く（既存ログの体裁に合わせる。例: 「書籍検索の言語別DB化・総件数表示・ページング不具合の修正」）
- **コミット・プッシュはユーザーに指示されたときだけ**行う
- `UserInterfaceState.xcuserstate` はコミットに含めない
- `bookbank-share` 側の変更は別コミット（リポジトリが別）

### 4.5 ドキュメント同期

- バグを修正したら `docs/bug-review-2026-07-06.md` の状態列を「✅ 修正済み (日付)」に更新する
- ロードマップの項目を完了したら `docs/implementation-roadmap.md` に完了マークを付ける
- 実装が設計書と乖離したら、**コードではなく設計書側を直してから**進める（乖離の放置禁止）

## 5. AIには実行できない作業（人間タスク一覧）

以下に到達したら、実装せず「人間の作業が必要」とタスク名を挙げて報告する。ブロックされない部分の実装（コード側の受け皿）は先に進めてよい。

| リリース | 人間にしかできない作業 |
|---------|----------------------|
| R6（Phase 2） | Firebaseプロジェクト作成・Auth プロバイダー有効化（Apple/Google の証明書・OAuth設定）・`GoogleService-Info.plist` の取得と配置・Firestore/Storage の有効化・App Privacy（プライバシーラベル）の更新・法務文書の最終確認 |
| EM1（公開基盤） | Firebase Admin SDK 用サービスアカウントJSONの発行・`bookbank-share` 環境変数設定・法務文書（公開機能条項・プライバシーポリシー）の最終確認・UI翻訳（日英韓）のネイティブチェック・App Store Connect の公開URL設定 |
| EM2（埋め込み） | note・WordPress・はてな・NAVERブログでの埋め込み実地確認 |
| R7（D1） | Cloud Functions のデプロイ権限・Blazeプラン切替の判断 |
| R9（Phase 4） | App Store Connect での月額商品 `com.bookbank.platinum.monthly` 作成・買い切りの販売停止操作・RevenueCat アカウント作成とAPIキー・サンドボックステスト・審査提出 |
| R10（M3/D2） | チケットキャンペーンの企画・コード発行の運用判断 |
| R11（Phase 5） | Stripe/RevenueCat Web Billing 契約・特商法表記の記載事項確認 |
| 全リリース共通 | TestFlight配布・実機確認・App Store審査提出・段階的ロールアウトの操作 |

APIキー・シークレットは**コードに書かない**（既存方針どおり `bookbank-share` のサーバー環境変数、または Functions の環境変数。クライアントに埋め込まない）。

## 6. 報告の形式

各タスク完了時に以下を簡潔に報告する:

1. 何を変更したか（ファイルと要点）
2. テスト結果（コマンドと exit code）
3. 人間の確認・作業が必要な残項目
4. 設計書との乖離があれば、その内容とドキュメント側の修正
