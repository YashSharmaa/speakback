@preconcurrency import AVFoundation
import Foundation

/// Gapless streaming playback through `AVAudioEngine` buffer scheduling.
///
/// Chunks are scheduled on one `AVAudioPlayerNode` as they arrive, so each
/// starts the sample after the previous one ends. A new `begin()` flushes
/// whatever is queued, which is how a new request replaces current speech.
///
/// Outputs:
/// - `speakers`: the default output device.
/// - `null`: offline manual rendering, pulled in real time by a background
///   thread and discarded. Behaves like playback, makes no sound.
/// - `manual`: offline manual rendering pulled only by `render(frames:)`.
///   For tests; the rendered audio is kept for inspection.
public final class ScheduledPlayer: @unchecked Sendable {

    public enum Output: String, Sendable {
        case speakers, null, manual
    }

    public let output: Output
    public let sampleRate: Int

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat

    /// Guards the bookkeeping below.
    private let state = NSLock()
    /// Serialises engine and node calls against the offline render pull.
    private let renderLock = NSRecursiveLock()

    private var generation = 0
    private var pendingBuffers = 0
    private var pendingFrames: Int64 = 0
    private var inputFinished = true
    private var underruns = 0
    private var onDrained: (@Sendable () -> Void)?
    private var prepared = false
    private var renderThread: Thread?
    private var renderBuffer: AVAudioPCMBuffer?
    private var captured: [Float] = []
    private var lastPlayback = Date()
    /// Player-timeline frame where the next chunk starts. Guarded by renderLock.
    private var nextFrame: AVAudioFramePosition = 0
    private var nodeStarted = false
    private var firstScheduled = false

    public init(output: Output, sampleRate: Int) {
        self.output = output
        self.sampleRate = sampleRate
        format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
    }

    deinit {
        renderThread?.cancel()
    }

    // MARK: - Public

    /// Starts a new playback session, dropping anything still queued.
    /// Returns the session's generation, which later calls must pass.
    public func begin() throws -> Int {
        let (gen, stale): (Int, (@Sendable () -> Void)?) = state.withLock {
            generation += 1
            pendingBuffers = 0
            pendingFrames = 0
            inputFinished = false
            underruns = 0
            let old = onDrained
            onDrained = nil
            return (generation, old)
        }
        // A superseded session's waiter is released, not left hanging.
        if let stale { DispatchQueue.global().async { stale() } }
        try renderLock.withLock {
            // stop() resets the player timeline to frame 0.
            if prepared { node.stop() }
            nextFrame = 0
            nodeStarted = false
            firstScheduled = false
            try ensureRunning()
            node.play()
            nodeStarted = true
        }
        return gen
    }

    /// Schedules a chunk at an explicit frame, right where the previous one ends.
    ///
    /// Explicit times matter: a buffer scheduled with `at: nil` after the
    /// player has started does not reliably follow the previous buffer
    /// (measured in offline rendering: it can start a whole buffer late).
    /// Scheduling is also applied asynchronously by the render thread, which
    /// is harmless here because chunks are queued well ahead of their start.
    public func enqueue(_ samples: [Float], generation gen: Int) {
        guard !samples.isEmpty else { return }
        guard state.withLock({ gen == generation }) else { return }
        let frames = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        state.withLock {
            pendingBuffers += 1
            pendingFrames += Int64(frames)
        }
        let type: AVAudioPlayerNodeCompletionCallbackType = output == .speakers ? .dataPlayedBack : .dataRendered
        renderLock.withLock {
            if nodeStarted, let now = currentFrame(), nextFrame < now {
                // Nothing queued covers "now" (the first chunk, or the queue ran dry):
                // start this chunk just ahead of the play position so none of it is skipped.
                if firstScheduled { state.withLock { underruns += 1 } }
                // Schedule calls reach the render thread asynchronously, so leave 50 ms of lead.
                nextFrame = now + (output == .manual ? 0 : AVAudioFramePosition(sampleRate / 20))
            }
            firstScheduled = true
            let when = AVAudioTime(sampleTime: nextFrame, atRate: Double(sampleRate))
            node.scheduleBuffer(buffer, at: when, options: [], completionCallbackType: type) { [weak self] _ in
                self?.bufferFinished(frames: Int64(frames), generation: gen)
            }
            nextFrame += AVAudioFramePosition(frames)
        }
    }

    /// The player's current position, once it is rendering.
    private func currentFrame() -> AVAudioFramePosition? {
        guard let nodeTime = node.lastRenderTime, nodeTime.isSampleTimeValid,
            let playerTime = node.playerTime(forNodeTime: nodeTime)
        else { return nil }
        return playerTime.sampleTime
    }

