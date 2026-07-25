# R4 ステップ3（Passbook切替）独立レビュー 指摘と修正引き継ぎ

作成日: 2026-07-25
位置づけ: 未コミットのステップ3差分（22ファイル＋新規 `PassbookModelLookup.swift`）に対する独立レビューの結果と、その修正方針の引き継ぎ。**本書はレビュー結果の記録であり、実装は含まない**（修正は別環境で実施）。
関連文書:

- `docs/r4-repository-abstraction-notes.md`（R4設計メモ。本レビューの突合基準＝第7章ステップ3・4.4節・5.1/5.4節・8.2/8.3節）
- `docs/agent-implementation-guide.md`（スコープ規律・テスト・Git規約）
- `docs/r3-uuid-migration-notes.md`（uuidバックフィルの前提。#2に関係）

レビュー時点の状態: ビルド成功・テスト98件パス（destination `iPhone 17`・OS未指定）。以下の指摘はすべて**テストが通った上で残っている**問題である。

---

## 0. 総評

切替そのものは設計どおり実施されている。

- `@Query(sort: \Passbook.sortOrder)` の残存ゼロ
- 削除2経路（`PassbookListView` のcascade任せ／`EditPassbookView` の明示delete）の `deletePassbook` への集約
- `persistentModelID` → `uuid` の置換
- `PassbookColor.color(for:in:)` / `isBlackTheme(for:in:)` のDTO化

以下は、その上で見つかった論点である。

---

## 1. 優先度まとめ

| # | 内容 | 区分 | 深刻度 | 扱い |
|---|------|------|:---:|------|
| 1 | `EditPassbookView.onAppear` の色フォールバックが死に、誤った `colorIndex=0` が永続化されうる | 確認項目（口座色解決） | 🔴 高 | 今回修正 |
| 2 | マイグレーション書き込みがチェンジパルスを通らず、ストリームがバックフィル前uuidを掴みうる | 触らないもの（起動シーケンスとの相互作用） | 🟠 中（要検証） | 今回修正 |
| 3 | 書籍系画面のテーマカラーが初回フレームで青／黒テーマ判定false | 確認項目（見た目不変） | 🟠 中 | 今回修正 |
| 4 | `deletePassbook` が `deleteBook` の `bookIds` 掃除を通らない | 削除セマンティクス統一 | 🟠 中 | **ステップ4送り** |
| 5 | `PassbookModelLookup` 失敗時のサイレント無保存（ログなし） | 新規失敗モード | 🟠 中 | 今回はOSLogのみ／構造対応はステップ4送り |
| 6 | ステップ3がテストを1件も追加していない／設計メモの確認欄が担保範囲を過大表示 | 確認項目全般 | 🟠 中 | 今回修正 |
| 7 | 未使用 `modelContext` 削除がステップ6の先取り（8.3節-2違反） | 触らないもの（スコープ） | 🟡 低 | 設計メモで追認 |
| 8 | 選択状態のID化が `BookSearchView` / `BookSearchDestination` で未統一 | 確認項目（選択状態のuuid化） | 🟡 低 | 今回修正 |
| 9 | デッドコード画面に `@Query` を新規追加している | 触らないもの（スコープ） | 🟡 低 | 今回修正（撤回） |
| 10 | `savePassbook` の書き戻し範囲拡大・プレビュー後退2件・設計メモの記載漏れ2件 | 記録事項 | 🟡 低 | 設計メモに記録 |

---

## 2. 【今回修正】の実装メモ

### #1 口座色のリスト位置フォールバックが機能していない 🔴

**現象**: `Views/EditPassbookView.swift:228-235` の `.onAppear`

```swift
.onAppear {
    if passbook.colorIndex == nil {
        if let index = customPassbooks.firstIndex(where: { $0.id == passbook.id }) { ... }
    }
}
```

`customPassbooks` の元になる `allPassbooks` は同ファイル32行で `@State ... = []` になり、値が入るのは `.task` のストリーム受信後。`.onAppear` は1回きりで、ストリーム初回値の到達より前に走る（`for await` の再開は必ず別のMainActorジョブになるため）。**このフォールバックは実質デッドコードになっている。** 旧コードは `@Query` だったため `onAppear` 時点で全口座が揃っており、確実に動いていた。

**影響**（`colorIndex == nil` の旧データ口座のみ）:

