import Foundation

/// Small wrapper over `NSRegularExpression` with closure-based replacement.
/// `NSRegularExpression` is immutable and thread-safe once built.
struct Rx: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        // Patterns are compile-time constants; a bad one is a programming error.
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// One regex match, with helpers to read groups and the text around it.
    struct Match {
        let result: NSTextCheckingResult
        let source: NSString

        /// Capture group `i`, or nil if it did not participate.
        subscript(_ i: Int) -> String? {
            guard i < result.numberOfRanges else { return nil }
            let r = result.range(at: i)
            return r.location == NSNotFound ? nil : source.substring(with: r)
        }

        var whole: String { source.substring(with: result.range) }

        /// Up to `count` characters before the match.
        func before(_ count: Int) -> String {
            let start = max(0, result.range.location - count)
            return source.substring(with: NSRange(location: start, length: result.range.location - start))
        }

        /// Up to `count` characters after the match.
        func after(_ count: Int) -> String {
            let end = result.range.location + result.range.length
            let len = min(count, source.length - end)
            return source.substring(with: NSRange(location: end, length: max(0, len)))
        }
    }

    /// Replace every match with `transform(match)`; returning nil keeps the original text.
    func replace(_ text: String, _ transform: (Match) -> String?) -> String {
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var out = ""
        var cursor = 0
        for m in matches {
            let r = m.range
            out += ns.substring(with: NSRange(location: cursor, length: r.location - cursor))
            let match = Match(result: m, source: ns)
            out += transform(match) ?? match.whole
            cursor = r.location + r.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// Replace with a template string (`$1` and so on).
    func replace(_ text: String, with template: String) -> String {
        let ns = text as NSString
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }

    func matches(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    func firstMatch(_ text: String) -> Match? {
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return Match(result: m, source: ns)
    }
}