    /// No more chunks for this session. `drained` runs once the last one has played.
    public func finish(generation gen: Int, drained: @escaping @Sendable () -> Void) {
        let fire: Bool = state.withLock {
            guard gen == generation else { return true }
            inputFinished = true
            if pendingBuffers == 0 { return true }
            onDrained = drained
            return false
        }
        if fire { DispatchQueue.global().async { drained() } }
    }

    /// Stops playback at once and drops the queue.
    public func stop() {
        let stale: (@Sendable () -> Void)? = state.withLock {
            generation += 1
            pendingBuffers = 0
            pendingFrames = 0
            inputFinished = true
            let old = onDrained
            onDrained = nil
            return old
        }
        renderLock.withLock {
            node.stop()
            nextFrame = 0
            nodeStarted = false
        }
        if let stale { DispatchQueue.global().async { stale() } }
    }

    /// True while a session has audio queued or more chunks coming.
    public var isActive: Bool {
        state.withLock { pendingBuffers > 0 || !inputFinished }
    }

    /// Seconds of audio scheduled but not yet played.
    public var queuedSeconds: Double {
        state.withLock { Double(pendingFrames) / Double(sampleRate) }
    }

    /// Times the current session ran out of audio before its input finished.
    public func underrunCount(generation gen: Int) -> Int {
        state.withLock { gen == generation ? underruns : 0 }
    }

    /// When audio last finished playing.
    public var lastPlaybackEnded: Date { state.withLock { lastPlayback } }

    /// Releases the output device after playback (speakers only).
    public func pauseIfIdle() {
        guard output == .speakers, !isActive else { return }
        renderLock.withLock { if engine.isRunning { engine.pause() } }
    }

    // MARK: - Manual rendering (tests)

    /// Pulls `frames` frames through the engine. `manual` output only.
    @discardableResult
    public func render(frames: Int) throws -> Int {
        precondition(output == .manual, "render(frames:) is for the manual output")
        return try pull(frames: frames)
    }

    /// Everything rendered so far by `render(frames:)`.
    public var renderedSamples: [Float] { state.withLock { captured } }

    // MARK: - Private

    private func bufferFinished(frames: Int64, generation gen: Int) {
        let drained: (@Sendable () -> Void)? = state.withLock {
            guard gen == generation else { return nil }
            pendingBuffers = max(0, pendingBuffers - 1)
            pendingFrames = max(0, pendingFrames - frames)
            guard pendingBuffers == 0 else { return nil }
            lastPlayback = Date()
            guard inputFinished else { return nil }
            let cb = onDrained
            onDrained = nil
            return cb
        }
        // Never call out while the render pull may be on this stack.
        if let drained { DispatchQueue.global().async { drained() } }
    }

    private func ensureRunning() throws {
        if !prepared {
            engine.attach(node)
            if output != .speakers {
                try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            }
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.prepare()
            prepared = true
        }
        if !engine.isRunning { try engine.start() }
        if output == .null, renderThread == nil { startRenderThread() }
    }

    private func pull(frames: Int) throws -> Int {
        try renderLock.withLock {
            if renderBuffer == nil {
                renderBuffer = AVAudioPCMBuffer(
                    pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount)
            }
            guard let buffer = renderBuffer, engine.isRunning else { return 0 }
            var done = 0
            while done < frames {
                let n = AVAudioFrameCount(min(frames - done, Int(buffer.frameCapacity)))
                let status = try engine.renderOffline(n, to: buffer)
                guard status == .success else { break }
                if output == .manual {
                    let ptr = buffer.floatChannelData![0]
                    let chunk = Array(UnsafeBufferPointer(start: ptr, count: Int(buffer.frameLength)))
                    state.withLock { captured.append(contentsOf: chunk) }
                }
                done += Int(buffer.frameLength)
            }
            return done
        }
    }

    /// Null output: pull audio at real-time pace and discard it.
    private func startRenderThread() {
        let block = 1024
        let period = Double(block) / Double(sampleRate)
        let thread = Thread { [weak self] in
            var next = Date().timeIntervalSinceReferenceDate
            while !Thread.current.isCancelled {
                guard let self else { return }
                _ = try? self.pull(frames: block)
                next += period
                let wait = next - Date().timeIntervalSinceReferenceDate
                if wait > 0 { Thread.sleep(forTimeInterval: wait) } else { next = Date().timeIntervalSinceReferenceDate }
            }
        }
        thread.name = "speak.null-output"
        thread.qualityOfService = .userInitiated
        renderThread = thread
        thread.start()
    }
}