- 色パレットの選択枠が「リスト位置由来の色」ではなく常に index 0 に当たる（`selectedColorIndex` の宣言時初期値 0 のまま）
- `originalColorIndex` も 0 のままなので、名前だけ変えて保存すると（保存ボタンは同307行で `hasChanges` ガード）、`savePassbook`（同415行）が `colorIndex = 0` を**永続化**し、口座の色が変わる

**修正方針**:

- 判定を `.onAppear` から `.task` のループ内（`allPassbooks = value` の直後）へ移す
- `hasResolvedDefaultColor` 相当のフラグで**初回値でのみ適用**する。2回目以降のyieldや、利用者が既に選んだ色を上書きしないため（フラグは初回yieldで無条件に立て、その内側で `colorIndex == nil` を判定する形が決定的）
- 位置解決を純関数へ切り出すとテストが書ける。例: `PassbookColor.resolvedDefaultColorIndex(for:in:) -> Int?`

**テスト**（#6と兼ねる）:

- `resolvedDefaultColorIndex(for:in: [])` が **nil** を返す ＝ ストリーム未到達時に `colorIndex` を確定しないことの固定。これが「0誤永続化を防ぐ」の直接的な担保になる
- リスト到達後は位置由来のindexを返す／`colorIndex` が既に設定済みなら nil を返す
- リポジトリレベル: `colorIndex == nil` の口座に解決済みindexを適用して `updatePassbook` → 読み戻して 0 ではなく位置indexであること

**設計メモの補正**: ステップ3の確認欄「口座色はDTOのみ」は、`colorIndex == nil` 時のリスト位置フォールバックがDTO単体では解決できない（口座リスト全体が要る）点を見落としている。

---

### #2 マイグレーションの書き込みがチェンジパルスに乗らない 🟠（要検証）

**現象**: コード変更ではなく構造上の相互作用。

設計メモ4.3節 案Aは「リポジトリを介さない書き込みを検知できない」弱点を認めた上で、「R4完了時点で書き込みは全てリポジトリ経由になるため成立する」としている。しかし**前提7でマイグレーション3種は永久にリポジトリを介さない**と決めており、その例外が考慮されていない。

1. `AppRepositories` は `BookBankApp.swift:89` でアプリ初期化時に生成される
2. 子View（`MainTabView` 等）の `.task` は、親（`RootView`）の `onAppear` より先に走りうる（SwiftUIのappearは子→親）
3. `Utils/UUIDBackfillMigration.swift:88` は `Passbook.uuid` を書き換えて `context.save()` するが、**`pulse.notify()` は呼ばない**
4. → ストリームが先に emit していた場合、View側は「バックフィル前のuuid」を持ったDTOを保持し続ける（次のリポジトリ書き込みまで更新されない）

旧実装の `@Query` は mainContext の save を自動検知するため、この経路は自己修復していた。**このセーフティネットがステップ3で外れている。**

**影響範囲**: R3未浸透の端末が初めてR4版を起動した瞬間に限られる（`hasCompleted` が立っていれば `migrateIfNeeded` は即return）。ただしバックフィル前のuuidは空文字や全行同一になりうる（R3設計メモ4.2の落とし穴そのもの）ため、その状態のDTOを掴むと:

- `allBooks.filter { $0.passbook?.uuid == passbook.id }` が別口座の本を拾う（冊数・金額・通帳内容が誤る）
- `PassbookModelLookup.fetch` が別口座を返す → 本が誤った口座に登録される
- `deletePassbook(id:)` が**誤った口座とその所属本を削除する**（不可逆）

**修正方針**:

- `RepositoryChangePulse` は各リポジトリの `private let` なので、`AppRepositories` に共有pulseを保持させて `notifyExternalChange()` を生やすのが最小
- 指定イニシャライザに `pulse` 引数が増えるため `BookBankTests/RepositoryFoundationTests.swift:24-29` の呼び出し更新が必要
- 発火位置は `BookBankApp.swift:195-207` のマイグレーション3種＋バックアップ削除の**直後**（`PreviewRuntime.isActive` の早期returnより後）
- **マイグレーション側は無改造**で済むため前提7を維持できる

**テスト**: 生の `ModelContext` で `uuid` を書き換え → `notifyExternalChange()` → ストリームが新値をyield。バックフィル競合をそのまま再現できる。

---

### #3 書籍系画面のテーマカラーが初回フレームで青になる 🟠

**現象**: `Views/UserBookDetailView.swift:53-71` / `Views/EditBookView.swift:28-37`

