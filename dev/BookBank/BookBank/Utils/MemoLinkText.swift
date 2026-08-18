//
//  MemoLinkText.swift
//  BookBank
//
//  メモ本文の表示（docs/memo-tagging-design.md 4.6節）。
//  検出は純関数（`MemoLinkParser` / `MemoTextBlocks` / `MemoPageMarker`）が担い、
//  ここは装飾を当てる表示側の薄い層に留める。
//
//  解釈するのは**ツールバーが出せるものだけ**（同 0.4節）:
//  `[[ ]]`（記号を隠して着色）・`**` のペア（太字）・行頭の `> `（薄いグレーの囲み）・
//  `p.数字`（グレーの角丸バッジ）。見出し・箇条書き・斜体・リンク等の他のMarkdown記法は解釈しない。
//

import SwiftUI

// MARK: - ページ番号を run 単位で塗るためのカスタム属性

/// `AttributedString` 側の印。テスト対象（`highlighted` の結果から読める）
enum MemoPageNumberAttribute: CodableAttributedStringKey {
    typealias Value = Bool
    static let name = "BookBankMemoPageNumber"
}

extension AttributeScopes {
    struct BookBankMemoAttributes: AttributeScope {
        let memoPageNumber: MemoPageNumberAttribute
    }
    var bookBankMemo: BookBankMemoAttributes.Type { BookBankMemoAttributes.self }
}

extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.BookBankMemoAttributes, T>
    ) -> T { self[T.self] }
}

/// `Text` 側の印。`TextRenderer` が背景の角丸を描くときの目印
private struct MemoPageBadgeAttribute: TextAttribute {}

/// ページ番号の run の背後にグレーの角丸バッジを敷く（文字色はテーマ色のまま）。
/// `AttributedString` の背景色属性は角丸も余白も持てないため、描画側で塗る。
/// 寸法は編集画面（`MemoQuoteBackgroundLayoutManager`）と共有する
private struct MemoPageBadgeRenderer: TextRenderer {
    let badgeColor: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            // バッジは字送りを広げた文字（末尾）で run が割れるので、続きは1枚にまとめる
            var box: CGRect?
            for run in line {
                guard run[MemoPageBadgeAttribute.self] != nil else {
                    fill(box, in: &context)
                    box = nil
                    continue
                }
                let bounds = run.typographicBounds.rect
                box = box.map { $0.union(bounds) } ?? bounds
            }
            fill(box, in: &context)
            for run in line { context.draw(run) }
        }
    }

    private func fill(_ box: CGRect?, in context: inout GraphicsContext) {
        guard var box else { return }
        let inset = MemoQuoteBackgroundLayoutManager.pageBadgeInset
        // 字送りには末尾に足した空きが入っているので、その分を戻してから余白を付ける
        box.size.width -= MemoQuoteBackgroundLayoutManager.pageBadgeSpacing
        context.fill(
            Path(
                roundedRect: box.insetBy(dx: -inset.width, dy: -inset.height),
                cornerRadius: MemoQuoteBackgroundLayoutManager.pageBadgeCornerRadius
            ),
            with: .color(badgeColor)
        )
    }
}

// MARK: - 表示ビュー

/// 書籍詳細のメモ欄。引用ブロックだけ薄いグレーで囲む——`> ` の記号は一般ユーザーに
/// 引用と伝わらないため、記号ではなくUIで表現する（2026-08-11 オーナー確定）
struct MemoFormattedText: View {
    let memo: String
    /// つながりの着色とページ番号バッジに使う色（黒テーマ＋ダーク時の退避は呼び出し側の責務）
    let accentColor: Color

