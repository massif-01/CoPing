import Darwin
import Foundation
import OSLog

private let hookSocketLogger = Logger(
    subsystem: "com.coping.app",
    category: "HookSocket"
)

public enum UnixSocketError: Error {
    case createFailed(Int32)
    case pathTooLong
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case writeFailed(Int32)
}

public final class UnixSocketServer: @unchecked Sendable {
    public typealias EventHandler = @Sendable (CodexEvent) -> Void

    private let path: String
    private let queue: DispatchQueue
    private let handler: EventHandler
    private let eventIDProvider: @Sendable () -> String
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?

    public init(
        path: String = defaultSocketPath(),
        queue: DispatchQueue = DispatchQueue(label: "com.coping.socket"),
        eventIDProvider: @escaping @Sendable () -> String = { UUID().uuidString },
        handler: @escaping EventHandler
    ) {
        self.path = path
        self.queue = queue
        self.eventIDProvider = eventIDProvider
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard descriptor < 0 else { return }
        let socketFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw UnixSocketError.createFailed(errno) }

        var noSignal: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        unlink(path)

        var address = try makeAddress(path: path)
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(socketFD)
            throw UnixSocketError.bindFailed(code)
        }
        chmod(path, S_IRUSR | S_IWUSR)

        guard Darwin.listen(socketFD, 8) == 0 else {
            let code = errno
            close(socketFD)
            unlink(path)
            throw UnixSocketError.listenFailed(code)
        }

        descriptor = socketFD
        let readSource = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        readSource.setEventHandler { [weak self] in self?.acceptAvailableConnections() }
        readSource.setCancelHandler { close(socketFD) }
        source = readSource
        readSource.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
        unlink(path)
    }

    private func acceptAvailableConnections() {
        guard descriptor >= 0 else { return }
        let client = Darwin.accept(descriptor, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }

        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while collected.count <= 16_384 {
            let count = Darwin.read(client, &buffer, buffer.count)
            if count <= 0 { break }
            collected.append(contentsOf: buffer.prefix(count))
            if collected.last == 0x0A { break }
        }
        guard collected.count <= 16_384 else { return }
        if collected.last == 0x0A { collected.removeLast() }
        guard let decoded = try? JSONDecoder().decode(CodexEvent.self, from: collected) else {
            hookSocketLogger.error(
                "Rejected local Hook event bytes=\(collected.count, privacy: .public)"
            )
            return
        }
        let event = decoded.addingEventIDIfMissing(eventIDProvider())
        hookSocketLogger.info(
            "Received \(event.type.rawValue, privacy: .public) session=\(event.sessionID, privacy: .public) turn=\(event.turnID ?? "-", privacy: .public)"
        )
        handler(event)
    }
}

public enum UnixSocketClient {
    public static func send(
        _ event: CodexEvent,
        path: String = defaultSocketPath()
    ) throws {
        let socketFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw UnixSocketError.createFailed(errno) }
        defer { close(socketFD) }

        var noSignal: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))

        var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))

        var address = try makeAddress(path: path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw UnixSocketError.connectFailed(errno) }

        var payload = try JSONEncoder().encode(event)
        payload.append(0x0A)
        try payload.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(socketFD, base.advanced(by: offset), rawBuffer.count - offset)
                guard count > 0 else { throw UnixSocketError.writeFailed(errno) }
                offset += count
            }
        }
    }
}

@usableFromInline
internal func defaultSocketPath(userID: uid_t = getuid()) -> String {
    "/tmp/coping-\(userID).sock"
}

private func makeAddress(path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard bytes.count <= capacity else { throw UnixSocketError.pathTooLong }
    path.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                destination.initialize(repeating: 0, count: capacity)
                strncpy(destination, source, capacity - 1)
            }
        }
    }
    return address
}
