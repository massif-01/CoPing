import CoPingCore
import Foundation

private struct TestFailure: LocalizedError, CustomStringConvertible {
    let description: String
    var errorDescription: String? { description }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(description: message) }
}

private func testPayloadSanitizer() throws {
    let input = Data(
        """
        {
          "hook_event_name":"Stop",
          "session_id":"session-1",
          "turn_id":"turn-1",
          "cwd":"/Users/test/SecretProject",
          "last_assistant_message":"secret response",
          "prompt":"secret prompt",
          "tool_input":{"command":"secret command"}
        }
        """.utf8
    )
    let event = try HookPayloadSanitizer.sanitize(input, now: Date(timeIntervalSince1970: 1))
    try check(event.type == .completed, "Stop was not mapped to completed")
    try check(event.projectName == "SecretProject", "Project name was not reduced to basename")
    let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
    try check(!encoded.contains("secret"), "Sanitized event leaked private content")
    try check(!encoded.contains("/Users/test"), "Sanitized event leaked full path")

    let question = Data(
        """
        {"hook_event_name":"PreToolUse","session_id":"s","turn_id":"t","cwd":"/tmp/p","tool_name":"request_user_input"}
        """.utf8
    )
    let questionEvent = try HookPayloadSanitizer.sanitize(question)
    try check(questionEvent.type == .questionRequested, "request_user_input was not mapped")

    let otherTool = Data(
        """
        {"hook_event_name":"PreToolUse","session_id":"s","turn_id":"t","cwd":"/tmp/p","tool_name":"Bash"}
        """.utf8
    )
    do {
        _ = try HookPayloadSanitizer.sanitize(otherTool)
        throw TestFailure(description: "Unrelated PreToolUse was accepted")
    } catch HookPayloadError.unsupportedEvent {
        // Expected.
    }
}

private func testHookConfiguration() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoPingSelfTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let hooksURL = directory.appendingPathComponent("hooks.json")
    let helperURL = directory.appendingPathComponent("CoPingHook")
    try Data().write(to: helperURL)

    let original: [String: Any] = [
        "description": "existing",
        "hooks": [
            "Stop": [[
                "hooks": [[
                    "type": "command",
                    "command": "\"/usr/local/bin/existing\"",
                ]],
            ]],
        ],
    ]
    try JSONSerialization.data(withJSONObject: original).write(to: hooksURL)
    let manager = HookConfigurationManager(hooksURL: hooksURL, helperURL: helperURL)
    _ = try manager.installConfiguration()
    _ = try manager.installConfiguration()
    try check(manager.isInstalled(), "Installed hooks were not detected")

    var root = try castRoot(Data(contentsOf: hooksURL))
    var hooks = try castHooks(root)
    let stopGroups = hooks["Stop"] as? [[String: Any]] ?? []
    try check(stopGroups.count == 2, "Idempotent install duplicated or removed existing Stop hook")
    hooks["Stop"] = stopGroups + [[
        "hooks": [["type": "command", "command": "\"/usr/local/bin/keep-me\""]],
    ]]
    root["hooks"] = hooks
    try JSONSerialization.data(withJSONObject: root).write(to: hooksURL)

    try manager.uninstallConfiguration()
    let uninstalled = try castHooks(castRoot(Data(contentsOf: hooksURL)))
    let retained = uninstalled["Stop"] as? [[String: Any]] ?? []
    try check(retained.count == 2, "Uninstall removed a foreign hook")
    try check(!manager.isInstalled(), "Uninstall left CoPing hooks installed")

    let malformed = Data("{broken".utf8)
    try malformed.write(to: hooksURL)
    do {
        _ = try manager.installConfiguration()
        throw TestFailure(description: "Malformed hooks JSON was accepted")
    } catch HookConfigurationError.malformedJSON {
        let retained = try Data(contentsOf: hooksURL)
        try check(retained == malformed, "Malformed hooks JSON was overwritten")
    }
}

private func testSocketRoundTrip() throws {
    let path = "/tmp/coping-test-\(UUID().uuidString).sock"
    let semaphore = DispatchSemaphore(value: 0)
    let expected = CodexEvent(
        type: .completed,
        sessionID: "session",
        turnID: "turn",
        projectName: "project"
    )
    let received = LockedEvent()
    let server = UnixSocketServer(path: path) {
        received.value = $0
        semaphore.signal()
    }
    try server.start()
    defer { server.stop() }
    try UnixSocketClient.send(expected, path: path)
    try check(semaphore.wait(timeout: .now() + 1) == .success, "Socket event timed out")
    try check(received.value == expected, "Socket event changed in transit")
}

private func testKeychainAndHistory() throws {
    let keychain = KeychainStore(
        service: "com.coping.tests.\(UUID().uuidString)",
        account: "device-key"
    )
    defer { try? keychain.delete() }
    let initialKey = try keychain.read()
    try check(initialKey == nil, "Fresh Keychain item was not empty")
    try keychain.save("test-secret")
    let savedKey = try keychain.read()
    try check(savedKey == "test-secret", "Keychain round trip failed")
    try keychain.delete()
    let deletedKey = try keychain.read()
    try check(deletedKey == nil, "Keychain item was not deleted")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoPingHistory-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = DeliveryHistoryStore(
        fileURL: directory.appendingPathComponent("history.json"),
        limit: 2
    )
    let records = (0..<3).map { index in
        DeliveryRecord(
            eventType: .completed,
            projectName: "project-\(index)",
            outcome: .sent
        )
    }
    try store.save(records)
    try check(store.load().count == 2, "History did not enforce its limit")
    try store.clear()
    try check(store.load().isEmpty, "History was not cleared")
}