- 旧: `if let passbook = book.passbook`（@Modelリレーション＝初回body評価で即取得可）
- 新: `book.passbook?.uuid` を `allPassbooks`（ストリーム）から引き直す → **初回フレームは必ず nil → `.blue` / `isBlackTheme == false`**

書籍詳細はテーマカラーが画面の大面積を占めるため、黒テーマ口座の本を開くと「青→黒」の切り替わりが見える疑いがある。設計メモ5.1節/8.2節が挙げた「初回bodyが空配列」問題は `MainTabView.emptyStateView`（553行）と `HomeView`（48行）では `hasLoadedPassbooks` ガードで対処されているが、**テーマカラー経路には同じ対処が入っていない**。

**修正方針**: `hasLoadedPassbooks` を追加し、**未ロード時のみ** `book.passbook`（ステップ4まで @Model のまま＝ハイブリッド）から解決し、ストリーム到達後はストリーム値を使う。これが現行の見た目を正確に保てる。

**判断が要る点**: `UserBookDetailView` は設計メモ8.4節のクラッシュ当該画面であり、削除済み @Model のフィールド読み取りを増やす方向になる。現状も `book.passbook?.uuid` は読んでおり増分は小さい、という整理は可能だが、8.4節の趣旨（生の PersistentModel をViewが読む構造を減らす）とは逆行するため、意識的に選ぶこと。

**残課題（今回では解けない）**: `colorIndex == nil` 口座のリスト位置フォールバックは、未ロード時には口座リスト全体が無いため解決できない。この場合は初回フレームで `.gray` になる。`PassbookDetailView` / `BookshelfView` / `StatisticsView` / `BookSearchView` も同じ残課題を持つ（`PassbookColor.swift:105-107`）。ステップ7の目視スモーク項目として明記すること。

**検証手順への申し送り**: この種の1フレーム差はステップ7のスクリーンショット比較（静止画）では検出できない。目視スモークの明示項目にすること。

---

### #5 `PassbookModelLookup` 失敗時のサイレント無保存（今回はOSLogのみ）🟠

**現象**: `Views/AddBookView.swift:396-400` / `Views/BookSearchView.swift:1006-1007`

```swift
guard let targetDTO = selectedPassbook,
      let targetPassbook = PassbookModelLookup.fetch(id: targetDTO.id, context: context) else { return }
```

lookup が nil を返すと**保存を試みずに黙って return** する。旧コードは `selectedPassbook` が @Model 参照そのものだったため、この失敗モード自体が存在しなかった。設計メモ4.5節の「失敗を静かに飲む」は *save失敗* の話であり、ここは「保存を試行すらしない」新規経路である。発生条件（uuid不整合、画面を開いたまま口座が削除された、#2のマイグレーション競合）は稀だが、**ユーザーには「登録ボタンが効かない」としか見えず、ログも残らない**。他のリポジトリ実装（`updatePassbook` / `updateBook`）が not-found を `logger.error` で記録しているのと非対称。

**修正方針（今回）**: `Repositories/PassbookModelLookup.swift` 内に logger を置き、fetch失敗（throw）と該当なし（empty）を区別して記録する。これで呼び出し3箇所（`AddBookView:398` / `BookSearchView:1007` / `EditBookView:563`）を一度にカバーできる。`privacy: .public` はステップ2の承認済み方針（設計メモ 第7章ステップ2の挙動差分①）に合わせる。

**ステップ4送り**: 失敗時にユーザーへ何を返すか（無反応のままでよいか）の構造的判断。

---

### #8 選択状態のID保持統一 🟡

`MainTabView` の `selectedPassbook: Passbook?` → `selectedPassbookId: String?` ＋ ID解決（74-76行・517-527行）は**正しく、かつ旧実装より堅牢**（改名・色変更がストリームの新値から常に反映される＝@Model参照時代の自動反映を再現）。一方で同じ問題に対して他所は方針が揃っていない。

| 箇所 | 保持形 | 結果 |
|---|---|---|
| `MainTabView:76` | ID + 解決 | ✅ 改名が反映 |
| `AddBookView:57-64` | ID + 解決（引数DTOへフォールバック） | ✅ |
| `BookSearchView:154` | DTOスナップショット | ⚠️ 597行のピッカー表示名が改名後も古いまま |
| `BookSearchDestination`（`MainTabView:572`） | DTOスナップショット（NavigationPathに載る） | ⚠️ 同上 |