    var body: some View {
        let blocks = MemoTextBlocks.parse(memo)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .paragraph(let content):
                    // Enterで分けた行は1行ずつ積んで空きを入れる——折り返しの行と同じ行送りだと
                    // 段落の区切りが読めない（2026-08-12 オーナー指示。編集画面と同じ空き）
                    VStack(alignment: .leading, spacing: MemoEditorTextView.paragraphSpacing) {
                        ForEach(
                            Array(content.components(separatedBy: "\n").enumerated()), id: \.offset
                        ) { _, line in
                            inline(line)
                                // 折り返したぶんの高さを必ず確保する（下記 `quote` と同じ理由）
                                .fixedSize(horizontal: false, vertical: true)
                                // 空行にも1行ぶんの高さを持たせる（空きの値は行送りと同じ）
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: MemoEditorTextView.paragraphSpacing,
                                    alignment: .leading
                                )
                                // 行頭のバッジは内側の余白ぶん字下げする（編集画面と同じ）——
                                // 字送りでは前の行が伸びてしまうため、行ごと寄せて場所を作る
                                .padding(.leading, Self.badgeIndent(of: line))
                        }
                    }
                case .quote(let content):
                    // 引用の文字は本文より少し小さく・少し薄い黒、囲みの内側余白は編集画面と同じ。
                    // 太字も囲みの中の大きさに合わせる（編集画面はその行のフォントから拾っている）
                    inline(content, boldFont: .app(.subheadline, weight: .bold))
                        .font(.app(.subheadline))
                        .foregroundStyle(Color(MemoEditorTextView.quoteTextColor))
                        // 折り返したぶんの高さを必ず確保する。書籍詳細のパネルは高さを固定した
                        // 入れ物の中にあり、上位から詰めた高さを提案されると引用が「…」で
                        // 省略される（2026-08-13 オーナー報告）
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, MemoQuoteBackgroundLayoutManager.padding)
                        .padding(.top, MemoQuoteBackgroundLayoutManager.padding)
                        .padding(.bottom, MemoQuoteBackgroundLayoutManager.paddingBottom)
                        .background(Color(.quaternarySystemFill))
                        .overlay(alignment: .topLeading) {
                            quoteLeadLine
                        }
                        // 出典ページが続くなら詰めたまま（同じかたまりに見せる）。
                        // 続かないなら、囲みの下が引用のまとまりの下になる
                        .padding(.bottom, Self.gapBelow(index, in: blocks))
                case .quotePage(let digits):
                    // 出典ページは囲みの枠外・右下。装飾は付けず小さくするだけ（オーナー指示）。
                    // 未入力の行は保存時に消えるのでここには来ない
                    if !digits.isEmpty {
                        Text(verbatim: "p.\(digits)")
                            .font(.app(.footnote))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.bottom, Self.gapBelow(index, in: blocks))
                    }
                }
            }
        }
    }

    /// 確定メモだけの引用印。先頭行の高さに合わせ、枠の左へ少しはみ出す
    /// （**2026-08-18 オーナー指示**。編集画面には出さない）
    private static let quoteLeadLineWidth: CGFloat = 20
    private static let quoteLeadLineThickness: CGFloat = 1
    private static let quoteLeadLineOverflow: CGFloat = 8

    private var quoteLeadLine: some View {
        let lineHeight = AppTypography.uiFont(.subheadline).lineHeight
        return Rectangle()
            .fill(Color.primary)
            .frame(width: Self.quoteLeadLineWidth, height: Self.quoteLeadLineThickness)
            .offset(
                x: -Self.quoteLeadLineOverflow,
                y: MemoQuoteBackgroundLayoutManager.padding
                    + lineHeight / 2
                    - Self.quoteLeadLineThickness / 2
            )
            .allowsHitTesting(false)
    }

    /// 引用のまとまりの下だけ広く空ける（編集画面と同じ30。ブロック間の6ぶんを差し引く）。
    /// まとまりの終わりは出典ページ、無ければ囲み。メモの末尾なら空けない（下は余白しかない）
    private static func gapBelow(_ index: Int, in blocks: [MemoTextBlock]) -> CGFloat {
        let next = index + 1 < blocks.count ? blocks[index + 1] : nil
        guard let next else { return 0 }
        if case .quotePage(let digits) = next, !digits.isEmpty { return 0 }
        return MemoQuoteBackgroundLayoutManager.gapBelowQuote - 6
    }

    /// 行頭がページ番号なら、バッジの内側の余白ぶんの字下げ。それ以外は0
    private static func badgeIndent(of line: String) -> CGFloat {
        guard MemoPageMarker.ranges(in: line).first?.lowerBound == line.startIndex,
              !line.isEmpty
        else { return 0 }
        return MemoQuoteBackgroundLayoutManager.pageBadgeInset.width
    }

    private func inline(
        _ content: String,
        boldFont: Font = .app(.body, weight: .bold)
    ) -> some View {
        MemoLinkText.text(content, accentColor: accentColor, boldFont: boldFont)
            .lineSpacing(MemoEditorTextView.bodyLineSpacing)
            .textRenderer(
                MemoPageBadgeRenderer(
                    badgeColor: Color(MemoQuoteBackgroundLayoutManager.pageBadgeColorDefault)
                )
            )
    }
}

