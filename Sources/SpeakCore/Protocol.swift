import Foundation

/// One request per connection, sent as a single JSON line.
public struct SpeakRequest: Codable, Sendable, Equatable {
    public enum Command: String, Codable, Sendable {
        case speak, stop, status, shutdown, ping, phonemes
    }

    public var command: Command
    public var text: String?
    public var voice: String?
    public var speed: Double?
    /// Absolute path: write a WAV file there instead of playing.
    public var out: String?
    /// Skip normalisation and speak the text exactly as given.
    public var raw: Bool?

    public init(
        command: Command, text: String? = nil, voice: String? = nil, speed: Double? = nil,
        out: String? = nil, raw: Bool? = nil
    ) {
        self.command = command
        self.text = text
        self.voice = voice
        self.speed = speed
        self.out = out
        self.raw = raw
    }
}

/// Server replies, one JSON line each, until the connection closes.
public struct SpeakEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// Request accepted; `chunks` is how many synthesis chunks it was split into.
        case accepted
        /// The first chunk is synthesised and scheduled (or, for `out`, ready).
        case firstAudio = "first_audio"
        /// Playback (or file writing) finished.
        case done
        /// Playback was replaced by a newer request or stopped.
        case interrupted
        case stopped
        case status
        case pong
        case error
    }

    public var event: Kind
    public var message: String?
    public var chunks: Int?
    /// Milliseconds from the request arriving to the first chunk being ready.
    public var firstAudioMs: Double?
    /// Seconds of audio produced.
    public var audioSeconds: Double?
    /// Seconds spent in synthesis.
    public var synthSeconds: Double?
    /// Times the player ran dry before the next chunk arrived (should be 0).
    public var underruns: Int?
    public var path: String?
    public var status: ServerStatus?

    public init(
        _ event: Kind, message: String? = nil, chunks: Int? = nil, firstAudioMs: Double? = nil,
        audioSeconds: Double? = nil, synthSeconds: Double? = nil, underruns: Int? = nil,
        path: String? = nil, status: ServerStatus? = nil
    ) {
        self.event = event
        self.message = message
        self.chunks = chunks
        self.firstAudioMs = firstAudioMs
        self.audioSeconds = audioSeconds
        self.synthSeconds = synthSeconds
        self.underruns = underruns
        self.path = path
        self.status = status
    }
}

public struct ServerStatus: Codable, Sendable, Equatable {
    public var pid: Int32
    public var version: String
    public var uptimeSeconds: Double
    public var idleSeconds: Double
    public var idleTimeoutSeconds: Double
    /// Idle seconds before the model is unloaded (older servers leave it out).
    public var unloadAfterSeconds: Double?
    public var modelState: String
    public var modelLoadSeconds: Double?
    public var engine: String
    public var audioOutput: String
    public var defaultVoice: String
    public var speaking: Bool
    public var currentChunk: Int?
    public var totalChunks: Int?
    public var queuedAudioSeconds: Double
    /// Chunks that fell off the engine's fast path (Kokoro: over 5 s of audio).
    public var slowPathChunks: Int?
    public var footprintMB: Double
    public var residentMB: Double
    public var requestsServed: Int
}

enum LineCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }
}
