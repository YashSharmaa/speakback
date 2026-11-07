import Darwin
import FluidAudio
import Foundation

/// `speak serve`: a long-lived process holding the model warm behind a Unix socket.
public enum SpeakServer {

    /// Runs the server until it is told to shut down or goes idle. Never returns.
    public static func run(paths: SpeakPaths = SpeakPaths(), environment: [String: String] = ProcessInfo.processInfo.environment) -> Never {
        do {
            try paths.ensure()
        } catch {
            fail("cannot create \(paths.root.path): \(error)")
        }

        // One server per user: hold an exclusive lock for the process lifetime.
        // A server that is shutting down still holds the lock for a moment, so retry briefly.
        let lockFD = open(paths.lock.path, O_CREAT | O_RDWR, 0o600)
        var locked = false
        for _ in 0..<50 where lockFD >= 0 {
            if flock(lockFD, LOCK_EX | LOCK_NB) == 0 {
                locked = true
                break
            }
            usleep(100_000)
        }
        guard locked else {
            log("another speak server is already running")
            exit(0)
        }
        signal(SIGPIPE, SIG_IGN)
        AppLogger.minimumLevel = .warning

        var settings = SpeakService.Settings()
        if let idle = environment["SPEAK_IDLE_SECONDS"].flatMap(Double.init), idle > 0 {
            settings.idleTimeout = idle
        }
        if let unload = environment["SPEAK_UNLOAD_SECONDS"].flatMap(Double.init), unload > 0 {
            settings.unloadAfter = unload
        }
        let output: ScheduledPlayer.Output = environment["SPEAK_AUDIO"] == "null" ? .null : .speakers
        let engine = KokoroEngine(
            modelsDirectory: paths.models, defaultVoice: settings.defaultVoice,
            useV3: environment["SPEAK_KOKORO"] == "v3")
        let player = ScheduledPlayer(output: output, sampleRate: engine.sampleRate)
        let service = SpeakService(engine: engine, player: player, settings: settings)

        let listenFD: Int32
        do {
            listenFD = try UnixSocket.listen(at: paths.socket.path)
        } catch {
            fail("cannot listen on \(paths.socket.path): \(error)")
        }
        log("listening on \(paths.socket.path) (pid \(getpid()), audio \(output.rawValue), \(engine.name))")

        let socketPath = paths.socket.path
        let cleanup: @Sendable () -> Never = {
            unlink(socketPath)
            log("exiting")
            exit(0)
        }

        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler { cleanup() }
            source.resume()
            retained.append(source)
        }

        Task { await service.warmUp() }

        // Idle unload, then idle shutdown.
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if await service.unloadIfIdle() {
                    log("model unloaded after \(Int(settings.unloadAfter)) s idle")
                }
                if await service.shouldExit() {
                    log("idle for \(Int(settings.idleTimeout)) s")
                    cleanup()
                }
            }
        }

        let acceptThread = Thread {
            while true {
                let fd = accept(listenFD, nil, nil)
                if fd < 0 {
                    if errno == EINTR { continue }
                    log("accept failed: \(String(cString: strerror(errno)))")
                    continue
                }
                UnixSocket.noSigPipe(fd)
                let worker = Thread { serve(fd: fd, service: service, cleanup: cleanup) }
                worker.start()
            }
        }
        acceptThread.name = "speak.accept"
        acceptThread.start()
        dispatchMain()
    }

    nonisolated(unsafe) private static var retained: [DispatchSourceSignal] = []

    /// One connection: read a request line, stream events until a final one.
    private static func serve(fd: Int32, service: SpeakService, cleanup: @escaping @Sendable () -> Never) {
        let connection = Connection(fd: fd)
        let reader = LineReader(fd: fd)
        guard let line = reader.next(), let request = try? LineCodec.decode(SpeakRequest.self, from: line) else {
            connection.send(SpeakEvent(.error, message: "bad request"))
            return
        }
        Task {
            await service.handle(request) { event in connection.send(event) }
            if request.command == .shutdown {
                connection.close()
                cleanup()
            }
        }
    }

    static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        FileHandle.standardError.write(Data("[\(stamp)] speak: \(message)\n".utf8))
    }

    private static func fail(_ message: String) -> Never {
        log(message)
        exit(1)
    }
}

/// A client connection; closes itself after a final event.
final class Connection: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32

    init(fd: Int32) { self.fd = fd }

    func send(_ event: SpeakEvent) {
        guard let data = try? LineCodec.encode(event) else { return }
        let final: Bool
        switch event.event {
        case .accepted, .firstAudio: final = false
        default: final = true
        }
        lock.withLock {
            guard fd >= 0 else { return }
            if !UnixSocket.writeAll(fd, data) || final {
                Darwin.close(fd)
                fd = -1
            }
        }
    }

    func close() {
        lock.withLock {
            if fd >= 0 { Darwin.close(fd) }
            fd = -1
        }
    }
}
