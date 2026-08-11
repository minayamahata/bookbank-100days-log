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
//  `p.数字`（角丸バッジ）。見出し・箇条書き・斜体・リンク等の他のMarkdown記法は解釈しない。
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

/// ページ番号の run の背後に角丸4の薄いテーマ色を敷く。
/// `AttributedString` の背景色属性は角丸を持てないため、描画側で塗る
private struct MemoPageBadgeRenderer: TextRenderer {
    let badgeColor: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[MemoPageBadgeAttribute.self] != nil {
                    let rect = run.typographicBounds.rect.insetBy(dx: -4, dy: -1.5)
                    context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(badgeColor))
                }
                context.draw(run)
            }
        }
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
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MemoTextBlocks.parse(memo).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let content):
                    inline(content)
                case .quote(let content):
                    inline(content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func inline(_ content: String) -> some View {
        MemoLinkText.text(content, accentColor: accentColor)
            .textRenderer(MemoPageBadgeRenderer(badgeColor: accentColor.opacity(0.14)))
    }
}

// MARK: - インライン装飾

enum MemoLinkText {
    /// 1ブロックぶんの本文を装飾付きの `AttributedString` にする。
    ///
    /// - `[[中身]]`: 記号を隠し、中身だけ `color`＋セミボールドで着色
    /// - `**中身**`: 記号を隠して太字。ペアが同じ行で閉じている場合のみ（`*` 1つの斜体は解釈しない）
    /// - `p.数字`: 文字はそのまま、`color`＋少し小さめのフォント＋ページ番号属性（バッジの目印）
    ///
    /// 記号を隠すため表示文字列は原文と一致しない。不変条件は「**解釈対象の記号以外の
    /// 文字は一切加工しない**」（設計メモ 4.6節・テストで固定)。編集画面は記号を出したまま。
    /// 行頭 `> ` の引用はここでは扱わない（`MemoTextBlocks` が囲みに変換する）
    static func highlighted(_ memo: String, color: Color) -> AttributedString {
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
            if isBold { part.inlinePresentationIntent = .stronglyEmphasized }
            result += part
            buffer = ""
        }

        while index < memo.endIndex {
            if let link = linksByStart[index] {
                flush()
                var highlighted = AttributedString(link.display)
                highlighted.foregroundColor = color
                highlighted.font = .subheadline.weight(.semibold)
                result += highlighted
                index = link.range.upperBound
                continue
            }

            if let page = pagesByStart[index] {
                flush()
                var badge = AttributedString(String(memo[page]))
                badge.foregroundColor = color
                badge.font = .footnote.weight(.medium)
                badge.memoPageNumber = true
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
    static func text(_ memo: String, accentColor: Color) -> Text {
        let attributed = highlighted(memo, color: accentColor)
        var result = Text(verbatim: "")
        for (isPage, range) in attributed.runs[\.memoPageNumber] {
            let piece = Text(AttributedString(attributed[range]))
            result = result + (isPage == true ? piece.customAttribute(MemoPageBadgeAttribute()) : piece)
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
}
