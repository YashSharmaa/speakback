import Foundation

/// Turns text written for reading (markdown, code-ish replies, numbers) into
/// text written for speaking. Pure: same input, same output, no I/O.
public struct TextNormalizer: Sendable {

    public struct Options: Sendable, Equatable {
        /// Table rows read aloud before "and N more rows".
        public var maxTableRows: Int

        public init(maxTableRows: Int = 8) {
            self.maxTableRows = maxTableRows
        }
    }

    public let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    /// Normalised text, one spoken unit (paragraph, heading, list item, table row) per line.
    public func normalize(_ text: String) -> String {
        units(text).joined(separator: "\n")
    }

    /// Normalised spoken units.
    public func units(_ text: String) -> [String] {
        MarkdownBlocks.units(text, maxTableRows: options.maxTableRows)
            .map(Self.inline)
            .map(Self.tidy)
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
    }

    /// Convenience: normalise with default options.
    public static func normalize(_ text: String) -> String {
        TextNormalizer().normalize(text)
    }

    // MARK: - Pipeline

    static func inline(_ unit: String) -> String {
        var t = InlineText.stripMarkup(unit)
        t = InlineText.replaceURLs(t)
        t = InlineText.dropEmoji(t)
        t = InlineText.replaceSymbols(t)
        t = InlineText.replaceAbbreviations(t)
        t = PathWords.replacePaths(t)
        t = InlineText.replaceAcronyms(t)
        t = NumberText.apply(t)
        t = leftoverSymbols(t)
        return t
    }

    private static let plusRx = Rx(#"\s*\+\s*(?=[\w$€£₹(])"#)
    private static let equalsRx = Rx(#"\s+(?:==?=?|≠|!=)\s+"#)
    private static let atRx = Rx(#"\s@(?=\w)"#)
    private static let slashRx = Rx(#"(?<=\w)/(?=\w)"#)
    private static let junkRx = Rx(#"[*_|\\`^<>{}\[\]#~]+"#)

    static func leftoverSymbols(_ s: String) -> String {
        var t = s
        t = plusRx.replace(t, with: " plus ")
        t = equalsRx.replace(t) { m in m.whole.contains("!") || m.whole.contains("≠") ? " is not " : " equals " }
        t = atRx.replace(t, with: " at ")
        t = slashRx.replace(t, with: " slash ")
        t = t.replacingOccurrences(of: "%", with: " percent")
        t = junkRx.replace(t, with: " ")
        return t
    }

    private static let spaces = Rx(#"[ \t\x{00A0}]+"#)
    private static let spaceBeforePunct = Rx(#"\s+([.,;:!?])"#)
    private static let repeatedPunct = Rx(#"([,;:])(?:\s*[,;:])+"#)
    private static let commaThenStop = Rx(#"[,;:]\s*([.!?])"#)
    private static let stopRun = Rx(#"([.!?])(?:\s*[.])+(?!\.)"#)
    private static let emptyParens = Rx(#"\(\s*\)|"\s*"|'\s*'"#)

    /// Collapses spacing and stray punctuation, and ends the unit with a full stop.
    static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\n", with: " ")
        t = emptyParens.replace(t, with: " ")
        t = spaces.replace(t, with: " ")
        t = spaceBeforePunct.replace(t, with: "$1")
        t = repeatedPunct.replace(t, with: "$1")
        t = commaThenStop.replace(t, with: "$1")
        t = stopRun.replace(t, with: "$1")
        t = t.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;")))
        while t.hasPrefix(".") || t.hasPrefix(":") { t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return MarkdownBlocks.terminated(t)
    }
}
