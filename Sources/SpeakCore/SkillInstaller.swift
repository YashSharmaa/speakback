import Foundation

/// `speak install-skill`: teaches coding agents to read answers aloud.
///
/// - Claude Code: a skill at `<config dir>/skills/speak/SKILL.md`. The config
///   dir is `--config-dir`, else `$CLAUDE_CONFIG_DIR`, else `~/.claude`.
/// - Codex: a marked section in `$CODEX_HOME/AGENTS.md` (default `~/.codex`),
///   the global instructions file Codex reads.
/// - OpenCode: a skill at `~/.config/opencode/skills/speak/SKILL.md`, its native
///   global skills folder. (A global `AGENTS.md` there would stop OpenCode
///   falling back to `~/.claude/CLAUDE.md`, so the skill is the quieter choice.)
///
/// Every action is idempotent, and `uninstall` removes only what this wrote.
public struct SkillInstaller {

    public enum Target: String, CaseIterable, Sendable {
        case claude, codex, opencode, deepseek, gemini
    }

    public let environment: [String: String]
    /// Claude Code config folder from `--config-dir`, which wins over `$CLAUDE_CONFIG_DIR`.
    public var claudeConfigDir: String?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment, claudeConfigDir: String? = nil) {
        self.environment = environment
        self.claudeConfigDir = claudeConfigDir
    }

    static let beginMarker = "<!-- BEGIN speak: managed by `speak install-skill`; edits here are replaced -->"
    static let endMarker = "<!-- END speak -->"

    var home: URL {
        URL(fileURLWithPath: environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory())
    }

    private func expand(_ path: String) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))) }
        return URL(fileURLWithPath: path)
    }

    /// The file each target writes.
    public func path(for target: Target) -> URL {
        switch target {
        case .claude:
            let dir = claudeConfigDir ?? environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            let root = dir.map(expand) ?? home.appendingPathComponent(".claude")
            return root.appendingPathComponent("skills/speak/SKILL.md")
        case .codex:
            let root = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : expand($0) }
                ?? home.appendingPathComponent(".codex")
            return root.appendingPathComponent("AGENTS.md")
        case .opencode:
            let config = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : expand($0) }
                ?? home.appendingPathComponent(".config")
            return config.appendingPathComponent("opencode/skills/speak/SKILL.md")
        case .deepseek:
            // DeepSeek-TUI reads SKILL.md folders from ~/.deepseek/skills.
            return home.appendingPathComponent(".deepseek/skills/speak/SKILL.md")
        case .gemini:
            // Gemini CLI reads its global context from ~/.gemini/GEMINI.md.
            return home.appendingPathComponent(".gemini/GEMINI.md")
        }
    }

    // MARK: - Install

    /// Installs for one target and returns a line describing what happened.
    public func install(_ target: Target) throws -> String {
        let url = path(for: target)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: url, encoding: .utf8))
        let updated: String
        switch target {
        case .claude, .opencode, .deepseek:
            if let existing, !existing.contains(SkillTexts.marker) {
                throw InstallError.notOurs(url.path)
            }
            updated = SkillTexts.skill
        case .codex, .gemini:
            updated = Self.withSection(existing ?? "")
        }
        var notes: [String] = []
        if target == .codex {
            let override = url.deletingLastPathComponent().appendingPathComponent("AGENTS.override.md")
            if fm.fileExists(atPath: override.path) {
                notes.append("note: \(override.path) exists and Codex reads it instead of AGENTS.md")
            }
        }
        if target == .opencode, environment["OPENCODE_DISABLE_CLAUDE_CODE_SKILLS"] == nil,
            fm.fileExists(atPath: path(for: .claude).path)
        {
            notes.append("note: OpenCode also reads ~/.claude/skills, where the Claude Code skill is installed")
        }
        let line: String
        if existing == updated {
            line = "\(label(target)): already up to date at \(url.path)"
        } else {
            try updated.write(to: url, atomically: true, encoding: .utf8)
            line = "\(label(target)): \(existing == nil ? "installed" : "updated") \(url.path)"
        }
        return ([line] + notes).joined(separator: "\n")
    }

    /// Removes what `install` wrote and returns a line describing what happened.
    public func uninstall(_ target: Target) throws -> String {
        let url = path(for: target)
        let fm = FileManager.default
        guard let existing = try? String(contentsOf: url, encoding: .utf8) else {
            return "\(label(target)): not installed (\(url.path))"
        }
        switch target {
        case .claude, .opencode, .deepseek:
            guard existing.contains(SkillTexts.marker) else { throw InstallError.notOurs(url.path) }
            try fm.removeItem(at: url)
            let dir = url.deletingLastPathComponent()
            if (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true { try? fm.removeItem(at: dir) }
            return "\(label(target)): removed \(url.path)"
        case .codex, .gemini:
            guard existing.contains(Self.beginMarker) else {
                return "\(label(target)): not installed (\(url.path))"
            }
            let rest = Self.withoutSection(existing)
            if rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try fm.removeItem(at: url)
            } else {
                try rest.write(to: url, atomically: true, encoding: .utf8)
            }
            return "\(label(target)): removed the speak section from \(url.path)"
        }
    }

    private func label(_ target: Target) -> String {
        switch target {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .deepseek: return "DeepSeek-TUI"
        case .gemini: return "Gemini CLI"
        }
    }

    // MARK: - AGENTS.md section

    static var section: String {
        beginMarker + "\n" + SkillTexts.generic.trimmingCharacters(in: .newlines) + "\n" + endMarker + "\n"
    }

    /// `text` with the speak section added, or replaced in place if present.
    static func withSection(_ text: String) -> String {
        if let range = sectionRange(in: text) {
            return text.replacingCharacters(in: range, with: section)
        }
        if text.isEmpty { return section }
        let base = text.hasSuffix("\n") ? text : text + "\n"
        return base + "\n" + section
    }

    /// `text` with the speak section and the blank line before it removed.
    static func withoutSection(_ text: String) -> String {
        guard let range = sectionRange(in: text) else { return text }
        var head = String(text[..<range.lowerBound])
        let tail = String(text[range.upperBound...])
        if head.hasSuffix("\n\n") { head.removeLast() }
        return head + tail
    }

    private static func sectionRange(in text: String) -> Range<String.Index>? {
        guard let begin = text.range(of: beginMarker),
            let end = text.range(of: endMarker, range: begin.upperBound..<text.endIndex)
        else { return nil }
        var upper = end.upperBound
        if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
        return begin.lowerBound..<upper
    }

    public enum InstallError: Error, CustomStringConvertible {
        case notOurs(String)
        public var description: String {
            switch self {
            case .notOurs(let path): return "\(path) exists and was not written by speak; leaving it alone"
            }
        }
    }
}