**修正方針**: `AddBookView:57-64` の「`@State` にIDを持ち、`customPassbooks` → `allPassbooks` → 引数DTO の順で解決」パターンを `BookSearchView` に適用（154 / 563 / 565 / 597 / 738 / 1006 行）。

**重要**: 引数DTOをフォールバックに残すこと。これがないと初回フレームで口座が解決できず、#3と同じ退行が `BookSearchView` に出る。

`BookSearchDestination` は等価判定が既に `id` ベースなので、保持するDTOは「初回フレーム用のシード」である旨をコメントで明示すれば整合する（IDのみに削ると初回フレームで口座が引けなくなるため、削らないこと）。

---

### #9 デッドコード画面への `@Query` 新規追加を撤回 🟡

`ContentView` / `HomeView` / `PassbookListView` は自身の `#Preview` からしか参照されていない（アプリ本体からの到達経路なし）。切替自体は無害だが、`passbook.bookCount` / `passbook.userBooks` の代替として `ContentView.swift:21` と `Views/PassbookListView.swift:16` に **`@Query private var allBooks: [UserBook]` を新規追加**している。ロードマップの「`@Query` 直依存のコードを増やさない」方針と逆行し、ステップ6の掃除対象を2件増やしている。

**修正方針**: `[BookDTO].totalDisplayAmount` は `Repositories/BookDTO.swift:50-57` に既に存在するため、両画面とも `repos.books.observeBooks()` の購読へ置き換えられる（`BookDTO.passbookId` で絞り込み）。`@Query` を増やさずに済み、ステップ6の掃除対象も減る。

**別案**: デッドコードなので削除するという選択肢もあるが、これはスコープ外の判断であり、オーナー確認が要る。

---

### #6 テストの追加と、担保範囲の正直な明記 🟠

**現状**: ワーキングツリーに**テストファイルの変更が1件もない**。設計メモのステップ3行が根拠として挙げる `testDeletingPassbookAlsoDeletesItsBooks`（`BookBankTests/RepositoryFoundationTests.swift:292`）はステップ1由来のテストで、**リポジトリ層の契約テストであり、View側の2つの呼び出し経路が実際に `deletePassbook` を通ることは検証していない**。同様に「オンボーディング初回口座作成・3口座上限・口座色解決・選択状態のuuid化」はいずれもView層の挙動で、98件のテストは通っていてもこれらは実行されていない。

**追加すべきテスト**:

| 対象 | テスト |
|---|---|
| #1 | `resolvedDefaultColorIndex` の3ケース（空配列→nil／到達後→位置index／設定済み→nil）＋ 適用後の `updatePassbook` 読み戻し |
| #2 | 生 `ModelContext` 書き込み → `notifyExternalChange()` → ストリームが新値をyield |
| #6（削除経路） | 複数口座を連続削除して残る口座と本が意図どおりであること（`PassbookListView` の「`offsets` を先にDTO配列へ確定 → 逐次削除」の形をリポジトリレベルで再現）／未知IDでの冪等性 |

**担保できないことの明記**: このプロジェクトにはView層のテストハーネス（ViewInspector等）がないため、「Viewが `deletePassbook` を呼ぶ」というView→リポジトリの結線そのものは直接検証できない。設計メモの確認欄には、テストで担保した範囲と目視・コードレビューで担保した範囲を分けて書くこと。

---

## 3. 【ステップ4送り】

### #4 `deletePassbook` が `deleteBook` のセマンティクスを通らない 🟠

設計メモ4.4節は削除の明示化を2点セットで定義している（口座→本、**本→所属リストの `bookIds` から除去**）。ところが:

- `Repositories/SwiftDataBookRepository.swift:64-71` の `deleteBook` は `ReadingList.bookIds` から当該idを除去する
- `Repositories/SwiftDataPassbookRepository.swift:53-55` の `deletePassbook` は `context.delete(book)` を直接呼ぶだけで、**この除去を行わない**

結果、口座を削除すると所属していた本のuuidが読了リストの `bookIds` にゴーストとして残る。

- **現行挙動からの回帰ではない**（cascade削除も旧 `EditPassbookView` の明示deleteも `bookIds` を掃除していなかった）。`ReadingListOrdering.resolve` はゴーストidを無視するため、ユーザーに見える影響も現時点ではない
- ただし**R4が消しにいったはずの「削除経路ごとにセマンティクスが違う」状態がリポジトリ層の内側に再生産されている**。R6でこれを `WriteBatch` に写すと、Firestoreには参照整合性がないためゴーストが実害（存在しないdocIDを含むリスト）になる
- `testDeletingPassbookAlsoDeletesItsBooks` は本と口座が消えることしか検証していないため、この非対称は誰も検出しない

