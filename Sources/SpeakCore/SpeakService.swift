import Foundation
import SpeakNormalizer

/// The server's brain: keeps the engine warm, runs speak jobs, and streams
/// audio chunks to the player as soon as each is synthesised.
public actor SpeakService {

    public struct Settings: Sendable {
        public var defaultVoice = VoiceCatalog.defaultVoice
        public var defaultSpeed = 1.1
        public var idleTimeout: TimeInterval = 30 * 60
        /// Drop the model from memory after this long idle; the next request reloads it (about 1 s).
        public var unloadAfter: TimeInterval = 15 * 60
        /// Stop synthesising ahead once this much audio is queued.
        public var maxLookaheadSeconds = 30.0
        public init() {}
    }

    public typealias Emit = @Sendable (SpeakEvent) -> Void

    public static let speedRange = 0.8...1.6
    public static let version = "1.0.0"

    private let engine: any SpeechEngine
    private let player: ScheduledPlayer
    private let settings: Settings
    private let normalizer = TextNormalizer()
    private let started = Date()

    private var lastActivity = Date()
    private var modelState = "loading"
    private var modelLoadSeconds: Double?
    private var loadTask: Task<Void, Error>?
    private var playJob: Task<Void, Never>?
    private var playJobID = 0
    private var playEmit: Emit?
    private var progress: (chunk: Int, total: Int)?
    private var requestsServed = 0
    private var activeFileJobs = 0

    public init(engine: any SpeechEngine, player: ScheduledPlayer, settings: Settings = Settings()) {
        self.engine = engine
        self.player = player
        self.settings = settings
    }

    // MARK: - Lifecycle

    /// Loads the model in the background; requests wait for it.
    public func warmUp() {
        guard loadTask == nil else { return }
        let engine = self.engine
        let t0 = Date()
        loadTask = Task {
            do {
                try await engine.load()
                // One short synthesis compiles and warms every stage.
                _ = try await engine.synthesize("Ready.", voice: settings.defaultVoice, speed: 1.0)
                self.modelLoaded(seconds: Date().timeIntervalSince(t0), error: nil)
            } catch {
                self.modelLoaded(seconds: Date().timeIntervalSince(t0), error: error)
                throw error
            }
        }
    }

    private func modelLoaded(seconds: Double, error: Error?) {
        modelLoadSeconds = seconds
        modelState = error == nil ? "ready" : "failed: \(error!)"
        if error != nil { loadTask = nil }
    }

    private func ensureLoaded() async throws {
        if loadTask == nil {
            modelState = "loading"
            warmUp()
        }
        try await loadTask!.value
    }

    /// Seconds since the last speak request or the end of playback.
    private func idleSeconds(now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(max(lastActivity, player.lastPlaybackEnded))
    }

    /// Unloads the model once idle past `unloadAfter` with nothing playing.
    /// Returns true if it unloaded.
    @discardableResult
    public func unloadIfIdle(now: Date = Date()) async -> Bool {
        guard modelState == "ready", let task = loadTask, !player.isActive, activeFileJobs == 0, playJob == nil,
            idleSeconds(now: now) > settings.unloadAfter
        else { return false }
        _ = try? await task.value
        loadTask = nil
        modelState = "unloaded after \(Int(settings.unloadAfter)) s idle (reloads on the next request)"
        modelLoadSeconds = nil
        await engine.unload()
        return true
    }

    /// True once idle for longer than the timeout with nothing playing.
    public func shouldExit(now: Date = Date()) -> Bool {
        guard !player.isActive, activeFileJobs == 0, playJob == nil else { return false }
        let last = max(lastActivity, player.lastPlaybackEnded)
        return now.timeIntervalSince(last) > settings.idleTimeout
    }

    // MARK: - Requests

    public func handle(_ request: SpeakRequest, emit: @escaping Emit) async {
        requestsServed += 1
        // Status checks and pings do not keep the server alive.
        if request.command != .status, request.command != .ping { lastActivity = Date() }
        switch request.command {
        case .ping:
            emit(SpeakEvent(.pong))
        case .status:
            emit(SpeakEvent(.status, status: await status()))
        case .stop:
            stopPlayback(reason: "stopped")
            emit(SpeakEvent(.stopped))
        case .shutdown:
            stopPlayback(reason: "server shutting down")
            emit(SpeakEvent(.stopped, message: "shutting down"))
        case .speak:
            await speak(request, emit: emit)
        case .phonemes:
            do {
                try await ensureLoaded()
                let text = request.raw == true ? request.text ?? "" : normalizer.normalize(request.text ?? "")
                var lines: [String] = []
                for chunk in chunker(speed: settings.defaultSpeed).chunks(text) {
                    lines.append(chunk + "\n  " + (try await engine.phonemes(for: chunk)))
                }
                emit(SpeakEvent(.done, message: lines.joined(separator: "\n")))
            } catch {
                emit(SpeakEvent(.error, message: "\(error)"))
            }
        }
    }

    private func chunker(speed: Double) -> SpeechChunker {
        SpeechChunker.forKokoro(speed: speed, fastPathOnly: engine.fastPathSeconds != nil)
    }

    public func status() async -> ServerStatus {
        let mem = MemoryUsage.current()
        return ServerStatus(
            pid: getpid(),
            version: Self.version,
            uptimeSeconds: Date().timeIntervalSince(started),
            idleSeconds: Date().timeIntervalSince(max(lastActivity, player.lastPlaybackEnded)),
            idleTimeoutSeconds: settings.idleTimeout,
            unloadAfterSeconds: settings.unloadAfter,
            modelState: modelState,
            modelLoadSeconds: modelLoadSeconds,
            engine: engine.name,
            audioOutput: player.output.rawValue,
            defaultVoice: settings.defaultVoice,
            speaking: player.isActive,
            currentChunk: progress?.chunk,
            totalChunks: progress?.total,
            queuedAudioSeconds: player.queuedSeconds,
            slowPathChunks: await engine.slowPathChunks(),
            footprintMB: mem.footprintMB,
            residentMB: mem.residentMB,
            requestsServed: requestsServed
        )
    }

    private func stopPlayback(reason: String) {
        playJob?.cancel()
        playJob = nil
        progress = nil
        player.stop()
        player.pauseIfIdle()
        if let emit = playEmit {
            emit(SpeakEvent(.interrupted, message: reason))
            playEmit = nil
        }
    }

    private func speak(_ request: SpeakRequest, emit: @escaping Emit) async {
        let received = Date()
        let asked = request.voice ?? settings.defaultVoice
        let speed = request.speed ?? settings.defaultSpeed
        guard let voice = VoiceCatalog.voice(asked)?.id else {
            emit(SpeakEvent(.error, message: "unknown voice '\(asked)'; run speak --voices"))
            return
        }
        guard Self.speedRange.contains(speed) else {
            emit(SpeakEvent(.error, message: "speed must be between 0.8 and 1.6"))
            return
        }
        let text = request.text ?? ""
        let spoken = request.raw == true ? text : normalizer.normalize(text)
        let chunks = chunker(speed: speed).chunks(spoken)
        guard !chunks.isEmpty else {
            emit(SpeakEvent(.error, message: "nothing to say"))
            return
        }

        if let out = request.out {
            activeFileJobs += 1
            defer { activeFileJobs -= 1 }
            await writeFile(chunks: chunks, voice: voice, speed: speed, path: out, received: received, emit: emit)
            lastActivity = Date()
            return
        }

        // A new playback replaces the current one.
        stopPlayback(reason: "replaced by a newer request")
        playJobID += 1
        let id = playJobID
        playEmit = emit
        emit(SpeakEvent(.accepted, chunks: chunks.count))
        playJob = Task { [weak self] in
            await self?.play(chunks: chunks, voice: voice, speed: speed, received: received, id: id, emit: emit)
        }
    }

    // MARK: - Playback

    private func play(chunks: [String], voice: String, speed: Double, received: Date, id: Int, emit: @escaping Emit) async {
        do {
            try await ensureLoaded()
            try Task.checkCancellation()
            let gen = try player.begin()
            var synth = 0.0
            var audio = 0.0
            var firstSent = false
            for (i, chunk) in chunks.enumerated() {
                // Keep generating ahead, but not unboundedly.
                while player.queuedSeconds > settings.maxLookaheadSeconds {
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                try Task.checkCancellation()
                progress = (i + 1, chunks.count)
                let t0 = Date()
                let raw = try await engine.synthesize(chunk, voice: voice, speed: speed)
                synth += Date().timeIntervalSince(t0)
                try Task.checkCancellation()
                let shaped = ChunkAudio.shape(raw, sampleRate: engine.sampleRate, text: chunk)
                audio += Double(shaped.count) / Double(engine.sampleRate)
                player.enqueue(shaped, generation: gen)
                if !firstSent {
                    firstSent = true
                    emit(SpeakEvent(.firstAudio, firstAudioMs: Date().timeIntervalSince(received) * 1000))
                }
            }
            let player = self.player
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                player.finish(generation: gen) { cont.resume() }
            }
            try Task.checkCancellation()
            let underruns = player.underrunCount(generation: gen)
            finishPlayJob(id: id)
            emit(SpeakEvent(.done, chunks: chunks.count, audioSeconds: audio, synthSeconds: synth, underruns: underruns))
        } catch is CancellationError {
            // stopPlayback already told the client.
        } catch {
            finishPlayJob(id: id)
            player.stop()
            emit(SpeakEvent(.error, message: "\(error)"))
        }
    }

    private func finishPlayJob(id: Int) {
        guard id == playJobID else { return }
        playJob = nil
        playEmit = nil
        progress = nil
        lastActivity = Date()
        player.pauseIfIdle()
    }

    // MARK: - File output

    private func writeFile(chunks: [String], voice: String, speed: Double, path: String, received: Date, emit: Emit) async {
        do {
            try await ensureLoaded()
            emit(SpeakEvent(.accepted, chunks: chunks.count))
            var samples: [Float] = []
            var synth = 0.0
            for (i, chunk) in chunks.enumerated() {
                let t0 = Date()
                let raw = try await engine.synthesize(chunk, voice: voice, speed: speed)
                synth += Date().timeIntervalSince(t0)
                samples += ChunkAudio.shape(raw, sampleRate: engine.sampleRate, text: chunk)
                if i == 0 {
                    emit(SpeakEvent(.firstAudio, firstAudioMs: Date().timeIntervalSince(received) * 1000))
                }
            }
            let url = URL(fileURLWithPath: path)
            try WAV.write(samples: samples, sampleRate: engine.sampleRate, to: url)
            emit(SpeakEvent(
                .done, chunks: chunks.count, audioSeconds: Double(samples.count) / Double(engine.sampleRate),
                synthSeconds: synth, underruns: 0, path: url.path))
        } catch {
            emit(SpeakEvent(.error, message: "\(error)"))
        }
    }
}
