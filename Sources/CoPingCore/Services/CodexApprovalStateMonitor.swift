import Darwin
import Foundation
import SQLite3

public final class CodexApprovalStateMonitor: @unchecked Sendable {
    public typealias ObservationHandler =
        @Sendable ([CodexApprovalObservation]) -> Void
    public typealias HealthHandler =
        @Sendable (CodexApprovalMonitorHealth) -> Void

    private let socketPath: String
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let observationHandler: ObservationHandler
    private let healthHandler: HealthHandler
    private let recentSessionProvider: @Sendable (Date) throws -> [String]
    private let decoder = CodexApprovalStateDecoder()

    private var running = false
    private var descriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var reconnectWorkItem: DispatchWorkItem?
    private var recentSessionsTimer: DispatchSourceTimer?
    private var inputBuffer = Data()
    private var clientID: String?
    private var explicitSessionIDs: Set<String> = []
    private var recentSessionIDs: Set<String> = []
    private var followedSessionIDs: Set<String> = []
    private var health: CodexApprovalMonitorHealth = .stopped

    public init(
        socketPath: String = CoPingPaths.codexIPCPath(),
        queue: DispatchQueue = DispatchQueue(label: "com.coping.codex-approval-state"),
        recentSessionProvider: @escaping @Sendable (Date) throws -> [String] = { now in
            try CodexRecentSessionProvider().recentSessionIDs(
                activeWithin: 15 * 60,
                now: now
            )
        },
        healthHandler: @escaping HealthHandler = { _ in },
        observationHandler: @escaping ObservationHandler
    ) {
        self.socketPath = socketPath
        self.queue = queue
        self.recentSessionProvider = recentSessionProvider
        self.healthHandler = healthHandler
        self.observationHandler = observationHandler
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopOnQueue()
        } else {
            queue.sync { stopOnQueue() }
        }
    }

    public func start() {
        queue.async { [self] in
            startOnQueue()
        }
    }

    public func stop() {
        queue.async { [self] in
            stopOnQueue()
        }
    }

    public func follow(sessionID: String) {
        guard !sessionID.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            explicitSessionIDs.insert(sessionID)
            reconcileFollowers()
        }
    }

    public func unfollow(sessionID: String) {
        guard !sessionID.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            explicitSessionIDs.remove(sessionID)
            reconcileFollowers()
        }
    }

    private func startOnQueue() {
        guard !running else { return }
        running = true
        setHealth(.connecting)
        refreshRecentSessions()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in self?.refreshRecentSessions() }
        recentSessionsTimer = timer
        timer.resume()

        connect()
    }

    private func stopOnQueue() {
        guard running else {
            setHealth(.stopped)
            return
        }
        running = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        recentSessionsTimer?.cancel()
        recentSessionsTimer = nil

        if clientID != nil {
            for sessionID in followedSessionIDs {
                sendFollowing(sessionID: sessionID, following: false)
            }
        }
        explicitSessionIDs.removeAll()
        recentSessionIDs.removeAll()
        followedSessionIDs.removeAll()
        decoder.reset()
        disconnect(scheduleReconnect: false)
        setHealth(.stopped)
    }

    private func refreshRecentSessions() {
        guard running else { return }
        do {
            recentSessionIDs = Set(try recentSessionProvider(Date()))
        } catch {
            setHealth(.unavailable)
        }
        reconcileFollowers()
    }

    private func reconcileFollowers() {
        guard running, clientID != nil else { return }
        let desired = explicitSessionIDs.union(recentSessionIDs)

        for sessionID in desired.subtracting(followedSessionIDs) {
            sendFollowing(sessionID: sessionID, following: true)
            followedSessionIDs.insert(sessionID)
        }
        for sessionID in followedSessionIDs.subtracting(desired) {
            sendFollowing(sessionID: sessionID, following: false)
            followedSessionIDs.remove(sessionID)
            decoder.removeSession(sessionID)
        }
    }

    private func connect() {
        guard running, descriptor < 0, secureSocketExists() else {
            setHealth(.unavailable)
            scheduleReconnect()
            return
        }

        let socketFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            setHealth(.unavailable)
            scheduleReconnect()
            return
        }

        var noSignal: Int32 = 1
        setsockopt(
            socketFD,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout.size(ofValue: noSignal))
        )

        guard var address = makeAddress(path: socketPath) else {
            close(socketFD)
            setHealth(.unavailable)
            scheduleReconnect()
            return
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    socketFD,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard result == 0 else {
            close(socketFD)
            setHealth(.unavailable)
            scheduleReconnect()
            return
        }

        let existingFlags = fcntl(socketFD, F_GETFL)
        if existingFlags >= 0 {
            _ = fcntl(socketFD, F_SETFL, existingFlags | O_NONBLOCK)
        }

        descriptor = socketFD
        inputBuffer.removeAll(keepingCapacity: true)
        clientID = nil
        followedSessionIDs.removeAll()

        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailableFrames() }
        source.setCancelHandler { close(socketFD) }
        readSource = source
        source.resume()
        setHealth(.connecting)

        send([
            "type": "request",
            "requestId": "coping-\(UUID().uuidString)",
            "version": 0,
            "method": "initialize",
            "params": ["clientType": "coping"],
        ])
    }

    private func readAvailableFrames() {
        guard descriptor >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 32_768)

        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                inputBuffer.append(contentsOf: buffer.prefix(count))
                guard consumeFrames() else {
                    disconnect(scheduleReconnect: true)
                    return
                }
                continue
            }
            if count == 0 {
                disconnect(scheduleReconnect: true)
                return
            }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }
            disconnect(scheduleReconnect: true)
            return
        }
    }

    private func consumeFrames() -> Bool {
        let maximumFrameBytes = 64 * 1_024 * 1_024

        while inputBuffer.count >= 4 {
            let length = inputBuffer.prefix(4).withUnsafeBytes {
                Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)))
            }
            guard length > 0, length <= maximumFrameBytes else { return false }
            guard inputBuffer.count >= 4 + length else { return true }

            let payload = inputBuffer.subdata(in: 4..<(4 + length))
            inputBuffer.removeSubrange(0..<(4 + length))
            handleFrame(payload)
        }
        return true
    }

    private func handleFrame(_ data: Data) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = root["type"] as? String
        else {
            return
        }

        if type == "response",
            root["method"] as? String == "initialize",
            root["resultType"] as? String == "success",
            let result = root["result"] as? [String: Any],
            let initializedClientID = result["clientId"] as? String
        {
            clientID = initializedClientID
            reconcileFollowers()
            return
        }

        if type == "client-discovery-request",
            let requestID = root["requestId"] as? String
        {
            send([
                "type": "client-discovery-response",
                "requestId": requestID,
                "response": ["canHandle": false],
            ])
            return
        }

        if type == "broadcast",
            root["method"] as? String == "ipc-connection-reset"
        {
            disconnect(scheduleReconnect: true)
            return
        }

        guard
            type == "broadcast",
            root["method"] as? String == "thread-stream-state-changed"
        else {
            return
        }
        do {
            let observations = try decoder.decodeJSONObject(root)
            setHealth(.ready)
            if !observations.isEmpty {
                observationHandler(observations)
            }
        } catch let CodexApprovalStateDecodeError.unsupportedVersion(version) {
            setHealth(.unsupportedProtocol(version))
        } catch {
            setHealth(.unavailable)
        }
    }

    private func sendFollowing(sessionID: String, following: Bool) {
        guard let clientID else { return }
        send([
            "type": "broadcast",
            "method": "thread-stream-following-changed",
            "sourceClientId": clientID,
            "version": 1,
            "params": [
                "conversationId": sessionID,
                "hostId": "local",
                "following": following,
            ],
        ])
    }

    private func send(_ object: [String: Any]) {
        guard
            descriptor >= 0,
            JSONSerialization.isValidJSONObject(object),
            let payload = try? JSONSerialization.data(withJSONObject: object),
            payload.count <= Int(UInt32.max)
        else {
            return
        }

        var length = UInt32(payload.count).littleEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)

        let succeeded = frame.withUnsafeBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else { return true }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count > 0 {
                    offset += count
                    continue
                }
                if errno == EINTR { continue }
                return false
            }
            return true
        }
        if !succeeded {
            disconnect(scheduleReconnect: true)
        }
    }

    private func disconnect(scheduleReconnect: Bool) {
        clientID = nil
        followedSessionIDs.removeAll()
        inputBuffer.removeAll(keepingCapacity: true)

        if let source = readSource {
            readSource = nil
            descriptor = -1
            source.cancel()
        } else if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }

        if scheduleReconnect {
            setHealth(.unavailable)
            self.scheduleReconnect()
        }
    }

    private func setHealth(_ newValue: CodexApprovalMonitorHealth) {
        guard health != newValue else { return }
        health = newValue
        healthHandler(newValue)
    }

    private func scheduleReconnect() {
        guard running, reconnectWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            reconnectWorkItem = nil
            connect()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 1, execute: workItem)
    }

    private func secureSocketExists() -> Bool {
        var socketInfo = stat()
        guard
            lstat(socketPath, &socketInfo) == 0,
            (socketInfo.st_mode & S_IFMT) == S_IFSOCK,
            socketInfo.st_uid == getuid()
        else {
            return false
        }

        var directoryInfo = stat()
        let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        guard
            lstat(directory, &directoryInfo) == 0,
            (directoryInfo.st_mode & S_IFMT) == S_IFDIR,
            directoryInfo.st_uid == getuid()
        else {
            return false
        }
        return directoryInfo.st_mode & (S_IRWXG | S_IRWXO) == 0
    }
}

