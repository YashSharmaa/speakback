import Foundation

/// 16-bit PCM mono WAV encoding.
public enum WAV {

    public static func data(samples: [Float], sampleRate: Int) -> Data {
        let dataBytes = samples.count * 2
        var d = Data(capacity: 44 + dataBytes)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8))
        u32(UInt32(36 + dataBytes))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        u32(16)
        u16(1)  // PCM
        u16(1)  // mono
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))
        u16(2)
        u16(16)
        d.append(contentsOf: Array("data".utf8))
        u32(UInt32(dataBytes))
        var pcm = [Int16](repeating: 0, count: samples.count)
        for (i, s) in samples.enumerated() {
            pcm[i] = Int16(max(-1, min(1, s)) * 32767)
        }
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }

    public static func write(samples: [Float], sampleRate: Int, to url: URL) throws {
        try data(samples: samples, sampleRate: sampleRate).write(to: url, options: .atomic)
    }

    /// Reads a 16-bit PCM mono WAV written by `data(samples:sampleRate:)`.
    public static func read(_ data: Data) -> (samples: [Float], sampleRate: Int)? {
        guard data.count >= 44, String(data: data[0..<4], encoding: .ascii) == "RIFF" else { return nil }
        let rate = data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        var offset = 12
        while offset + 8 <= data.count {
            let id = String(data: data[offset..<offset + 4], encoding: .ascii)
            let size = Int(data[offset + 4..<offset + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            if id == "data" {
                let body = data[(offset + 8)..<min(data.count, offset + 8 + size)]
                let samples = body.withUnsafeBytes { raw in
                    raw.bindMemory(to: Int16.self).map { Float($0) / 32767 }
                }
                return (samples, Int(rate))
            }
            offset += 8 + size
        }
        return nil
    }
}

/// Shapes the edges of each synthesised chunk so chunks join without clicks
/// or long silences.
public enum ChunkAudio {

    /// Trims leading and trailing near-silence, leaving a short natural margin,
    /// then appends a pause that suits how the chunk ends.
    public static func shape(_ samples: [Float], sampleRate: Int, text: String) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let threshold: Float = 0.004
        let lead = Int(Double(sampleRate) * 0.02)
        let tailKeep = Int(Double(sampleRate) * 0.04)
        guard let first = samples.firstIndex(where: { abs($0) > threshold }),
            let last = samples.lastIndex(where: { abs($0) > threshold })
        else { return [] }
        let start = max(0, first - lead)
        let end = min(samples.count, last + tailKeep)
        var out = Array(samples[start..<end])
        // 5 ms fades guard against clicks at the cut points.
        let fade = min(out.count / 2, sampleRate / 200)
        for i in 0..<fade {
            let g = Float(i) / Float(fade)
            out[i] *= g
            out[out.count - 1 - i] *= g
        }
        out.append(contentsOf: [Float](repeating: 0, count: Int(Double(sampleRate) * pause(after: text))))
        return out
    }

    /// Seconds of silence after a chunk: longer after a sentence than a clause.
    public static func pause(after text: String) -> Double {
        let end = text.trimmingCharacters(in: .whitespaces).last
        switch end {
        case ".", "!", "?": return 0.28
        case ",", ";", ":": return 0.12
        default: return 0.08
        }
    }
}
