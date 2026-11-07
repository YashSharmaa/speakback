import Darwin
import Foundation

/// Talks to `speak serve`, starting it first if needed.
public struct SpeakClient: Sendable {

    public enum ClientError: Error, CustomStringConvertible {
        case notRunning
        case startFailed(String)
        case closed

        public var description: String {
            switch self {
            case .notRunning: return "the speak server is not running"
            case .startFailed(let why): return "could not start the speak server: \(why)"
            case .closed: return "the speak server closed the connection"
            }
        }
    }

    public let paths: SpeakPaths
    public let environment: [String: String]

    public init(paths: SpeakPaths = SpeakPaths(), environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.paths = paths
        self.environment = environment
    }

    /// Sends `request` and passes each event to `onEvent` until it returns
    /// false or the server sends a final event.
    public func send(
        _ request: SpeakRequest, autostart: Bool, onEvent: (SpeakEvent) -> Bool
    ) throws {
        let fd = try autostart ? connectStartingServer() : connectExisting()
        defer { close(fd) }
        guard UnixSocket.writeAll(fd, try LineCodec.encode(request)) else { throw ClientError.closed }
        let reader = LineReader(fd: fd)
        while let line = reader.next() {
            guard let event = try? LineCodec.decode(SpeakEvent.self, from: line) else { continue }
            if !onEvent(event) { return }
        }
    }

    public func isRunning() -> Bool {
        guard let fd = try? connectExisting() else { return false }
        close(fd)
        return true
    }

    private func connectExisting() throws -> Int32 {
        do {
            return try UnixSocket.connect(to: paths.socket.path)
        } catch SocketError.system(_, let code) where code == ENOENT || code == ECONNREFUSED {
            throw ClientError.notRunning
        }
    }

    /// Connects, spawning `speak serve` in its own session if nothing is listening.
    public func connectStartingServer(timeout: TimeInterval = 20) throws -> Int32 {
        if let fd = try? connectExisting() { return fd }
        try paths.ensure()
        try spawnServer()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let fd = try? connectExisting() { return fd }
            usleep(25_000)
        }
        throw ClientError.startFailed("no answer on \(paths.socket.path) after \(Int(timeout)) s; see \(paths.log.path)")
    }

    private func spawnServer() throws {
        guard let exe = environment["SPEAK_SERVER_BIN"] ?? Bundle.main.executablePath else {
            throw ClientError.startFailed("cannot find my own executable")
        }
        var attr = posix_spawnattr_t(nil as OpaquePointer?)
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Its own session, so closing the terminal does not take the server with it.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        var actions = posix_spawn_file_actions_t(nil as OpaquePointer?)
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, paths.log.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)

        var pid: pid_t = 0
        let args = [exe, "serve"]
        let cArgs = args.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        let env = environment.map { "\($0.key)=\($0.value)" }
        let cEnv = env.map { strdup($0) } + [nil]
        defer { cEnv.forEach { free($0) } }
        let rc = posix_spawn(&pid, exe, &actions, &attr, cArgs, cEnv)
        guard rc == 0 else { throw ClientError.startFailed(String(cString: strerror(rc))) }
    }
}