private final class LockedEvent: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: CodexEvent?

    var value: CodexEvent? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private func testBarkClient() async throws {
    let directConfiguration = try BarkConfiguration(
        baseURLString: "https://bark.example/base",
        deviceKeyInput: "secret-device-key"
    )
    try check(
        directConfiguration.baseURL.absoluteString == "https://bark.example/base",
        "Direct Device Key changed the configured base URL"
    )
    try check(
        directConfiguration.deviceKey == "secret-device-key",
        "Direct Device Key was not preserved"
    )

    let copiedURLConfiguration = try BarkConfiguration(
        baseURLString: "https://bark.example/base",
        deviceKeyInput: "https://api.day.app/copied-device-key/这里改成你自己的推送内容"
    )
    try check(
        copiedURLConfiguration.baseURL.absoluteString == "https://api.day.app",
        "Copied Bark URL did not select the public service"
    )
    try check(
        copiedURLConfiguration.deviceKey == "copied-device-key",
        "Copied Bark URL did not extract the Device Key"
    )

    do {
        _ = try BarkConfiguration(
            baseURLString: "https://api.day.app",
            deviceKeyInput: "https://example.com/not-a-bark-key"
        )
        throw TestFailure(description: "Unrecognized full URL was accepted as a Device Key")
    } catch BarkError.invalidDeviceKey {
        // Expected.
    }

    do {
        _ = try BarkClient(baseURL: URL(string: "http://example.com")!, deviceKey: "key")
        throw TestFailure(description: "HTTP Bark URL was accepted")
    } catch BarkError.invalidBaseURL {
        // Expected.
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    let session = URLSession(configuration: configuration)
    URLProtocolStub.handler = { request in
        try check(request.url?.absoluteString == "https://bark.example/base/push", "Wrong Bark endpoint")
        try check(!(request.url?.absoluteString.contains("secret-device-key") ?? true), "Key leaked into URL")
        let body = try bodyData(from: request)
        guard
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            throw TestFailure(description: "Missing Bark JSON body")
        }
        try check(json["device_key"] as? String == "secret-device-key", "Device key missing from JSON")
        try check(
            json["icon"] as? String == CoPingBrand.barkIconURL.absoluteString,
            "CoPing icon missing from Bark JSON"
        )
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data(#"{"code":200}"#.utf8)
        )
    }
    defer { URLProtocolStub.handler = nil }

    let client = try BarkClient(
        baseURL: URL(string: "https://bark.example/base")!,
        deviceKey: "secret-device-key",
        session: session
    )
    try await client.send(PushNotification(title: "Title", body: "Body"))

    URLProtocolStub.handler = { request in
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data()
        )
    }
    do {
        try await client.send(PushNotification(title: "Title", body: "Body"))
        throw TestFailure(description: "Bark HTTP failure was accepted")
    } catch BarkError.rejected(503) {
        // Expected.
    }
}

private func testLanguageResolution() throws {
    for language in ["zh", "zh-Hans", "zh-CN", "zh-Hant", "zh-TW", "zh-HK", "zh_MO"] {
        try check(
            AppLanguage.resolve(preferredLanguages: [language]) == .simplifiedChinese,
            "\(language) did not resolve to Simplified Chinese"
        )
    }

    for language in ["en", "en-US", "ja-JP", "fr-FR", "de-DE"] {
        try check(
            AppLanguage.resolve(preferredLanguages: [language]) == .english,
            "\(language) did not resolve to English"
        )
    }

    try check(
        AppLanguage.resolve(preferredLanguages: []) == .english,
        "An empty language list did not fall back to English"
    )

    try check(
        AppText.terminalInstalled(language: .simplifiedChinese) == "CoPing 已安装监听器。",
        "Terminal guidance did not use Simplified Chinese"
    )
    try check(
        AppText.terminalInstalled(language: .english) == "CoPing installed its event listeners.",
        "Terminal guidance did not use English"
    )

    let localizedHTTPFailure = AppText.localizedHistoryDetail("Bark 请求失败（HTTP 400）。")
    try check(
        localizedHTTPFailure == AppText.barkHTTPFailure(400),
        "Stored Bark HTTP failures did not follow the current language"
    )
}

private func bodyData(from request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else {
        throw TestFailure(description: "Missing Bark JSON body")
    }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? StubError.missingHandler }
        if count == 0 { break }
        result.append(contentsOf: buffer.prefix(count))
    }
    return result
}

private func castRoot(_ data: Data) throws -> [String: Any] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw TestFailure(description: "Expected JSON object")
    }
    return root
}

private func castHooks(_ root: [String: Any]) throws -> [String: Any] {
    guard let hooks = root["hooks"] as? [String: Any] else {
        throw TestFailure(description: "Expected hooks object")
    }
    return hooks
}

private enum StubError: Error {
    case missingHandler
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw StubError.missingHandler }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@main
private struct CoPingSelfTests {
    static func main() async {
        do {
            try testPayloadSanitizer()
            try testHookConfiguration()
            try testSocketRoundTrip()
            try testKeychainAndHistory()
            try testLanguageResolution()
            try await testBarkClient()
            print("CoPingSelfTests: PASS")
        } catch {
            fputs("CoPingSelfTests: FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