// MARK: - インライン装飾

enum MemoLinkText {
    /// 太字の太さ。編集画面（`MemoEditorTextView.boldWeight`）と同じ段。
    /// LINE Seed に存在する Bold 面を使う（従来の heavy 合成はやめる）
    static let boldWeight: Font.Weight = .bold

    /// 1ブロックぶんの本文を装飾付きの `AttributedString` にする。
    ///
    /// - `[[中身]]`: 記号を隠し、中身だけ `color` で着色して下線を引く
    /// - `**中身**`: 記号を隠して太字。ペアが同じ行で閉じている場合のみ（`*` 1つの斜体は解釈しない）
    /// - `p.数字`: 文字はそのまま、`color`＋少し小さめのフォント＋ページ番号属性（バッジの目印）
    ///
    /// 記号を隠すため表示文字列は原文と一致しない。不変条件は「**解釈対象の記号以外の
    /// 文字は一切加工しない**」（設計メモ 4.6節・テストで固定)。編集画面も同じ規則で隠す。
    /// 行頭 `> ` の引用はここでは扱わない（`MemoTextBlocks` が囲みに変換する）
    /// - Parameter boldFont: 太字に当てるフォント。行の大きさに合った Bold を
    ///   呼び出し側から渡す（引用の中は本文より小さい）
    static func highlighted(
        _ memo: String,
        color: Color,
        boldFont: Font = .app(.body, weight: .bold)
    ) -> AttributedString {
        let links = MemoLinkParser.parse(memo)
        let linksByStart = Dictionary(uniqueKeysWithValues: links.map { ($0.range.lowerBound, $0) })
        let boldMarkers = pairedBoldMarkers(in: memo, excluding: links.map(\.range))
        // p.数字 がつながりのラベル内にある場合は、リンクの範囲ごと消費されるので届かない
        let pagesByStart = Dictionary(
            uniqueKeysWithValues: MemoPageMarker.ranges(in: memo).map { ($0.lowerBound, $0) }
        )

        var result = AttributedString()
        var buffer = ""
        var isBold = false
        var index = memo.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            var part = AttributedString(buffer)
            if isBold { part.font = boldFont }
            result += part
            buffer = ""
        }

        while index < memo.endIndex {
            if let link = linksByStart[index] {
                flush()
                var highlighted = AttributedString(link.display)
                highlighted.foregroundColor = color
                // つながりの印は太字ではなく下線（2026-08-13 オーナー指示）——白テーマ×ダーク／
                // 黒テーマ×ライトではテーマ色が本文と同色になり、セミボールドでは太字と区別が
                // つかないため。フォントは指定せず周囲に合わせる。太字と重なっても
                // つながりの見た目を優先する規則は変わらない（設計メモ 4.6節・boldFont を当てない）
                highlighted.underlineStyle = .single
                result += highlighted
                index = link.range.upperBound
                continue
            }

            if let page = pagesByStart[index] {
                flush()
                let spacing = MemoQuoteBackgroundLayoutManager.pageBadgeSpacing
                // バッジの前後に場所を作る（文字は足さず、直前の文字とバッジ末尾の字送りを広げる）
                if let previous = result.characters.indices.last {
                    result[previous...].kern = spacing
                }
                var badge = AttributedString(String(memo[page]))
                badge.foregroundColor = color
                badge.font = .app(.footnote)
                badge.memoPageNumber = true
                if let last = badge.characters.indices.last {
                    badge[last...].kern = spacing
                }
                result += badge
                index = page.upperBound
                continue
            }

            if boldMarkers.contains(index) {
                flush()
                isBold.toggle()
                index = memo.index(index, offsetBy: 2)
                continue
            }

            let character = memo[index]
            buffer.append(character)
            if character.isNewline {
                flush()
                isBold = false
            }
            index = memo.index(after: index)
        }