**ステップ4で扱う理由**: `UserBook` の削除経路を全面的にリポジトリへ移すタイミングで、`deletePassbook` から `deleteBook` のセマンティクスを再利用する形へ揃えるのが自然かつ低コスト。

### #5（構造） lookup失敗時の扱い

上記2.#5の「失敗時にユーザーへ何を返すか」。ステップ4で本の登録・編集経路を全面移行する際に同じ判断が必要になるため、その時点で方針を決める。

---

## 4. 【設計メモ反映】

`docs/r4-repository-abstraction-notes.md` に対して、実装と独立に文書側だけで完結する更新。

### 4-1. #7 の追認（8.3節-2）

8.3節-2 は未使用 `@Environment(\.modelContext)` の削除を「**ステップ6で削除する（それまでは触らない）**」と明記しているが、`Views/StatisticsView.swift:27` と `Views/PassbookDetailView.swift:22` で今回削除されている（`AppRepositories` への置換に伴う巻き込み）。機能的には無害。**ステップ3で先行実施した旨を追認として記載**し、8.3節-2 とステップ6行から該当2ファイルを落とす。

### 4-2. #4 をステップ4課題として明記

4.4節および第7章ステップ4行に、「`deletePassbook` は所属本を明示削除するが `ReadingList.bookIds` の掃除は行っていない（ステップ3時点）。ステップ4で `deleteBook` のセマンティクスへ寄せる」ことを追記。

### 4-3. 4.3節に「マイグレーションはパルス外」の注記

案Aの表または直下の箇条書きに、以下を追記:

> チェンジパルスはリポジトリ経由の書き込みしか拾わない。前提7により**マイグレーション3種と `StoreBackupManager` は恒久的にパルス外**であり、起動時マイグレーションの書き込みは購読済みストリームに反映されない。`@Query` はmainContextのsaveを自動検知して自己修復していたが、ストリームは検知しない。起動シーケンスの末尾で `AppRepositories.notifyExternalChange()` を1回叩くことでこの穴を塞ぐ（R6でも同じ配線が必要）。

### 4-4. #10 記録事項3点

1. **`savePassbook` の書き戻し範囲拡大**: 旧 `savePassbook` は `name` / `customColorHex` / `colorIndex` の3つだけを @Model に書いていた。新実装は `updatePassbook` → `ModelDTOMapping.apply`（`Repositories/ModelDTOMapping.swift:75-84`）経由で **`type` / `sortOrder` / `isActive` / `createdAt` / `updatedAt` も含む全フィールドをスナップショット値で上書き**する。編集シートを開いたまま並び替え等が起きれば `sortOrder` が巻き戻る。8.1節が「単一端末・逐次操作なので実害なし」とした編集競合の適用範囲が Passbook では `sortOrder` にまで広がった点を8.1節に追記。なお `updatedAt` を据え置く点は前提12どおりで正しい。
2. **プレビューの後退2件**: (a) `Views/EditBookView.swift:580-601` の `#Preview("手動登録の本")` と `#Preview("API取得の本")` がどちらも「1冊目をfetch」の同一内容になり、`source` の違いを見る目的が失われている。(b) `Views/BookSelectorView.swift:366-370` はローカル `ModelContainer` と `PreviewSupport.repositories`（別コンテナ）を混在注入しており、口座リストと本のリストが別ストアを向く。5.5節「プレビューはリポジトリ束に統一」を満たしていない（ステップ6予定ではあるが、今回触った分は整合させたほうが安全）。8.3節-5 に追記。
3. **ステップ3行の記載漏れ2件**: (a) 対象列に `Utils/MarkdownExporter.swift`（`generatePassbookMarkdown` の第1引数DTO化）が入っていない。5.5節ではステップ4/5の作業として整理されている項目の先行実施。(b) `PassbookColor` から**単一引数版 `color(for: Passbook)`（sortOrder基準）が削除**されている。全参照を確認したところ残存呼び出しはゼロ（残るのは `color(for: Int)` と `color(for:in:)`）で問題ないが、API削除が記録されていない。

### 4-5. ステップ3行の確認欄の補正

