#!/usr/bin/env python3
"""既存メモとT1装飾記法の衝突チェック（R4.5 ステップ9'）。

N0スパイクのエクスポートJSON（実本棚データ）を入力に、既存メモの中に
`[[ ]]`・ペアの `**`・行頭の `> `・`p.数字` が偶然含まれていて、T1リリース後に
意図しない装飾として表示されてしまう箇所がないかを機械的に洗い出す
（docs/memo-tagging-design.md 7章の確認項目）。

判定規則はアプリ本体の純関数と同じものを再現している:
- つながり:   MemoLinkParser（半角/全角 [[ ]] 混在可・同一行内で閉じる・
              NFKC＋トリム後1〜30文字。空や31文字超は不成立＝記号がそのまま見える）
- 太字:       MemoLinkText.pairedBoldMarkers（同一行内で ** が偶数個ペア成立。
              つながりの範囲内は数えない。余った ** はただの文字）
- 引用:       MemoTextBlocks.parse（行頭が半角の「> 」の行だけ。>単独や >text は対象外）
- ページ番号: MemoPageMarker.ranges（p または P ＋ . ＋ 半角数字1つ以上。
              直前が英数字なら不成立。つながりのラベル内は対象外）

使い方:
    python3 tools/memo-markup-check.py <エクスポートJSONのパス>

入力JSONはデバッグメニューの「N0スパイク用JSONエクスポート」で書き出したもの
（books[].memo と monthlyMemos[].text を見る）。**メモは私有データなので、
JSONも本スクリプトの出力もリポジトリにコミットしないこと**（n0-spike-plan 3.2節）。
置き場所は gitignore 済みの tools/n0-spike/data/ を推奨。

注意: ラベル長の判定は Python の len()（コードポイント数）で、Swift の
Character（書記素クラスタ）とは絵文字等でずれることがある。境界ぎりぎりの
ラベルが出たら実機でも確認すること。
"""

import json
import sys
import unicodedata

OPEN_BRACKETS = {"[", "［"}
CLOSE_BRACKETS = {"]", "］"}
MAX_KEY_LENGTH = 30


def find_closed_pairs(text):
    """MemoLinkParser.closedPairs と同じ走査。

    [(全体の開始, 全体の終了, 中身の開始, 中身の終了)] を返す（終了は排他的）。
    """
    pairs = []
    i = 0
    n = len(text)
    while i < n - 1:
        if text[i] in OPEN_BRACKETS and text[i + 1] in OPEN_BRACKETS:
            # 同じ行の中で閉じ括弧のペアを探す（改行に当たったら不成立）
            j = i + 2
            closer = None
            while j < n:
                if text[j] in "\n\r":
                    break
                if j + 1 < n and text[j] in CLOSE_BRACKETS and text[j + 1] in CLOSE_BRACKETS:
                    closer = j
                    break
                j += 1
            if closer is None:
                i += 1  # この [[ は不成立。1文字進めて探し直す
                continue
            pairs.append((i, closer + 2, i + 2, closer))
            i = closer + 2
        else:
            i += 1
    return pairs


def normalize_key(raw_label):
    """MemoLinkParser.normalize と同じ（トリム → NFKC → 小文字化）"""
    return unicodedata.normalize("NFKC", raw_label.strip()).lower()


def find_links(text):
    """成立するつながりと、不成立（空・31文字超）の閉じた括弧を分けて返す"""
    valid, invalid = [], []
    for start, end, body_start, body_end in find_closed_pairs(text):
        key = normalize_key(text[body_start:body_end])
        if 0 < len(key) <= MAX_KEY_LENGTH:
            valid.append((start, end, text[body_start:body_end].strip()))
        else:
            invalid.append((start, end, key))
    return valid, invalid


def find_paired_bold(text, link_ranges):
    """MemoLinkText.pairedBoldMarkers と同じ。ペア成立した ** の開始位置のリスト"""
    paired = []
    pending = None
    link_starts = {start: end for start, end, _ in link_ranges}
    i = 0
    n = len(text)
    while i < n:
        if i in link_starts:
            i = link_starts[i]
            continue
        if text[i] in "\n\r":
            pending = None
            i += 1
            continue
        if text[i] == "*" and i + 1 < n and text[i + 1] == "*":
            if pending is not None:
                paired.extend([pending, i])
                pending = None
            else:
                pending = i
            i += 2
            continue
        i += 1
    return sorted(paired)