        flush()
        return result
    }

    /// `highlighted` の結果を `Text` に変換する。ページ番号の run にだけ描画用の印
    /// （`MemoPageBadgeAttribute`）を付ける——カスタム `TextAttribute` は `Text` の連結でしか
    /// 埋め込めないため、この変換層が要る
    static func text(
        _ memo: String,
        accentColor: Color,
        boldFont: Font = .app(.body, weight: .bold)
    ) -> Text {
        let attributed = highlighted(memo, color: accentColor, boldFont: boldFont)
        var result = Text(verbatim: "")
        for (isPage, range) in attributed.runs[\.memoPageNumber] {
            let piece = Text(AttributedString(attributed[range]))
            let marked = isPage == true ? piece.customAttribute(MemoPageBadgeAttribute()) : piece
            // `Text` 同士の `+` はiOS 26で非推奨。連結は補間で行う。
            // ここは訳語ではなく連結だけが目的なので、翻訳カタログに拾わせない形で組み立てる
            var interpolation = LocalizedStringKey.StringInterpolation(
                literalCapacity: 0, interpolationCount: 2
            )
            interpolation.appendInterpolation(result)
            interpolation.appendInterpolation(marked)
            result = Text(LocalizedStringKey(stringInterpolation: interpolation))
        }
        return result
    }

    /// 同じ行の中でペアが閉じている `**` の開始位置の集合（昇順に並べると開き・閉じが交互になる）。
    /// 奇数個目が余った場合や行をまたぐ場合、その `**` はただの文字として表示される。
    /// `[[ ]]` の中の `**` は数えない（中身は任意の文字列であり装飾記号ではない）。
    /// 編集画面のライブ装飾（`MemoEditorTextView`）も同じ規則を使う
    static func pairedBoldMarkers(
        in text: String,
        excluding excludedRanges: [Range<String.Index>]
    ) -> Set<String.Index> {
        var paired = Set<String.Index>()
        var pending: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            if let excluded = excludedRanges.first(where: { $0.lowerBound == index }) {
                index = excluded.upperBound
                continue
            }
            if text[index].isNewline {
                pending = nil
                index = text.index(after: index)
                continue
            }
            let next = text.index(after: index)
            if text[index] == "*", next < text.endIndex, text[next] == "*" {
                if let opening = pending {
                    paired.insert(opening)
                    paired.insert(index)
                    pending = nil
                } else {
                    pending = index
                }
                index = text.index(after: next)
                continue
            }
            index = next
        }

        return paired
    }

    /// ペアが成立している `**` のまとまり。`range` は記号を含む全体、`body` は中身。
    /// 記号を隠したあとの編集（トグル・アクティブ表示・選択範囲の手当て）はここを見る
    static func boldPairs(
        in text: String
    ) -> [(range: Range<String.Index>, body: Range<String.Index>)] {
        let links = MemoLinkParser.parse(text).map(\.range)
        let markers = pairedBoldMarkers(in: text, excluding: links).sorted()
        return stride(from: 0, to: markers.count - 1, by: 2).map { pair in
            let opening = markers[pair]
            let closing = markers[pair + 1]
            return (
                range: opening..<text.index(closing, offsetBy: 2),
                body: text.index(opening, offsetBy: 2)..<closing
            )
        }
    }

    /// `caret` に効いている `**` のまとまり（中身の両端も中と見なす＝そこで打てば太字になる）
    static func enclosingBoldPair(
        in text: String,
        at caret: String.Index
    ) -> (range: Range<String.Index>, body: Range<String.Index>)? {
        boldPairs(in: text).first { $0.body.lowerBound <= caret && caret <= $0.body.upperBound }
    }
}