現行の確認欄「口座色はDTOのみ」は #1 の見落としを含む。テストで担保した範囲／コードレビューで担保した範囲／目視スモーク送りを分けて書き直すこと（#6参照）。

---

## 5. レビューで確認して問題なしだった項目

修正不要だが、再確認のコストを避けるため記録する。

- **オンボーディング初回口座作成**: `sortOrder: 1` / `colorIndex: 10` / `createdAt == updatedAt == now` は旧 `Passbook.init` ＋ `colorIndex = 10` と等価。`BookBankApp.swift:182` で `fullScreenCover` に `.environment(repositories)` を明示注入済み（無いと `@Environment(AppRepositories.self)` が実行時トラップするため必須）。差分は `onComplete()` / `dismiss()` が `await` の1ホップ後になる点のみで、ステップ2で承認済みの「1ランループ遅延」と同種
- **マイグレーション3種・StoreBackupManager**: `RootView.onAppear`（`BookBankApp.swift:192-211`）の起動シーケンスは完全に無変更。追加は `.environment(repositories)` 1行のみ。設計メモ8.2節の「diffレビューで担保」は満たしている（ただし#2の相互作用は別途）
- **検索状態機械（R2）**: `Views/BookSearchView.swift` の差分は「型変更・`PassbookModelLookup` 経由の保存・`.task` 追加」のみ。`searchPhase` / `registeredISBNs` の構築タイミング（8.3節-6）・世代管理には触れていない
- **削除2経路の集約**: `PassbookListView.deletePassbooks:78-90` は `offsets` を `targets` として**事前にDTO配列へ確定**してからループしており、await間にストリームが `customPassbooks` を縮めてもインデックスがずれない。`EditPassbookView.deletePassbook:430-436` もView側の本の明示削除ループを撤去済み
- **3口座上限**: 判定は `Views/AccountListView.swift:203` の1箇所のみで、DTO件数ベースでも同値（設計メモ8.2節の想定どおり）。初回フレームでは count == 0 になるが、実操作で突けるタイミングではない。判定入力が「初回body評価時に確実に揃っている `@Query`」から「非同期に届く `@State`」に変わった点のみ記録に値する
- **`MainTabView` の選択状態ID化**: 正しく、かつ旧実装より堅牢（#8は他所との不統一の話であり、`MainTabView` 自体は模範）
- **モデル側の `deleteRule: .cascade`**: `Models/Passbook.swift:41-43` は無変更。R4はスキーマ非変更が制約なのでこれは正しい。ただし「明示削除に統一した」は意味論の宣言であり、実際にはcascadeがバックストップとして効いたままである旨を4.4節に一行明記しておくと、R6の担当者の読み違いを防げる

---

## 6. 副次的に確認された残課題（今回・ステップ4いずれのスコープにも入れていない）

- **`EditBookView` の口座再解決で意味論が変わっている**（`Views/EditBookView.swift:562-564`）: 旧は `customPassbooks.first { ... }`（custom && isActive に限定）、新は `PassbookModelLookup.fetch`（全Passbookからuuid一致）。総合口座または非アクティブ口座に属する本を編集保存した場合、旧は `book.passbook = nil`（口座から外れる）、新は維持される。改善方向だが挙動差。逆に lookup が nil を返すと `book.passbook = nil` が代入され本が口座から外れる（旧も同様に nil 代入しうるため回帰ではないが、失敗確率の高い経路に変わっている）
- **`MainTabView.emptyStateView` の未ロード分岐**（553-566行）: `.frame(maxWidth: .infinity, maxHeight: .infinity)` を持たない `EmptyView` を返すため、3つの呼び出し元（通帳/本棚/集計タブの `NavigationStack` 内 `Group`）で1フレームだけレイアウトが潰れ、ナビゲーションバーの高さ等が揺れる疑いがある
- **「本を登録」導線の1フレーム遅延**: `if let registrationPassbook` ガード（`Views/BookshelfView.swift:277` / `594`、`Views/PassbookDetailView.swift:318`）は総合口座モードで `customPassbooks.first` に依存するため、初回フレームはツールバーの＋ボタンが出ず、1フレーム遅れて出現する
- **ステップ7のスクショ比較手順**: `MainTabView.emptyStateView` と `HomeView` に「ベースラインに無い分岐」が新設されているため、比較手順に「起動直後1フレームは空状態を出さないのが正」と明記が要る