def find_quote_lines(text):
    """行頭が「> 」（半角・空白必須）の行番号（0始まり）"""
    return [i for i, line in enumerate(text.split("\n")) if line.startswith("> ")]


def find_page_markers(text, link_ranges):
    """MemoPageMarker.ranges と同じ。つながりのラベル内は除く"""
    markers = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch in ("p", "P"):
            prev = text[i - 1] if i > 0 else None
            prev_is_alnum = prev is not None and prev.isascii() and prev.isalnum()
            if not prev_is_alnum and i + 1 < n and text[i + 1] == ".":
                j = i + 2
                while j < n and text[j].isascii() and text[j].isdigit():
                    j += 1
                if j > i + 2:
                    if not any(start <= i < end for start, end, _ in link_ranges):
                        markers.append((i, j, text[i:j]))
                    i = j
                    continue
        i += 1
    return markers


def snippet(text, pos, width=30):
    """pos の前後を1行に潰した抜粋"""
    start = max(0, pos - width)
    end = min(len(text), pos + width)
    prefix = "…" if start > 0 else ""
    suffix = "…" if end < len(text) else ""
    return prefix + text[start:end].replace("\n", "⏎") + suffix


def check_memo(source, text, report):
    valid_links, invalid_links = find_links(text)
    bold = find_paired_bold(text, valid_links)
    quotes = find_quote_lines(text)
    pages = find_page_markers(text, valid_links)

    for start, _end, label in valid_links:
        report["links"].append((source, f"[[{label}]] → つながりとして認識される", snippet(text, start)))
    for start, _end, _key in invalid_links:
        report["invalid_links"].append((source, "閉じた [[ ]] だが不成立（空 or 31文字超）→ 記号がそのまま見える", snippet(text, start)))
    lines = text.split("\n")
    for a, b in zip(bold[0::2], bold[1::2]):
        report["bold"].append((source, f"** ペア成立 → 「{text[a + 2:b]}」が太字になる", snippet(text, a)))
    for line_no in quotes:
        report["quotes"].append((source, "行頭「> 」→ 引用の囲みになる", lines[line_no][:60]))
    for start, _end, marker in pages:
        report["pages"].append((source, f"{marker} → ページ番号バッジになる", snippet(text, start)))


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)

    with open(sys.argv[1], encoding="utf-8") as f:
        shelf = json.load(f)

    report = {"links": [], "invalid_links": [], "bold": [], "quotes": [], "pages": []}
    memo_count = 0

    for book in shelf.get("books", []):
        memo = book.get("memo")
        if memo:
            memo_count += 1
            check_memo(f"書籍「{book.get('title', '?')}」", memo, report)
    for monthly in shelf.get("monthlyMemos", []):
        text = monthly.get("text")
        if text:
            memo_count += 1
            check_memo(f"月別メモ {monthly.get('year')}-{monthly.get('month'):02d}", text, report)

    sections = [
        ("links", "つながりとして認識される [[ ]]"),
        ("invalid_links", "不成立の閉じた [[ ]]（記号がそのまま見える）"),
        ("bold", "太字として表示される ** のペア"),
        ("quotes", "引用の囲みになる行頭の「> 」"),
        ("pages", "ページ番号バッジになる p.数字"),
    ]

    print(f"検査対象: 書籍 {len(shelf.get('books', []))} 冊・メモあり {memo_count} 件")
    print("（この出力はメモ本文の抜粋を含む。コミット・共有しないこと）")
    print()
    total = 0
    for key, title in sections:
        findings = report[key]
        total += len(findings)
        print(f"■ {title}: {len(findings)} 件")
        for source, what, context in findings:
            print(f"  - {source}: {what}")
            print(f"      | {context}")
    print()
    if total == 0:
        print("→ 衝突なし。既存メモに意図しない装飾は発生しない。")
    else:
        print(f"→ 計 {total} 件。上記が「本人が意図した表示になるか」を目視で判定すること。")


if __name__ == "__main__":
    main()
