import Foundation

/// Spells numbers as English words. Pure and deterministic.
public enum NumberWords {

    private static let ones = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen",
    ]
    private static let tens = [
        "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
    ]
    private static let scales: [(UInt64, String)] = [
        (1_000_000_000_000_000_000, "quintillion"),
        (1_000_000_000_000_000, "quadrillion"),
        (1_000_000_000_000, "trillion"),
        (1_000_000_000, "billion"),
        (1_000_000, "million"),
        (1_000, "thousand"),
    ]

    /// "1520" → "one thousand five hundred twenty". No "and", as in American usage.
    public static func cardinal(_ value: UInt64) -> String {
        if value < 100 { return belowHundred(Int(value)) }
        if value < 1000 { return belowThousand(Int(value)) }
        var parts: [String] = []
        var rest = value
        for (scale, name) in scales where rest >= scale {
            let count = rest / scale
            rest %= scale
            parts.append(cardinal(count) + " " + name)
        }
        if rest > 0 { parts.append(belowThousand(Int(rest))) }
        return parts.joined(separator: " ")
    }

    /// Signed integer.
    public static func cardinal(_ value: Int) -> String {
        value < 0 ? "minus " + cardinal(UInt64(-value)) : cardinal(UInt64(value))
    }

    /// Spells a run of digits, which may be too long for an integer.
    /// Leading zeros and very long runs are read digit by digit.
    public static func cardinal(digits: String) -> String {
        guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit) else { return digits }
        if digits.count > 1, digits.first == "0" { return digitByDigit(digits) }
        if digits.count > 18 { return digitByDigit(digits) }
        return cardinal(UInt64(digits)!)
    }

    /// "0123" → "zero one two three".
    public static func digitByDigit(_ digits: String) -> String {
        digits.compactMap { $0.wholeNumberValue }.map { ones[$0] }.joined(separator: " ")
    }

    /// "2.30" → "two point three zero"; "0.5" → "zero point five".
    public static func decimal(integer: String, fraction: String) -> String {
        let whole = integer.isEmpty ? "zero" : cardinal(digits: integer)
        guard !fraction.isEmpty else { return whole }
        return whole + " point " + digitByDigit(fraction)
    }

    /// Ordinal: 1 → "first", 22 → "twenty second".
    public static func ordinal(_ value: UInt64) -> String {
        let words = cardinal(value)
        var parts = words.split(separator: " ").map(String.init)
        guard let last = parts.popLast() else { return words }
        parts.append(ordinalWord(last))
        return parts.joined(separator: " ")
    }

    /// Year reading: 1999 → "nineteen ninety nine", 2005 → "two thousand five",
    /// 2026 → "twenty twenty six", 1900 → "nineteen hundred".
    public static func year(_ value: Int) -> String {
        guard value >= 1000, value <= 9999 else { return cardinal(value) }
        let high = value / 100
        let low = value % 100
        if value % 1000 < 10 && (value / 1000) % 10 != 0 && high % 10 == 0 {
            // 2000-2009, 3000-3009 → "two thousand (five)"
            return cardinal(value)
        }
        if low == 0 { return belowHundred(high) + " hundred" }
        if low < 10 { return belowHundred(high) + " oh " + ones[low] }
        return belowHundred(high) + " " + belowHundred(low)
    }

    // MARK: - Private

    private static func belowHundred(_ value: Int) -> String {
        if value < 20 { return ones[value] }
        let t = tens[value / 10]
        return value % 10 == 0 ? t : t + " " + ones[value % 10]
    }

    private static func belowThousand(_ value: Int) -> String {
        if value < 100 { return belowHundred(value) }
        let head = ones[value / 100] + " hundred"
        return value % 100 == 0 ? head : head + " " + belowHundred(value % 100)
    }

    private static func ordinalWord(_ word: String) -> String {
        switch word {
        case "one": return "first"
        case "two": return "second"
        case "three": return "third"
        case "five": return "fifth"
        case "eight": return "eighth"
        case "nine": return "ninth"
        case "twelve": return "twelfth"
        default:
            if word.hasSuffix("y") { return String(word.dropLast()) + "ieth" }
            return word + "th"
        }
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
