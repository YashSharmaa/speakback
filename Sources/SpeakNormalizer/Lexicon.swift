import Foundation

/// Word lists: how acronyms, product names, file extensions and units are spoken.
///
/// Plain all-caps initialisms (API, CLI, PR, CI, URL) are left as capitals:
/// they read as letter names. Only words that are said differently from their
/// letters, or that a speech engine is likely to misread, are respelled here.
enum Lexicon {

    /// Case-sensitive whole-word respellings. Longer forms come before the
    /// words they contain ("PostgreSQL" before "Postgres", "MySQL" before "SQL").
    /// The developer terms follow the 2026-11 text-to-speech research lexicon.
    static let respellings: [(String, String)] = [
        ("JSON", "Jason"),
        ("JSONL", "Jason L"),
        ("PostgreSQL", "Post gress Q L"),
        ("Postgres", "Post gress"),
        ("MySQL", "my S Q L"),
        ("NoSQL", "no S Q L"),
        ("SQLite", "S Q Lite"),
        ("SQL", "S Q L"),
        ("GraphQL", "graph Q L"),
        ("OS", "O S"),
        ("iOS", "I O S"),
        ("iPadOS", "eye pad O S"),
        ("macOS", "mac O S"),
        ("watchOS", "watch O S"),
        ("tvOS", "TV O S"),
        ("visionOS", "vision O S"),
        ("iPhone", "eye phone"),
        ("iPad", "eye pad"),
        ("iCloud", "eye cloud"),
        ("GUI", "gooey"),
        ("YAML", "yammel"),
        ("TOML", "tommel"),
        ("WASM", "wazzum"),
        ("OAuth", "oh auth"),
        ("JWT", "J W T"),
        ("SaaS", "sass"),
        ("README", "read me"),
        ("TODO", "to do"),
        ("TODOs", "to dos"),
        ("OK", "okay"),
        ("npm", "N P M"),
        ("pnpm", "P N P M"),
        ("npx", "N P X"),
        ("uv", "U V"),
        ("CI/CD", "C I C D"),
        ("stdin", "standard in"),
        ("stdout", "standard out"),
        ("stderr", "standard error"),
        ("localhost", "local host"),
        ("TypeScript", "Type Script"),
        ("JavaScript", "Java Script"),
        ("PyTorch", "Pie Torch"),
        ("ffmpeg", "F F M peg"),
        ("FFmpeg", "F F M peg"),
        ("regex", "rej ex"),
        ("regexes", "rej exes"),
        ("sudo", "sue doo"),
        ("GIF", "gif"),
        ("ASCII", "ask ee"),
        ("UTF-8", "UTF eight"),
        ("x86", "x eighty six"),
        ("arm64", "arm sixty four"),
        ("M.2", "M two"),
    ]

    static let respellingRules: [(Rx, String)] = respellings.map { word, spoken in
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return (Rx("(?<![\\w./-])" + escaped + "(?![\\w-]|\\.\\w)"), spoken)
    }

    /// Plural of an all-caps initialism, "PRs" → "PR's".
    static func pluralAcronym(_ base: String) -> String {
        base + "'s"
    }

    /// How domain labels are read inside "a link to …".
    static let domainLabels: [String: String] = [
        "io": "IO", "ai": "AI", "co": "co", "uk": "UK", "in": "IN", "gov": "gov",
        "edu": "E D U", "ly": "L Y", "gg": "G G", "sh": "SH", "md": "MD", "tv": "TV",
    ]

    /// File extensions, and how to read them. Unlisted extensions read as written.
    static let fileExtensions: [String: String] = [
        "json": "json", "jsonl": "json L", "swift": "swift", "md": "MD", "markdown": "markdown",
        "txt": "text", "js": "JS", "mjs": "MJS", "cjs": "CJS", "ts": "T S", "tsx": "TSX",
        "jsx": "JSX", "py": "pie", "rs": "RS", "go": "go", "sh": "SH", "zsh": "ZSH",
        "bash": "bash", "fish": "fish", "yml": "yammel", "yaml": "yammel", "toml": "tommel",
        "html": "HTML", "htm": "HTM", "css": "CSS", "scss": "SCSS", "lock": "lock",
        "plist": "P list", "wav": "wave", "mp3": "MP three", "mp4": "MP four", "m4a": "M four A",
        "png": "PNG", "jpg": "J peg", "jpeg": "J peg", "gif": "gif", "svg": "SVG", "webp": "web P",
        "pdf": "PDF", "csv": "CSV", "tsv": "TSV", "xml": "XML", "c": "C", "h": "H",
        "cpp": "C P P", "hpp": "H P P", "cc": "CC", "m": "M", "mm": "MM", "java": "java",
        "kt": "KT", "rb": "ruby", "php": "PHP", "zip": "zip", "gz": "GZ", "tar": "tar",
        "tgz": "TGZ", "env": "env", "log": "log", "sql": "S Q L", "ipynb": "IPYNB",
        "dmg": "DMG", "app": "app", "pkg": "package", "xcodeproj": "xcode proj",
        "xcworkspace": "xcode workspace", "entitlements": "entitlements", "mlmodelc": "ML model C",
        "mlpackage": "ML package", "onnx": "onnx", "safetensors": "safe tensors", "bin": "bin",
        "conf": "conf", "cfg": "config", "ini": "INI", "lua": "lua", "dart": "dart",
        "vue": "view", "svelte": "svelte", "proto": "proto", "graphql": "graph Q L", "dockerfile": "dockerfile",
        "gitignore": "git ignore", "dockerignore": "docker ignore", "npmrc": "N P M RC", "zshrc": "ZSH RC",
        "bashrc": "bash RC", "editorconfig": "editor config", "prettierrc": "prettier RC",
        "eslintrc": "ES lint RC", "nvmrc": "NVM RC", "wasm": "wazzum", "exe": "EXE", "dll": "DLL",
        "so": "SO", "dylib": "dye lib", "a": "A", "o": "O", "xcconfig": "xcode config",
        "resolved": "resolved", "local": "local", "example": "example", "test": "test", "spec": "spec",
        "d": "D", "config": "config", "min": "min", "map": "map", "pem": "PEM", "key": "key",
        "crt": "CRT", "doc": "doc", "docx": "doc X", "xlsx": "excel", "pptx": "power point",
        "mov": "mov", "heic": "heic", "ico": "icon", "ttf": "TTF", "otf": "OTF", "woff2": "woff two",
    ]

    /// Top-level domains, so "example.com" reads as "example dot com".
    static let topLevelDomains: Set<String> = [
        "com", "org", "net", "io", "ai", "dev", "app", "co", "in", "uk", "us", "me",
        "sh", "gg", "xyz", "tech", "cloud", "edu", "gov", "info",
    ]
}
