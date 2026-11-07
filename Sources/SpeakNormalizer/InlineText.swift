import Foundation

/// Inline markdown, links, emoji, symbols, abbreviations and acronyms.
enum InlineText {

    // MARK: Markup

    private static let image = Rx(#"!\[([^\]]*)\]\([^)]*\)"#)
    private static let link = Rx(#"\[([^\]]+)\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)"#)
    private static let refLink = Rx(#"\[([^\]]+)\]\[[^\]]*\]"#)
    private static let autolink = Rx(#"<((?:https?|ftp)://[^>\s]+|[\w.+-]+@[\w-]+(?:\.[\w-]+)+)>"#)
    private static let htmlTag = Rx(#"</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?/?>"#)
    private static let inlineCode = Rx(#"(`+)(.+?)\1"#)
    private static let boldStar = Rx(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#)
    private static let boldUnder = Rx(#"(?<![\w])__(?=\S)(.+?)(?<=\S)__(?![\w])"#)
    private static let italicStar = Rx(#"(?<![*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\w])"#)
    private static let italicUnder = Rx(#"(?<![\w])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w])"#)
    private static let strike = Rx(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let entity = Rx(#"&(amp|lt|gt|quot|apos|nbsp|#39);"#)

    static func stripMarkup(_ s: String) -> String {
        var t = s
        t = image.replace(t) { m in
            let alt = (m[1] ?? "").trimmingCharacters(in: .whitespaces)
            return alt.isEmpty ? "" : "Image: \(alt)."
        }
        t = link.replace(t) { m in
            let text = m[1] ?? ""
            // A bare URL used as link text reads as the URL; otherwise read the text.
            return text
        }
        t = refLink.replace(t, with: "$1")
        t = autolink.replace(t, with: "$1")
        t = htmlTag.replace(t, with: " ")
        t = entity.replace(t) { m in
            switch m[1] {
            case "amp": return "&"
            case "lt": return "<"
            case "gt": return ">"
            case "quot": return "\""
            case "apos", "#39": return "'"
            default: return " "
            }
        }
        t = inlineCode.replace(t) { m in m[2]?.trimmingCharacters(in: .whitespaces) }
        for rx in [boldStar, boldUnder, strike, italicStar, italicUnder] {
            t = rx.replace(t, with: "$1")
        }
        return t
    }

    // MARK: URLs and email

    private static let url = Rx(#"\b(?:(?:https?|ftp)://|www\.)[^\s<>"'`]+"#, [.caseInsensitive])
    private static let email = Rx(#"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b"#)

    private static let bareDomainURL = Rx(
        #"(?<![\w@./-])((?:[A-Za-z0-9-]+\.)+(?:com|org|net|io|ai|dev|app|co|in|uk|sh|me|gg|xyz))/[^\s<>"'`]*"#)

    static func replaceURLs(_ s: String) -> String {
        var t = bareDomainURL.replace(s) { m in
            var raw = m.whole
            var trailing = ""
            while let last = raw.last, ".,;:!?)]}'\"".contains(last) {
                trailing = String(last) + trailing
                raw.removeLast()
            }
            guard let domain = domain(of: raw) else { return nil }
            return "a link to " + spokenDomain(domain) + trailing
        }
        t = url.replace(t) { m in
            var raw = m.whole
            var trailing = ""
            // Trailing sentence punctuation and an unbalanced ")" are not part of the URL.
            while let last = raw.last, ".,;:!?)]}'\"".contains(last) {
                if last == ")", raw.filter({ $0 == "(" }).count >= raw.filter({ $0 == ")" }).count { break }
                trailing = String(last) + trailing
                raw.removeLast()
            }
            guard let domain = domain(of: raw) else { return m.whole }
            return "a link to " + spokenDomain(domain) + trailing
        }
        t = email.replace(t) { m in
            let parts = m.whole.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let user = parts[0].replacingOccurrences(of: ".", with: " dot ")
                .replacingOccurrences(of: "_", with: " underscore ")
            return user + " at " + spokenDomain(parts[1])
        }
        return t
    }

    /// Host of a URL with any "www." removed.
    static func domain(of raw: String) -> String? {
        var s = raw
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let at = s.firstIndex(of: "@"), s.firstIndex(of: "/").map({ at < $0 }) ?? true {
            s = String(s[s.index(after: at)...])
        }
        let host = s.split(whereSeparator: { "/?#:".contains($0) }).first.map(String.init) ?? ""
        var h = host.lowercased()
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h.isEmpty ? nil : h
    }

    /// "github.com" → "github dot com".
    static func spokenDomain(_ domain: String) -> String {
        domain.split(separator: ".").map { part -> String in
            let p = String(part)
            return Lexicon.domainLabels[p] ?? p
        }.joined(separator: " dot ")
    }

    // MARK: Emoji

    /// Drops emoji, including flags, keycaps, skin tones and ZWJ sequences.
    static func dropEmoji(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s where !isEmoji(ch) { out.append(ch) }
        return out
    }

    static func isEmoji(_ ch: Character) -> Bool {
        let scalars = ch.unicodeScalars
        guard let first = scalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        if scalars.contains(where: { $0.value == 0xFE0F || $0.value == 0x20E3 || $0.value == 0x200D }) {
            return first.properties.isEmoji || first.properties.isEmojiModifier
        }
        // Text-default pictographs above the ASCII and Latin-1 ranges (✔, ☀, ⚠).
        if first.properties.isEmoji, first.value >= 0x2190, !(0x2190...0x21FF).contains(first.value) {
            return true
        }
        // Lone variation selectors, tags and skin-tone modifiers.
        return first.value == 0xFE0F || first.properties.isEmojiModifier
            || (0xE0020...0xE007F).contains(first.value)
    }

    // MARK: Symbols and abbreviations

    private static let arrow = Rx(#"\s*(?:→|⟶|->|=>|⇒)\s*"#)
    private static let backArrow = Rx(#"\s*(?:←|<-)\s*"#)
    private static let approxBeforeNumber = Rx(#"(?:~|≈|∼)\s*(?=[$€£₹¥]?\d)"#)
    private static let ampersand = Rx(#"\s*&\s*"#)
    private static let times = Rx(#"(?<=\d)\s*×\s*(?=\d)"#)
    private static let withSlash = Rx(#"\bw/o\b"#, [.caseInsensitive])
    private static let withShort = Rx(#"\bw/(?=\s)"#, [.caseInsensitive])
    private static let andOr = Rx(#"\band/or\b"#, [.caseInsensitive])

    static func replaceSymbols(_ s: String) -> String {
        var t = s
        t = arrow.replace(t, with: " to ")
        t = backArrow.replace(t, with: " from ")
        t = approxBeforeNumber.replace(t, with: "about ")
        t = times.replace(t, with: " times ")
        t = withSlash.replace(t, with: "without")
        t = withShort.replace(t, with: "with")
        t = andOr.replace(t, with: "and or")
        t = ampersand.replace(t, with: " and ")
        t = t.replacingOccurrences(of: "−", with: "-")
        t = t.replacingOccurrences(of: "…", with: "...")
        t = t.replacingOccurrences(of: "—", with: ", ")
        t = t.replacingOccurrences(of: " – ", with: ", ")
        t = t.replacingOccurrences(of: "’", with: "'")
        t = t.replacingOccurrences(of: "‘", with: "'")
        t = t.replacingOccurrences(of: "“", with: "\"")
        t = t.replacingOccurrences(of: "”", with: "\"")
        return t
    }

    private static let abbreviations: [(Rx, String)] = [
        (Rx(#"\be\.g\.(?=[\s,]|$),?"#, [.caseInsensitive]), "for example,"),
        (Rx(#"\bi\.e\.(?=[\s,]|$),?"#, [.caseInsensitive]), "that is,"),
        (Rx(#"\betc\.(?=\s+[a-z])"#), "et cetera"),
        (Rx(#"\betc\b\.?"#), "et cetera."),
        (Rx(#"\bvs\.?(?=\s)"#, [.caseInsensitive]), "versus"),
        (Rx(#"\bapprox\.(?=\s)"#, [.caseInsensitive]), "approximately"),
        (Rx(#"\bcf\.(?=\s)"#), "compare"),
        (Rx(#"\bmisc\.(?=\s)"#), "miscellaneous"),
    ]

    static func replaceAbbreviations(_ s: String) -> String {
        var t = s
        for (rx, word) in abbreviations { t = rx.replace(t, with: word) }
        return t
    }

    // MARK: Acronyms and respellings

    private static let pluralAcronym = Rx(#"\b([A-Z]{2,5})s\b"#)

    static func replaceAcronyms(_ s: String) -> String {
        var t = s
        for (rx, spoken) in Lexicon.respellingRules { t = rx.replace(t, with: spoken) }
        // "PRs" → "PR's": an apostrophe keeps the letters spelled and adds the plural sound.
        t = pluralAcronym.replace(t) { m in
            guard let base = m[1] else { return nil }
            return Lexicon.pluralAcronym(base)
        }
        return splitIdentifiers(t)
    }

    /// snake_case words and camelCase identifiers.
    private static let snakeCase = Rx(#"(?<![\w.])[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+(?!\w|\.\w)"#)
    /// A lower-case start of two or more letters, then capitals: "fetchUserData", not "iPhone" or "eBay".
    private static let camelCase = Rx(#"(?<![\w.])[a-z]{2,}[a-z0-9]*(?:[A-Z][a-z0-9]*)+(?!\w|\.\w)"#)
    private static let camelBoundary = Rx(#"(?<=[a-z0-9])(?=[A-Z])"#)

    /// Splits code identifiers so the parts read as words: "fetch_user_data" and
    /// "fetchUserData" both read "fetch user data" ("fetch User Data").
    static func splitIdentifiers(_ s: String) -> String {
        var t = snakeCase.replace(s) { $0.whole.replacingOccurrences(of: "_", with: " ") }
        t = camelCase.replace(t) { camelBoundary.replace($0.whole, with: " ") }
        return t
    }
}
