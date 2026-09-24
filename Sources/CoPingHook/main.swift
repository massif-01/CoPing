import CoPingIPC
import Darwin
import Foundation

/// The Hook timeout is one second. Reserve time for the bounded local IPC send.
private func readInput() -> Data? {
    let deadline = ProcessInfo.processInfo.systemUptime + 0.4
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)
    while data.count <= HookPayloadSanitizer.maximumInputBytes {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { return nil }
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, Int32(remaining * 1000))
        if ready < 0 && errno == EINTR { continue }
        guard ready > 0 else { return nil }
        let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
        if count == 0 { return data }
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { return nil }
        data.append(contentsOf: buffer.prefix(count))
    }
    return nil
}

private func run() {
    guard ProcessInfo.processInfo.environment["COPING_SETUP"] != "1" else { return }
    guard let data = readInput(),
        let event = try? HookPayloadSanitizer.sanitize(
            data, sourceID: ProcessInfo.processInfo.environment["COPING_SOURCE_ID"])
    else { return }
    do {
        try UnixSocketClient.send(event)
    } catch {
        if ProcessInfo.processInfo.environment["COPING_DEBUG"] == "1" {
            FileHandle.standardError.write(Data("CoPingHook: event delivery failed\n".utf8))
        }
    }
}

run()
