import Foundation

/// Where speak keeps its socket, models and logs.
///
/// Everything lives under `~/Library/Application Support/speak`, or under
/// `$SPEAK_HOME` when that is set (tests use a temporary folder).
public struct SpeakPaths: Sendable {
    public let root: URL

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let home = environment["SPEAK_HOME"], !home.isEmpty {
            root = URL(fileURLWithPath: home, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            root = support.appendingPathComponent("speak", isDirectory: true)
        }
    }

    public var socket: URL { root.appendingPathComponent("speak.sock") }
    public var lock: URL { root.appendingPathComponent("server.lock") }
    public var log: URL { root.appendingPathComponent("server.log") }
    /// FluidAudio's model root: Core ML bundles, voice packs and G2P assets.
    public var models: URL { root.appendingPathComponent("models", isDirectory: true) }

    public func ensure() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
    }
}
