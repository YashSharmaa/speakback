import Foundation

/// Splits normalised text into sentences, then into synthesis chunks.
///
/// The first chunk plays alone so audio starts as soon as possible; later
/// sentences are packed together up to `maxChars`. Sentences longer than the
/// limit split at clause punctuation, then before a conjunction, then at a space.
public struct SpeechChunker: Sendable {

    public var firstMaxChars: Int
    public var maxChars: Int
    /// The first sentence is cut at its first comma past this many characters,
    /// so the first chunk is tiny and audio starts sooner. Zero turns it off.
    public var firstCommaAfter: Int

    public init(firstMaxChars: Int = 120, maxChars: Int = 220, firstCommaAfter: Int = 35) {
        self.firstMaxChars = firstMaxChars
        self.maxChars = maxChars
        self.firstCommaAfter = firstCommaAfter
    }

    /// Kokoro reads about 17 characters a second at speed 1.0. The first chunk
    /// is held to about 4 s of audio so it is ready quickly. With
    /// `fastPathOnly` every chunk is (FluidAudio's ANE-v3 fast path covers 5 s
    /// per call); otherwise later chunks carry whole sentences for better prosody.
    public static func forKokoro(speed: Double, fastPathOnly: Bool = false) -> SpeechChunker {
        let short = max(40, Int((68 * speed).rounded()))
        return SpeechChunker(firstMaxChars: short, maxChars: fastPathOnly ? short : max(short, 220))
    }

    private static let conjunctions = [
        " and ", " but ", " or ", " so ", " because ", " which ", " while ", " although ", " then ",
        " that ", " with ", " where ", " when ", " if ",
    ]

    private static let noBreakAfter: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "no", "inc", "ltd", "co", "corp",
        "fig", "approx", "dept", "est", "mt", "gen", "col", "lt", "sgt", "rev",
    ]

    /// Sentences, in order. Each normalised unit (line) is at least one sentence.
    public static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            out.append(contentsOf: sentences(inLine: line))
        }
        return out
    }

    static func sentences(inLine line: String) -> [String] {
        let chars = Array(line)
        var out: [String] = []
        var current = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            current.append(c)
            if ".!?".contains(c) {
                // Absorb closing quotes, brackets and repeated marks.
                while i + 1 < chars.count, ".!?\"')]”’".contains(chars[i + 1]) {
                    i += 1
                    current.append(chars[i])
                }
                let atEnd = i + 1 >= chars.count
                let nextIsSpace = !atEnd && chars[i + 1].isWhitespace
                if atEnd || (nextIsSpace && startsSentence(chars, from: i + 1)) {
                    if c == ".", endsWithAbbreviation(current) {
                        i += 1
                        continue
                    }
                    let s = current.trimmingCharacters(in: .whitespaces)
                    if !s.isEmpty { out.append(s) }
                    current = ""
                }
            }
            i += 1
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    private static func startsSentence(_ chars: [Character], from index: Int) -> Bool {
        var j = index
        while j < chars.count, chars[j].isWhitespace || "\"'(“‘".contains(chars[j]) { j += 1 }
        guard j < chars.count else { return true }
        let c = chars[j]
        return c.isUppercase || c.isNumber || !c.isLetter
    }

    private static func endsWithAbbreviation(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces).dropLast()
        let last = trimmed.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        let word = last.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "(\"'"))
        if noBreakAfter.contains(word) { return true }
        // Single initials: "J. Smith".
        return word.count == 1 && word.first!.isLetter && last.first!.isUppercase
    }

    /// Synthesis chunks for normalised text.
    public func chunks(_ text: String) -> [String] {
        let sentences = Self.sentences(text)
        var pieces: [String] = []
        for (n, s) in sentences.enumerated() {
            if n == 0, let (head, rest) = firstCommaCut(s) {
                pieces.append(head)
                pieces.append(contentsOf: Self.split(rest, limit: maxChars))
                continue
            }
            let limit = n == 0 ? firstMaxChars : maxChars
            pieces.append(contentsOf: Self.split(s, limit: limit))
        }
        // The first piece plays alone; later pieces pack up to maxChars.
        var out: [String] = []
        for piece in pieces {
            if out.count >= 2, let last = out.last, last.count + 1 + piece.count <= maxChars {
                out[out.count - 1] = last + " " + piece
            } else {
                out.append(piece)
            }
        }
        return out
    }

    /// The first sentence cut after its first comma at or past `firstCommaAfter`
    /// characters, if that comma falls within `firstMaxChars` and is followed by a space.
    func firstCommaCut(_ sentence: String) -> (String, String)? {
        guard firstCommaAfter > 0 else { return nil }
        let chars = Array(sentence)
        guard chars.count > firstCommaAfter else { return nil }
        for i in firstCommaAfter..<min(chars.count - 1, firstMaxChars) where chars[i] == "," && chars[i + 1] == " " {
            let head = String(chars[...i])
            let rest = String(chars[(i + 1)...]).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : (head, rest)
        }
        return nil
    }

    /// Splits a long sentence at clause punctuation, then at spaces, to fit `limit`.
    static func split(_ sentence: String, limit: Int) -> [String] {
        guard sentence.count > limit else { return [sentence] }
        var parts: [String] = []
        var rest = Substring(sentence)
        while rest.count > limit {
            let window = rest.prefix(limit)
            let minCut = window.index(window.startIndex, offsetBy: limit / 3)
            var cut: Substring.Index?
            for marks in [",;:", ")"] {
                if let idx = window[minCut...].lastIndex(where: { marks.contains($0) }) {
                    cut = window.index(after: idx)
                    break
                }
            }
            if cut == nil {
                // Break before a conjunction so each part reads as a phrase.
                let tail = window[minCut...]
                cut = conjunctions.compactMap { tail.range(of: $0, options: .backwards)?.lowerBound }.max()
            }
            if cut == nil, let idx = window[minCut...].lastIndex(of: " ") {
                cut = idx
            }
            let at = cut ?? window.endIndex
            let head = rest[..<at].trimmingCharacters(in: .whitespaces)
            if !head.isEmpty { parts.append(head) }
            rest = rest[at...].drop(while: { $0.isWhitespace })
        }
        let tail = rest.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { parts.append(tail) }
        return parts
    }
}
