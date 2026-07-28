import CoPingIPC
import Foundation

private func run() {
    guard ProcessInfo.processInfo.environment["COPING_SETUP"] != "1" else { return }
    guard
        let data = try? FileHandle.standardInput.read(upToCount: HookPayloadSanitizer.maximumInputBytes + 1),
        data.count <= HookPayloadSanitizer.maximumInputBytes,
        let event = try? HookPayloadSanitizer.sanitize(data)
    else {
        return
    }
    do {
        try UnixSocketClient.send(event)
    } catch {
        if ProcessInfo.processInfo.environment["COPING_DEBUG"] == "1" {
            FileHandle.standardError.write(Data("CoPingHook: event delivery failed\n".utf8))
        }
    }
}

run()
