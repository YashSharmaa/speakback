import Foundation

/// Turns markdown into spoken units: one string per paragraph, heading, list
/// item or table row. Inline markup is left for `InlineText`.
enum MarkdownBlocks {

    static let codeBlockPhrase = "Code block omitted."

    private static let fence = Rx(#"^\s{0,3}(`{3,}|~{3,})"#)
    private static let heading = Rx(#"^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$"#)
    private static let setextUnderline = Rx(#"^\s{0,3}(=+|-+)\s*$"#)
    private static let rule = Rx(#"^\s{0,3}([-*_])(\s*\1){2,}\s*$"#)
    private static let listItem = Rx(#"^\s*(?:[-*+•▪◦‣]|\d{1,3}[.)])\s+(?:\[[ xX]\]\s+)?(.*)$"#)
    private static let quote = Rx(#"^\s{0,3}(?:>\s?)+"#)
    private static let tableSeparator = Rx(#"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$"#)
    private static let htmlComment = Rx(#"<!--[\s\S]*?-->"#)

    static func units(_ text: String, maxTableRows: Int) -> [String] {
        let cleaned = htmlComment.replace(
            text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"),
            with: " ")
        let lines = cleaned.components(separatedBy: "\n")
        var units: [String] = []
        var paragraph: [String] = []

        func flush() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { units.append(joined) }
            paragraph.removeAll()
        }

        var i = 0
        while i < lines.count {
            var line = lines[i]

            // Fenced code: skip to the closing fence, whatever the language.
            if let open = fence.firstMatch(line), let marker = open[1] {
                flush()
                var j = i + 1
                while j < lines.count {
                    let t = lines[j].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(String(repeating: String(marker.first!), count: marker.count)),
                        t.allSatisfy({ $0 == marker.first! })
                    {
                        break
                    }
                    j += 1
                }
                units.append(codeBlockPhrase)
                i = j + 1
                continue
            }

            // Tables: a row of cells followed by a separator row.
            if line.contains("|"), i + 1 < lines.count, tableSeparator.matches(lines[i + 1]) {
                flush()
                let header = cells(line)
                var rows: [[String]] = []
                var j = i + 2
                while j < lines.count, lines[j].contains("|"),
                    !lines[j].trimmingCharacters(in: .whitespaces).isEmpty
                {
                    let row = cells(lines[j])
                    if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
                    j += 1
                }
                units.append(contentsOf: tableUnits(header: header, rows: rows, maxRows: maxTableRows))
                i = j
                continue
            }

            // Strip blockquote markers, then classify.
            line = quote.replace(line, with: "")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flush()
                i += 1
                continue
            }
            if rule.matches(trimmed) {
                flush()
                i += 1
                continue
            }
            if let h = heading.firstMatch(line) {
                flush()
                units.append(terminated(h[1] ?? ""))
                i += 1
                continue
            }
            // Setext heading: the paragraph so far is the heading text.
            if setextUnderline.matches(trimmed), !paragraph.isEmpty {
                let text = paragraph.joined(separator: " ")
                paragraph.removeAll()
                units.append(terminated(text))
                i += 1
                continue
            }
            if let item = listItem.firstMatch(line) {
                flush()
                units.append(terminated(item[1] ?? ""))
                i += 1
                continue
            }
            paragraph.append(trimmed)
            i += 1
        }
        flush()
        return units
    }

    /// Cells of a pipe table row, trimmed, with outer pipes removed.
    static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Tables are read briefly: the size, the column names, then each row's cells.
    static func tableUnits(header: [String], rows: [[String]], maxRows: Int) -> [String] {
        var out: [String] = []
        let rowWord = rows.count == 1 ? "row" : "rows"
        let columns = header.filter { !$0.isEmpty }
        if columns.isEmpty {
            out.append("Table with \(rows.count) \(rowWord).")
        } else {
            out.append("Table with \(rows.count) \(rowWord). Columns: \(columns.joined(separator: ", ")).")
        }
        for row in rows.prefix(maxRows) {
            let values = row.filter { !$0.isEmpty }
            if !values.isEmpty { out.append(terminated(values.joined(separator: ", "))) }
        }
        if rows.count > maxRows {
            let rest = rows.count - maxRows
            out.append("And \(rest) more \(rest == 1 ? "row" : "rows").")
        }
        return out
    }

    /// Ends a unit with a full stop if it has no closing punctuation, so the
    /// speaker pauses between headings, list items and rows.
    static func terminated(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let last = t.last else { return t }
        if ".!?:;…".contains(last) { return t }
        return t + "."
    }
}
