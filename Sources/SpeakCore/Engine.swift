import Darwin
import FluidAudio
import Foundation

/// A text-to-speech engine: normalised text in, mono float samples out.
public protocol SpeechEngine: Sendable {
    var sampleRate: Int { get }
    var name: String { get }
    /// Longest audio per call the engine handles on its fast path, if it has one.
    var fastPathSeconds: Double? { get }
    func load() async throws
    func synthesize(_ text: String, voice: String, speed: Double) async throws -> [Float]
    /// The phonemes the engine would speak, for checking pronunciations.
    func phonemes(for text: String) async throws -> String
    /// Chunks synthesised off the engine's fast path, if it has one.
    func slowPathChunks() async -> Int?
    /// Frees the model; the next `load` or `synthesize` brings it back.
    func unload() async
}

extension SpeechEngine {
    public func slowPathChunks() async -> Int? { nil }
    public func unload() async {}
    public var fastPathSeconds: Double? { nil }
}

/// Kokoro-82M through FluidAudio's Core ML pipeline.
public actor KokoroEngine: SpeechEngine {

    public nonisolated let sampleRate = KokoroAneConstants.sampleRate
    public nonisolated let name: String
    public nonisolated let fastPathSeconds: Double?

    private let manager: KokoroAneManager
    private let modelsDirectory: URL
    private let useV3: Bool
    private var loaded = false
    private var blendsReady: Set<String> = []
    private var lexiconReady = false
    private let defaultVoice: String
    private var slowChunks = 0

    /// - Parameters:
    ///   - modelsDirectory: FluidAudio's model root; everything it downloads goes here.
    ///   - useV3: FluidAudio's hybrid ANE-v3 runtime: about twice as fast, but on
    ///     macOS 27.2 (M5 Max) its GPU generator grew the process by about 13 MB
    ///     per chunk, so the long-lived server defaults to the legacy chain.
    public init(modelsDirectory: URL, defaultVoice: String, useV3: Bool = false) {
        self.defaultVoice = defaultVoice
        self.modelsDirectory = modelsDirectory
        self.useV3 = useV3
        self.fastPathSeconds = useV3 ? 5.0 : nil
        self.name = "Kokoro-82M v1.0 via FluidAudio 0.18.2 (" + (useV3 ? "ANE-v3" : "legacy") + ")"
        manager = KokoroAneManager(
            defaultVoice: defaultVoice,
            directory: modelsDirectory,
            version: useV3 ? .v3 : .legacy
        )
    }

    public func load() async throws {
        guard !loaded else { return }
        try await manager.initialize(preloadVoices: [defaultVoice])
        loaded = true
        try await installLexicon()
    }

    public func unload() async {
        loaded = false
        await manager.cleanup()
        // Hand the freed model buffers back to the system now, not at the next allocation.
        malloc_zone_pressure_relief(nil, 0)
    }

    public func synthesize(_ text: String, voice: String, speed: Double) async throws -> [Float] {
        try await load()
        if VoiceCatalog.blends[voice] != nil { try await ensureBlend(voice) }
        let result = try await manager.synthesizeDetailed(text: text, voice: voice, speed: Float(speed))
        if fastPathSeconds != nil, !result.usedFastVocoder {
            slowChunks += 1
            let line = "speak: slow path for \(result.acousticFrames) frames (\(text.count) chars): \(text)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
        return result.samples
    }

    /// Phonemes the frontend would use, for checking pronunciations.
    public func slowPathChunks() async -> Int? { fastPathSeconds == nil ? nil : slowChunks }

    public func phonemes(for text: String) async throws -> String {
        try await load()
        return try await manager.phonemes(for: text)
    }

    // MARK: - Blended voices

    /// Where each runtime looks for `<voice>.bin` packs.
    private func voiceDirectories() -> [URL] {
        let fm = FileManager.default
        let root = modelsDirectory.appendingPathComponent("kokoro-82m-coreml")
        if !useV3 { return [root.appendingPathComponent("ANE")] }
        let v3 = root.appendingPathComponent("ANE-v3")
        let revisions = (try? fm.contentsOfDirectory(atPath: v3.path)) ?? []
        return revisions.map { v3.appendingPathComponent($0).appendingPathComponent("en/voices") }
            .filter { fm.fileExists(atPath: $0.deletingLastPathComponent().path) }
    }

    /// Mixes the blend's source packs row by row and saves it where the
    /// runtime finds voice packs, so FluidAudio loads it like a stock voice.
    private func ensureBlend(_ voice: String) async throws {
        guard !blendsReady.contains(voice), let recipe = VoiceCatalog.blends[voice] else { return }
        let fm = FileManager.default
        let targets = voiceDirectories().map { $0.appendingPathComponent("\(voice).bin") }
        if !targets.isEmpty, targets.allSatisfy({ fm.fileExists(atPath: $0.path) }) {
            blendsReady.insert(voice)
            return
        }
        // Source packs come through FluidAudio's legacy downloader, which
        // converts the upstream Kokoro JSON packs to the flat fp32 layout.
        let sourceDir = modelsDirectory.appendingPathComponent("kokoro-82m-coreml/ANE")
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        var mixed: [Float]?
        for (source, weight) in recipe {
            let url = try await KokoroAneResourceDownloader.ensureVoicePack(source, repoDirectory: sourceDir)
            let pack = try KokoroAneVoicePack.load(from: url)
            mixed = mixed.map { acc in zip(acc, pack.storage).map { $0 + weight * $1 } }
                ?? pack.storage.map { weight * $0 }
        }
        guard let mixed else { return }
        let data = try KokoroAneVoicePack(storage: mixed).binaryData
        for target in targets {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        }
        blendsReady.insert(voice)
    }

    /// Words the English frontend misreads, mapped to a spelling it reads right.
    /// Each respelling is phonemised once and installed as a lexicon override.
    static let pronunciationFixes: [String: String] = [
        "json": "Jason",
        "yammel": "yammel",
    ]

    private func installLexicon() async throws {
        guard !lexiconReady else { return }
        var entries: [String: String] = [:]
        for (word, respelling) in Self.pronunciationFixes {
            let ipa = try await manager.englishPhonemes(for: respelling)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !ipa.isEmpty { entries[word] = ipa }
        }
        await manager.setEnglishCustomLexicon(entries)
        lexiconReady = true
    }
}
