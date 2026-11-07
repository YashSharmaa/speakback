import Foundation

/// Speaks numbers in context: money, percentages, times, dates, scores,
/// versions, units, ordinals, ranges, decimals and plain integers.
enum NumberText {

    /// A number as written: "1,520", "2.3", "1,50,000" (Indian grouping), ".5".
    static let num = #"(?:\d{1,3}(?:,\d{2,3})+(?:\.\d+)?|\d+\.\d+|\d+|\.\d+)"#

    static func apply(_ s: String) -> String {
        var t = s
        t = money(t)
        t = percent(t)
        t = isoDate(t)
        t = time(t)
        t = bareMeridiem(t)
        t = slashDate(t)
        t = score(t)
        t = version(t)
        t = units(t)
        t = ordinals(t)
        t = hashNumber(t)
        t = ranges(t)
        t = negatives(t)
        t = suffixedScale(t)
        t = alphanumericSplit(t)
        t = decimals(t)
        t = integers(t)
        return t
    }

    // MARK: - Number reading

    /// Spoken form of a written number: commas dropped, decimals read digit by digit.
    static func spoken(_ written: String) -> String {
        let plain = written.replacingOccurrences(of: ",", with: "")
        if let dot = plain.firstIndex(of: ".") {
            let integer = String(plain[..<dot])
            let fraction = String(plain[plain.index(after: dot)...])
            return NumberWords.decimal(integer: integer, fraction: fraction)
        }
        return NumberWords.cardinal(digits: plain)
    }

    static func isOne(_ written: String) -> Bool {
        written.replacingOccurrences(of: ",", with: "") == "1"
    }

    // MARK: - Money

    private struct Currency {
        let one: String, many: String, centOne: String?, centMany: String?
    }

    private static let currencies: [Character: Currency] = [
        "$": Currency(one: "dollar", many: "dollars", centOne: "cent", centMany: "cents"),
        "€": Currency(one: "euro", many: "euros", centOne: "cent", centMany: "cents"),
        "£": Currency(one: "pound", many: "pounds", centOne: "penny", centMany: "pence"),
        "₹": Currency(one: "rupee", many: "rupees", centOne: "paisa", centMany: "paise"),
        "¥": Currency(one: "yen", many: "yen", centOne: nil, centMany: nil),
    ]

    private static let scaleWords: [String: String] = [
        "k": "thousand", "K": "thousand", "thousand": "thousand",
        "m": "million", "M": "million", "mn": "million", "million": "million", "MM": "million",
        "b": "billion", "B": "billion", "bn": "billion", "billion": "billion",
        "t": "trillion", "T": "trillion", "tn": "trillion", "trillion": "trillion",
        "lakh": "lakh", "lakhs": "lakh", "crore": "crore", "crores": "crore", "cr": "crore",
    ]

