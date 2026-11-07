import Foundation

/// The Kokoro-82M v1.0 voices FluidAudio's English chain accepts.
///
/// Grades are the overall grades in hexgrad/Kokoro-82M VOICES.md (A is best;
/// "-" means ungraded). Every voice reads through the English text frontend,
/// so a non-English voice reads English text with that voice's accent.
public struct Voice: Sendable, Equatable {
    public let id: String
    public let language: String
    public let gender: String
    public let grade: String

    public var isHindi: Bool { id.hasPrefix("hf_") || id.hasPrefix("hm_") }
    public var isBlend: Bool { VoiceCatalog.blends[id] != nil }
    public var isEnglish: Bool { ["a", "b"].contains(id.prefix(1)) }
}

public enum VoiceCatalog {

    /// af_heart: the only English voice graded A overall, warm and natural,
    /// and the upstream and FluidAudio default.
    public static let defaultVoice = "af_heart"

    /// Voices made by mixing Kokoro style vectors (each pack is 510 rows of
    /// 256 floats). The blend is computed once and saved next to the stock packs.
    /// The id keeps the `af_` prefix FluidAudio's ANE-v3 runtime requires.
    public static let blends: [String: [(voice: String, weight: Float)]] = [
        "af_heart_in": [("af_heart", 0.75), ("hf_alpha", 0.25)],
    ]

    /// Short names accepted by `--voice`.
    public static let aliases: [String: String] = [
        "indian": "af_heart_in", "en-in": "af_heart_in", "en_in": "af_heart_in",
    ]

    public static let all: [Voice] = {
        let grades: [(String, String)] = [
            ("af_heart", "A"), ("af_heart_in", "-"), ("af_bella", "A-"), ("af_nicole", "B-"), ("af_aoede", "C+"),
            ("af_kore", "C+"), ("af_sarah", "C+"), ("af_alloy", "C"), ("af_nova", "C"), ("af_sky", "C-"),
            ("af_jessica", "D"), ("af_river", "D"),
            ("am_fenrir", "C+"), ("am_michael", "C+"), ("am_puck", "C+"), ("am_echo", "D"), ("am_eric", "D"),
            ("am_liam", "D"), ("am_onyx", "D"), ("am_santa", "D-"), ("am_adam", "F+"),
            ("bf_emma", "B-"), ("bf_isabella", "C"), ("bf_alice", "D"), ("bf_lily", "D"),
            ("bm_fable", "C"), ("bm_george", "C"), ("bm_lewis", "D+"), ("bm_daniel", "D"),
            ("hf_alpha", "C"), ("hf_beta", "C"), ("hm_omega", "C"), ("hm_psi", "C"),
            ("jf_alpha", "C+"), ("jf_gongitsune", "C"), ("jf_tebukuro", "C"), ("jf_nezumi", "C-"),
            ("jm_kumo", "C-"),
            ("zf_xiaobei", "D"), ("zf_xiaoni", "D"), ("zf_xiaoxiao", "D"), ("zf_xiaoyi", "D"),
            ("zm_yunjian", "D"), ("zm_yunxi", "D"), ("zm_yunxia", "D"), ("zm_yunyang", "D"),
            ("ef_dora", "-"), ("em_alex", "-"), ("em_santa", "-"),
            ("ff_siwis", "B-"),
            ("if_sara", "C"), ("im_nicola", "C"),
            ("pf_dora", "-"), ("pm_alex", "-"), ("pm_santa", "-"),
        ]
        return grades.map { id, grade in
            Voice(id: id, language: language(of: id), gender: id.dropFirst().first == "m" ? "male" : "female",
                  grade: grade)
        }
    }()

    /// The voice for an id or alias ("indian").
    public static func voice(_ id: String) -> Voice? {
        let key = aliases[id.lowercased()] ?? id
        return all.first { $0.id == key }
    }

    static func language(of id: String) -> String {
        if blends[id] != nil { return "Indian English (blend)" }
        switch id.prefix(1) {
        case "a": return "American English"
        case "b": return "British English"
        case "h": return "Hindi"
        case "j": return "Japanese"
        case "z": return "Mandarin"
        case "e": return "Spanish"
        case "f": return "French"
        case "i": return "Italian"
        case "p": return "Brazilian Portuguese"
        default: return "Other"
        }
    }

    /// The `speak --voices` listing.
    public static func listing() -> String {
        var lines: [String] = []
        lines.append("Kokoro-82M voices (grade from hexgrad/Kokoro-82M VOICES.md; A is best).")
        lines.append("All voices read English text. Non-English voices give that accent.")
        lines.append("")
        let groups = Dictionary(grouping: all, by: \.language)
        let order = ["American English", "Indian English (blend)", "British English", "Hindi", "Japanese", "Mandarin", "Spanish",
                     "French", "Italian", "Brazilian Portuguese"]
        for lang in order {
            guard let voices = groups[lang] else { continue }
            var note = ""
            if lang == "Hindi" { note = "  (Indian-accented English; Devanagari text is not read)" }
            if lang == "Indian English (blend)" { note = "  (0.75 af_heart + 0.25 hf_alpha; --voice indian)" }
            lines.append(lang + note)
            for v in voices {
                let mark = v.id == defaultVoice ? "  (default)" : ""
                lines.append("  " + v.id.padding(toLength: 15, withPad: " ", startingAt: 0)
                    + v.gender.padding(toLength: 8, withPad: " ", startingAt: 0)
                    + (v.isBlend ? "blend" : "grade " + v.grade) + mark)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