public enum CodexRecentSessionProviderError: Error {
    case stateDatabaseUnavailable
    case openFailed
    case queryFailed
}

public struct CodexRecentSessionProvider: @unchecked Sendable {
    private let codexDirectory: URL
    private let fileManager: FileManager

    public init(
        codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.codexDirectory = codexDirectory
        self.fileManager = fileManager
    }

    public func recentSessionIDs(
        activeWithin interval: TimeInterval = 15 * 60,
        now: Date = Date()
    ) throws -> [String] {
        guard interval > 0, let databaseURL = newestStateDatabaseURL() else {
            throw CodexRecentSessionProviderError.stateDatabaseUnavailable
        }

        var database: OpaquePointer?
        guard
            sqlite3_open_v2(
                databaseURL.path,
                &database,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
                nil
            ) == SQLITE_OK,
            let database
        else {
            if let database { sqlite3_close(database) }
            throw CodexRecentSessionProviderError.openFailed
        }
        defer { sqlite3_close(database) }

        let cutoffMilliseconds = Int64(
            now.addingTimeInterval(-interval).timeIntervalSince1970 * 1_000
        )
        let cutoffSeconds = cutoffMilliseconds / 1_000
        let currentQuery = """
            SELECT id
            FROM threads
            WHERE archived = 0
              AND COALESCE(thread_source, '') != 'subagent'
              AND source NOT LIKE '%guardian%'
              AND recency_at_ms >= ?
            ORDER BY recency_at_ms DESC, id DESC
            """
        let fallbackQuery = """
            SELECT id
            FROM threads
            WHERE archived = 0
              AND source NOT LIKE '%guardian%'
              AND (
                (updated_at > 100000000000 AND updated_at >= ?)
                OR
                (updated_at <= 100000000000 AND updated_at >= ?)
              )
            ORDER BY updated_at DESC, id DESC
            """

        for (query, bindings) in [
            (currentQuery, [cutoffMilliseconds]),
            (fallbackQuery, [cutoffMilliseconds, cutoffSeconds]),
        ] {
            var statement: OpaquePointer?
            guard
                sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
                let statement
            else {
                continue
            }
            defer { sqlite3_finalize(statement) }
            for (offset, value) in bindings.enumerated() {
                sqlite3_bind_int64(statement, Int32(offset + 1), value)
            }

            var sessionIDs: [String] = []
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    let sessionID = String(cString: text)
                    if !sessionID.isEmpty {
                        sessionIDs.append(sessionID)
                    }
                }
                result = sqlite3_step(statement)
            }
            guard result == SQLITE_DONE else {
                continue
            }
            return sessionIDs
        }
        throw CodexRecentSessionProviderError.queryFailed
    }

    private func newestStateDatabaseURL() -> URL? {
        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: codexDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }

        return urls.compactMap { url -> (version: Int, url: URL)? in
            let name = url.lastPathComponent
            guard
                name.hasPrefix("state_"),
                name.hasSuffix(".sqlite"),
                let version = Int(name.dropFirst(6).dropLast(7))
            else {
                return nil
            }
            return (version, url)
        }
        .max { $0.version < $1.version }?
        .url
    }
}

private func makeAddress(path: String) -> sockaddr_un? {
    var address = sockaddr_un()
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard path.utf8CString.count <= capacity else { return nil }

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