    private static let moneyRx = Rx(
        #"(-)?([$€£₹¥])\s?("# + num
            + #")(?:\s?(thousand|million|billion|trillion|lakhs?|crores?|mn|bn|tn|cr|MM|[kKmMbBtT])(?![A-Za-z]))?"#)

    static func money(_ s: String) -> String {
        moneyRx.replace(s) { m in
            guard let sym = m[2]?.first, let cur = currencies[sym], let amount = m[3] else { return nil }
            let minus = m[1] != nil ? "minus " : ""
            if let scaleKey = m[4], let scale = scaleWords[scaleKey] {
                return minus + spoken(amount) + " " + scale + " " + cur.many
            }
            let plain = amount.replacingOccurrences(of: ",", with: "")
            var whole = plain
            var cents: Int?
            if let dot = plain.firstIndex(of: ".") {
                whole = String(plain[..<dot])
                let frac = String(plain[plain.index(after: dot)...])
                if frac.count == 2, cur.centMany != nil {
                    cents = Int(frac)
                } else {
                    // "$1.5" with no scale: read as a decimal amount.
                    return minus + spoken(amount) + " " + cur.many
                }
            }
            if whole.isEmpty { whole = "0" }
            let unitWord = whole == "1" ? cur.one : cur.many
            var out = NumberWords.cardinal(digits: whole) + " " + unitWord
            if let c = cents, c > 0, let one = cur.centOne, let many = cur.centMany {
                if whole == "0" {
                    out = NumberWords.cardinal(c) + " " + (c == 1 ? one : many)
                } else {
                    out += " and " + NumberWords.cardinal(c) + " " + (c == 1 ? one : many)
                }
            }
            return minus + out
        }
    }

    // MARK: - Percent

    private static let percentRx = Rx(#"(-)?("# + num + #")\s?%"#)

    static func percent(_ s: String) -> String {
        percentRx.replace(s) { m in
            (m[1] != nil ? "minus " : "") + spoken(m[2]!) + " percent"
        }
    }

    // MARK: - Dates and times

    private static let months = [
        "January", "February", "March", "April", "May", "June", "July", "August",
        "September", "October", "November", "December",
    ]
    private static let isoDateRx = Rx(#"\b(\d{4})-(\d{2})-(\d{2})\b"#)

    static func isoDate(_ s: String) -> String {
        isoDateRx.replace(s) { m in
            guard let y = Int(m[1]!), let mo = Int(m[2]!), let d = Int(m[3]!),
                (1...12).contains(mo), (1...31).contains(d)
            else { return nil }
            return "\(months[mo - 1]) \(NumberWords.ordinal(UInt64(d))), \(NumberWords.year(y))"
        }
    }

    private static let timeRx = Rx(
        #"(?<![\d:])(\d{1,2}):([0-5]\d)(?::([0-5]\d))?(?![\d:])(?:\s?([AaPp])\.?\s?[Mm]\b\.?)?"#)
    /// "10.30 am": a dotted time only counts with am or pm after it.
    private static let dottedTimeRx = Rx(
        #"(?<![\d.])(\d{1,2})\.([0-5]\d)()(?![\d.])\s?([AaPp])\.?\s?[Mm]\b\.?"#)

    static func time(_ s: String) -> String {
        timeRx.replace(dottedTimeRx.replace(s, readTime), readTime)
    }

    private static func readTime(_ m: Rx.Match) -> String? {
        guard let h = Int(m[1]!), let mins = Int(m[2]!), h <= 24 else { return nil }
        // "A M" spaced: written "AM", the engine reads the word "am".
        let meridiem = m[4].map { $0.uppercased() == "A" ? "A M" : "PM" }
        var out: String
        if mins == 0 {
            if meridiem != nil {
                out = NumberWords.cardinal(h)
            } else if h > 12 || h == 0 {
                out = NumberWords.cardinal(h) + " hundred"
            } else {
                out = NumberWords.cardinal(h) + " o'clock"
            }
        } else {
            let minutes = mins < 10 ? "oh " + NumberWords.cardinal(mins) : NumberWords.cardinal(mins)
            out = NumberWords.cardinal(h == 0 && meridiem != nil ? 12 : h) + " " + minutes
        }
        if let sec = m[3].flatMap(Int.init) {
            out += " and " + NumberWords.cardinal(sec) + (sec == 1 ? " second" : " seconds")
        }
        if let mer = meridiem { out += " " + mer }
        return out
    }

    private static let bareMeridiemRx = Rx(#"(?<![\w:.])(\d{1,2})\s?([AaPp])\.?[Mm]\b\.?"#)

    /// "3pm" and "11 a.m." → "three PM", "eleven AM".
    static func bareMeridiem(_ s: String) -> String {
        bareMeridiemRx.replace(s) { m in
            guard let h = Int(m[1]!), (1...12).contains(h) else { return nil }
            return NumberWords.cardinal(h) + (m[2]!.uppercased() == "A" ? " A M" : " PM")
        }
    }

    /// "11/07/2026" is ambiguous between month-first and day-first, so read the parts.
    private static let slashDateRx = Rx(#"(?<![\d/])(\d{1,2})/(\d{1,2})/(\d{2}|\d{4})(?![\d/])"#)

    static func slashDate(_ s: String) -> String {
        slashDateRx.replace(s) { m in
            let y = m[3]!
            let year = y.count == 4 ? NumberWords.year(Int(y)!) : NumberWords.cardinal(digits: y)
            return NumberWords.cardinal(digits: String(Int(m[1]!)!)) + " slash "
                + NumberWords.cardinal(digits: String(Int(m[2]!)!)) + " slash " + year
        }
    }

    // MARK: - Scores

    private static let scoreRx = Rx(#"(?<![\d/.,])(\d+)\s?/\s?(\d+)(?![\d/]|[.,]\d)"#)

    /// "10/10" → "ten of ten". "24/7" stays an idiom.
    static func score(_ s: String) -> String {
        scoreRx.replace(s) { m in
            let a = m[1]!, b = m[2]!
            if a == "24" && b == "7" { return "twenty four seven" }
            return NumberWords.cardinal(digits: a) + " of " + NumberWords.cardinal(digits: b)
        }
    }

    // MARK: - Versions

    private static let versionRx = Rx(#"(?<![\w.])[vV](\d+(?:\.\d+)*)(?![\w.]|\.\d)"#)
    private static let dottedRx = Rx(#"(?<![\w.])(\d+\.\d+\.\d+(?:\.\d+)*)(?![\w.]|\.\d)"#)

    static func version(_ s: String) -> String {
        var t = versionRx.replace(s) { m in
            let said = m.before(8).lowercased().hasSuffix("version ")
            return (said ? "" : "version ") + dotted(m[1]!)
        }
        t = dottedRx.replace(t) { m in dotted(m[1]!) }
        return t
    }

    static func dotted(_ v: String) -> String {
        v.split(separator: ".").map { NumberWords.cardinal(digits: String($0)) }.joined(separator: " point ")
    }

    // MARK: - Units

    private struct Unit {
        let one: String, many: String
        /// Units that collide with ordinary words or letters must touch the number ("5h", not "5 h").
        let needsTight: Bool
    }

    private static let unitTable: [(String, Unit)] = [
        ("ms", Unit(one: "millisecond", many: "milliseconds", needsTight: false)),
        ("µs", Unit(one: "microsecond", many: "microseconds", needsTight: false)),
        ("us", Unit(one: "microsecond", many: "microseconds", needsTight: true)),
        ("ns", Unit(one: "nanosecond", many: "nanoseconds", needsTight: false)),
        ("secs", Unit(one: "second", many: "seconds", needsTight: false)),
        ("sec", Unit(one: "second", many: "seconds", needsTight: false)),
        ("s", Unit(one: "second", many: "seconds", needsTight: false)),
        ("mins", Unit(one: "minute", many: "minutes", needsTight: false)),
        ("min", Unit(one: "minute", many: "minutes", needsTight: false)),
        ("hrs", Unit(one: "hour", many: "hours", needsTight: false)),
        ("hr", Unit(one: "hour", many: "hours", needsTight: false)),
        ("h", Unit(one: "hour", many: "hours", needsTight: true)),
        ("KiB", Unit(one: "kibibyte", many: "kibibytes", needsTight: false)),
        ("MiB", Unit(one: "mebibyte", many: "mebibytes", needsTight: false)),
        ("GiB", Unit(one: "gibibyte", many: "gibibytes", needsTight: false)),
        ("KB", Unit(one: "kilobyte", many: "kilobytes", needsTight: false)),
        ("kB", Unit(one: "kilobyte", many: "kilobytes", needsTight: false)),
        ("MB", Unit(one: "megabyte", many: "megabytes", needsTight: false)),
        ("GB", Unit(one: "gigabyte", many: "gigabytes", needsTight: false)),
        ("TB", Unit(one: "terabyte", many: "terabytes", needsTight: false)),
        ("PB", Unit(one: "petabyte", many: "petabytes", needsTight: false)),
        ("Kb", Unit(one: "kilobit", many: "kilobits", needsTight: false)),
        ("Mb", Unit(one: "megabit", many: "megabits", needsTight: false)),
        ("Gb", Unit(one: "gigabit", many: "gigabits", needsTight: false)),
        ("Mbps", Unit(one: "megabit per second", many: "megabits per second", needsTight: false)),
        ("Gbps", Unit(one: "gigabit per second", many: "gigabits per second", needsTight: false)),
        ("Hz", Unit(one: "hertz", many: "hertz", needsTight: false)),
        ("kHz", Unit(one: "kilohertz", many: "kilohertz", needsTight: false)),
        ("MHz", Unit(one: "megahertz", many: "megahertz", needsTight: false)),
        ("GHz", Unit(one: "gigahertz", many: "gigahertz", needsTight: false)),
        ("mm", Unit(one: "millimeter", many: "millimeters", needsTight: false)),
        ("cm", Unit(one: "centimeter", many: "centimeters", needsTight: false)),
        ("km", Unit(one: "kilometer", many: "kilometers", needsTight: false)),
        ("kg", Unit(one: "kilogram", many: "kilograms", needsTight: false)),
        ("mg", Unit(one: "milligram", many: "milligrams", needsTight: false)),
        ("lbs", Unit(one: "pound", many: "pounds", needsTight: false)),
        ("lb", Unit(one: "pound", many: "pounds", needsTight: false)),
        ("°C", Unit(one: "degree Celsius", many: "degrees Celsius", needsTight: false)),
        ("°F", Unit(one: "degree Fahrenheit", many: "degrees Fahrenheit", needsTight: false)),
        ("°", Unit(one: "degree", many: "degrees", needsTight: false)),
        ("mph", Unit(one: "mile per hour", many: "miles per hour", needsTight: false)),
        ("km/h", Unit(one: "kilometer per hour", many: "kilometers per hour", needsTight: false)),
        ("fps", Unit(one: "frame per second", many: "frames per second", needsTight: false)),
        ("px", Unit(one: "pixel", many: "pixels", needsTight: false)),
        ("pt", Unit(one: "point", many: "points", needsTight: false)),
        ("dpi", Unit(one: "dot per inch", many: "dots per inch", needsTight: false)),
        ("kW", Unit(one: "kilowatt", many: "kilowatts", needsTight: false)),
        ("kWh", Unit(one: "kilowatt hour", many: "kilowatt hours", needsTight: false)),
        ("W", Unit(one: "watt", many: "watts", needsTight: true)),
        ("tok/s", Unit(one: "token per second", many: "tokens per second", needsTight: false)),
        ("x", Unit(one: "times", many: "times", needsTight: true)),
        ("×", Unit(one: "times", many: "times", needsTight: false)),
    ]

    private static let perSuffix: [String: String] = ["s": "second", "sec": "second", "h": "hour", "hr": "hour",
                                                      "min": "minute", "ms": "millisecond", "day": "day"]

    private static let unitRx: Rx = {
        let names = unitTable.map(\.0).sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return Rx(#"(?<![\w.,])(-)?("# + num + #")(\s?)("# + names + #")(?:/(s|sec|h|hr|min|ms|day))?(?![\w°/])"#)
    }()

    private static let unitLookup: [String: Unit] = Dictionary(unitTable, uniquingKeysWith: { a, _ in a })

    static func units(_ s: String) -> String {
        unitRx.replace(s) { m in
            guard let value = m[2], let name = m[4], let unit = unitLookup[name] else { return nil }
            let spaced = !(m[3] ?? "").isEmpty
            if unit.needsTight && spaced { return nil }
            // A bare "s" after a space is too often a stray letter; require a tight "2s" or a decimal.
            if name == "s" && spaced && !value.contains(".") && m.after(1).first.map({ $0.isLetter }) == true {
                return nil
            }
            var out = (m[1] != nil ? "minus " : "") + spoken(value) + " "
            out += isOne(value) ? unit.one : unit.many
            if let per = m[5], let perWord = perSuffix[per] { out += " per " + perWord }
            return out
        }
    }

    // MARK: - Ordinals, hashes, ranges, negatives, scales

    private static let ordinalRx = Rx(#"(?<![\w.])(\d+)(st|nd|rd|th)\b"#)

    static func ordinals(_ s: String) -> String {
        ordinalRx.replace(s) { m in
            guard let v = UInt64(m[1]!) else { return nil }
            return NumberWords.ordinal(v)
        }
    }

    private static let hashRx = Rx(#"(?<![\w&])#(\d+)\b"#)

    static func hashNumber(_ s: String) -> String {
        hashRx.replace(s) { m in "number " + NumberWords.cardinal(digits: m[1]!) }
    }

    private static let rangeRx = Rx(#"(?<![\w.,-])("# + num + #")\s?[–-]\s?("# + num + #")(?![\w.]|\.\d)"#)

    static func ranges(_ s: String) -> String {
        rangeRx.replace(s) { m in
            let a = m[1]!, b = m[2]!
            if isYear(a), isYear(b) {
                return NumberWords.year(Int(a)!) + " to " + NumberWords.year(Int(b)!)
            }
            return spoken(a) + " to " + spoken(b)
        }
    }

    private static let negativeRx = Rx(#"(?<![\w.,)-])-("# + num + #")\b"#)

    static func negatives(_ s: String) -> String {
        negativeRx.replace(s) { m in "minus " + spoken(m[1]!) }
    }

    private static let scaleRx = Rx(#"(?<![\w.,])("# + num + #")(k|K|M|B|bn|T)(?![\w])"#)

    static func suffixedScale(_ s: String) -> String {
        scaleRx.replace(s) { m in
            guard let word = scaleWords[m[2]!] else { return nil }
            return spoken(m[1]!) + " " + word
        }
    }

    // MARK: - Letters and digits together

    private static let letterDigit = Rx(#"(?<=[A-Za-z])(?=\d)|(?<=\d)(?=[A-Za-z])"#)

    /// "M5" → "M 5", "GPT-4o" → "GPT-4 o", so each part reads on its own.
    static func alphanumericSplit(_ s: String) -> String {
        letterDigit.replace(s, with: " ")
    }

    // MARK: - Plain numbers

    private static let decimalRx = Rx(#"(?<![\w.])(\d*\.\d+)(?![\w]|\.\d)"#)

    static func decimals(_ s: String) -> String {
        decimalRx.replace(s) { m in spoken(m[1]!) }
    }

    private static let integerRx = Rx(#"(?<![\w])(\d{1,3}(?:,\d{2,3})+|\d+)(?![\w])"#)
    private static let yearContext = Set([
        "in", "since", "by", "from", "until", "till", "before", "after", "of", "year", "circa", "around",
        "during", "to", "and", "early", "late", "mid", "fall", "spring", "summer", "winter", "january",
        "february", "march", "april", "may", "june", "july", "august", "september", "october",
        "november", "december", "through", "between", "copyright", "©",
    ])

    static func isYear(_ digits: String) -> Bool {
        guard digits.count == 4, let v = Int(digits) else { return false }
        return (1100...2099).contains(v)
    }

    static func integers(_ s: String) -> String {
        integerRx.replace(s) { m in
            let digits = m[1]!
            if isYear(digits) {
                let before = m.before(16).lowercased()
                let prevWord = before.split(whereSeparator: { !$0.isLetter && $0 != "©" }).last.map(String.init)
                let after = m.after(2)
                let endsClause = after.isEmpty || after.first.map({ ".,;:!?)".contains($0) }) == true
                if let w = prevWord, yearContext.contains(w) { return NumberWords.year(Int(digits)!) }
                // "November 7th, 2026" (the day is already words by now).
                let recent = m.before(40).lowercased()
                if months.contains(where: { recent.contains($0.lowercased() + " ") }) {
                    return NumberWords.year(Int(digits)!)
                }
                if endsClause, prevWord != nil, !before.hasSuffix("number "), !before.hasSuffix("of ") {
                    return NumberWords.year(Int(digits)!)
                }
            }
            return spoken(digits)
        }
    }
}
