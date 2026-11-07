import Darwin
import Foundation

public enum SocketError: Error, CustomStringConvertible {
    case pathTooLong(String)
    case system(String, Int32)

    public var description: String {
        switch self {
        case .pathTooLong(let p): return "socket path is too long for a Unix socket: \(p)"
        case .system(let call, let code): return "\(call) failed: \(String(cString: strerror(code)))"
        }
    }
}

/// Minimal blocking Unix-domain stream socket helpers.
enum UnixSocket {

    static func address(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { throw SocketError.pathTooLong(path) }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return addr
    }

    static func listen(at path: String) throws -> Int32 {
        var addr = try address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket", errno) }
        unlink(path)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let e = errno
            close(fd)
            throw SocketError.system("bind", e)
        }
        chmod(path, 0o600)
        guard Darwin.listen(fd, 16) == 0 else {
            let e = errno
            close(fd)
            throw SocketError.system("listen", e)
        }
        return fd
    }

    static func connect(to path: String) throws -> Int32 {
        var addr = try address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket", errno) }
        noSigPipe(fd)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let e = errno
            close(fd)
            throw SocketError.system("connect", e)
        }
        return fd
    }

    static func noSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Writes all of `data`; false if the peer went away.
    @discardableResult
    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard var p = raw.baseAddress else { return true }
            var left = raw.count
            while left > 0 {
                let n = Darwin.write(fd, p, left)
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                left -= n
                p += n
            }
            return true
        }
    }
}

/// Reads newline-delimited messages from a blocking file descriptor.
final class LineReader {
    private let fd: Int32
    private var buffer = Data()
    private var eof = false

    init(fd: Int32) { self.fd = fd }

    /// The next line without its newline, or nil at end of stream.
    func next(maxBytes: Int = 16 * 1024 * 1024) -> Data? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                return Data(line)
            }
            if eof || buffer.count > maxBytes {
                guard !buffer.isEmpty else { return nil }
                let rest = buffer
                buffer.removeAll()
                return rest
            }
            var chunk = [UInt8](repeating: 0, count: 65536)
            let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, 65536) }
            if n < 0 {
                if errno == EINTR { continue }
                eof = true
            } else if n == 0 {
                eof = true
            } else {
                buffer.append(contentsOf: chunk[0..<n])
            }
        }
    }
}
