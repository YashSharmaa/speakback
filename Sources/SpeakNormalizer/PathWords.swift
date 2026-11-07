import Foundation

/// Reads file names and paths: "package.json" → "package dot json",
/// "~/src/app/main.swift" → "home slash src slash app slash main dot swift".
enum PathWords {

    private static let leadingPunctuation = CharacterSet(charactersIn: "([{\"'«")
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?)]}\"'»")

    static func replacePaths(_ s: String) -> String {
        // Work token by token on whitespace so sentence punctuation stays put.
        var out = ""
        var token = ""
        func emit() {
            out += convert(token)
            token = ""
        }
        for ch in s {
            if ch.isWhitespace {
                emit()
                out.append(ch)
            } else {
                token.append(ch)
            }
        }
        emit()
        return out
    }

    static func convert(_ token: String) -> String {
        guard !token.isEmpty else { return token }
        var core = Substring(token)
        var lead = ""
        var trail = ""
        while let f = core.unicodeScalars.first, leadingPunctuation.contains(f) {
            lead.append(Character(f))
            core = core.dropFirst()
        }
        while let l = core.unicodeScalars.last, trailingPunctuation.contains(l) {
            trail = String(Character(l)) + trail
            core = core.dropLast()
        }
        let word = String(core)
        guard let spoken = spokenPath(word) else { return token }
        return lead + spoken + trail
    }

    /// The spoken form if `word` looks like a path or file name, else nil.
    static func spokenPath(_ word: String) -> String? {
        guard word.count >= 2, word.contains(where: \.isLetter) else { return nil }
        guard !word.contains("://"), !word.contains("@") else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "~./_-+"))
        guard word.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        let hasSlash = word.contains("/")
        if hasSlash {
            let segments = word.split(separator: "/", omittingEmptySubsequences: false)
            let rooted = word.hasPrefix("/") || word.hasPrefix("~/") || word.hasPrefix("./")
                || word.hasPrefix("../")
            let lastIsFile = segments.last.map { isFileName(String($0)) } ?? false
            // "and/or"-style word pairs are not paths; need a root, a file, or several segments.
            guard rooted || lastIsFile || segments.count >= 3 else { return nil }
            guard segments.allSatisfy({ seg in seg.isEmpty || seg == "~" || seg == "." || seg == ".."
                || seg.contains(where: { $0.isLetter || $0.isNumber }) })
            else { return nil }
            return speak(path: word)
        }
        guard isFileName(word) else { return nil }
        return speak(path: word)
    }

    private static let dottedAbbreviations: Set<String> = [
        "a.m", "p.m", "e.g", "i.e", "u.s", "u.k", "ph.d", "etc", "vs", "no", "st", "mr", "dr", "mrs", "ms",
    ]

    /// "main.swift", ".env", "Package.resolved", "example.com".
    static func isFileName(_ word: String) -> Bool {
        if word.hasPrefix("."), word.count > 1 {
            let rest = word.dropFirst()
            if !rest.contains("."), rest.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
                return rest.contains(where: \.isLetter) && (Lexicon.fileExtensions[rest.lowercased()] != nil
                    || rest.count >= 3)
            }
        }
        let parts = word.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, let ext = parts.last, !ext.isEmpty else { return false }
        // "a..b" is not a file name; a leading dot is (".eslintrc.json").
        guard parts.dropFirst().dropLast().allSatisfy({ !$0.isEmpty }) else { return false }
        guard !dottedAbbreviations.contains(word.lowercased()) else { return false }
        guard ext.first!.isLetter else { return false }
        let stem = parts.dropLast().joined(separator: ".")
        guard stem.contains(where: { $0.isLetter || $0.isNumber }) || word.hasPrefix(".") else { return false }
        let lower = ext.lowercased()
        // A dotted capital abbreviation ("U.S", "Ph.D") is not a file.
        if ext.count <= 2, ext.allSatisfy(\.isUppercase), stem.count <= 2 { return false }
        if Lexicon.fileExtensions[lower] != nil {
            // Single-letter extensions only for lower-case stems ("main.c", not "Mr.T").
            return lower.count > 1 || stem.first.map { $0.isLowercase } ?? false
        }
        return Lexicon.topLevelDomains.contains(lower)
    }

    static func speak(path: String) -> String {
        var pieces: [String] = []
        var rest = Substring(path)
        if rest.hasPrefix("~/") || rest == "~" {
            pieces.append("home")
            rest = rest.dropFirst()
        }
        let segments = rest.split(separator: "/", omittingEmptySubsequences: false)
        for (i, seg) in segments.enumerated() {
            if i > 0 { pieces.append("slash") }
            if !seg.isEmpty { pieces.append(speak(segment: String(seg))) }
        }
        return pieces.joined(separator: " ")
    }

    static func speak(segment: String) -> String {
        if segment == "." { return "dot" }
        if segment == ".." { return "dot dot" }
        let parts = segment.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var words: [String] = []
        for (i, part) in parts.enumerated() {
            if i > 0 { words.append("dot") }
            if part.isEmpty { continue }
            let isExt = i == parts.count - 1 && i > 0
            if isExt, let spoken = Lexicon.fileExtensions[part.lowercased()] {
                words.append(spoken)
            } else if isExt, let label = Lexicon.domainLabels[part.lowercased()] {
                words.append(label)
            } else {
                words.append(readable(part))
            }
        }
        return words.joined(separator: " ")
    }

    /// Splits snake_case, kebab-case and camelCase so the parts read as words.
    static func readable(_ part: String) -> String {
        var s = part.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        s = s.replacingOccurrences(of: "+", with: " plus ")
        var out = ""
        var prev: Character?
        for ch in s {
            if let p = prev, p.isLowercase, ch.isUppercase { out.append(" ") }
            out.append(ch)
            prev = ch
        }
        return out.split(separator: " ").joined(separator: " ")
    }
}
