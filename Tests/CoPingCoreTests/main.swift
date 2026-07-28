import CoPingCore
import CoPingAppSupport
import Foundation
import SQLite3

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
    try check(event.verifiesConnection, "A supported Stop event did not verify the connection")
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
    try check(
        CodexEvent.EventType.allCases.allSatisfy {
            CodexEvent(
                type: $0,
                sessionID: "connection-test",
                turnID: nil,
                projectName: "CoPing"
            ).verifiesConnection
        },
        "A supported Codex event did not verify the connection"
    )
    try check(
        !CodexEvent(
            version: 2,
            type: .sessionStarted,
            sessionID: "unsupported-version",
            turnID: nil,
            projectName: "CoPing"
        ).verifiesConnection,
        "An unsupported event version verified the connection"
    )

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

private func testCodexNotificationPreferences() throws {
    let defaultPreferences = CodexNotificationPreferences()
    try check(
        defaultPreferences.allows(.permissionRequested),
        "Permission notifications were ignored by default"
    )

    let ignoringPermissions = CodexNotificationPreferences(
        ignorePermissionNotifications: true
    )
    try check(
        !ignoringPermissions.allows(.permissionRequested),
        "Permission notifications were not ignored"
    )
    try check(
        ignoringPermissions.allows(.completed),
        "Completion notifications were affected"
    )
    try check(
        ignoringPermissions.allows(.questionRequested),
        "Question notifications were affected"
    )
    try check(
        ignoringPermissions.allows(.sessionStarted),
        "Connection events were affected"
    )
}

private func testCodexConnectionStatus() throws {
    for eventType in CodexEvent.EventType.allCases {
        var status = CodexConnectionStatus.awaitingVerification
        let event = CodexEvent(
            type: eventType,
            sessionID: "connection-test",
            turnID: "turn",
            projectName: "CoPing"
        )
        try check(
            status.verify(with: event),
            "\(eventType.rawValue) did not verify an awaiting connection"
        )
        try check(
            status == .connected,
            "\(eventType.rawValue) did not move the connection to connected"
        )
    }

    let validEvent = CodexEvent(
        type: .completed,
        sessionID: "connection-test",
        turnID: "turn",
        projectName: "CoPing"
    )
    for initialStatus in [
        CodexConnectionStatus.disconnected,
        .connected,
        .error,
    ] {
        var status = initialStatus
        try check(
            !status.verify(with: validEvent),
            "\(initialStatus) accepted a connection event"
        )
        try check(status == initialStatus, "\(initialStatus) changed unexpectedly")
    }

    var awaiting = CodexConnectionStatus.awaitingVerification
    let unsupportedEvent = CodexEvent(
        version: 2,
        type: .completed,
        sessionID: "unsupported-version",
        turnID: "turn",
        projectName: "CoPing"
    )
    try check(
        !awaiting.verify(with: unsupportedEvent),
        "An unsupported event version verified the connection"
    )
    try check(
        awaiting == .awaitingVerification,
        "An unsupported event version changed the connection state"
    )
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

private func testDeviceKeyAndHistory() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoPingStorage-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let configurationURL = directory.appendingPathComponent("config.json")
    let deviceKeyStore = DeviceKeyStore(fileURL: configurationURL)
    let initialKey = try deviceKeyStore.read()
    try check(initialKey == nil, "Fresh Device Key file was not empty")
    try deviceKeyStore.save("test-secret")
    let savedKey = try deviceKeyStore.read()
    try check(savedKey == "test-secret", "Device Key round trip failed")

    let attributes = try FileManager.default.attributesOfItem(atPath: configurationURL.path)
    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
    try check(permissions == 0o600, "Device Key file permissions were not 0600")

    try deviceKeyStore.delete()
    let deletedKey = try deviceKeyStore.read()
    try check(deletedKey == nil, "Device Key file was not deleted")

    let malformedConfiguration = Data("{broken".utf8)
    try malformedConfiguration.write(to: configurationURL, options: [.atomic])
    var malformedConfigurationRejected = false
    do {
        _ = try deviceKeyStore.read()
    } catch {
        malformedConfigurationRejected = true
    }
    try check(
        malformedConfigurationRejected,
        "Malformed Device Key configuration was treated as an empty configuration"
    )
    let retainedMalformedConfiguration = try Data(contentsOf: configurationURL)
    try check(
        retainedMalformedConfiguration == malformedConfiguration,
        "Reading a malformed Device Key configuration modified the original file"
    )

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

    let legacyRecord = DeliveryRecord(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 10),
        eventType: .completed,
        projectName: "legacy",
        outcome: .sent,
        detail: nil
    )
    let legacyObject = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(legacyRecord)
    ) as! [String: Any]
    var oldShape = legacyObject
    oldShape.removeValue(forKey: "attempts")
    let decodedLegacy = try JSONDecoder().decode(
        DeliveryRecord.self,
        from: JSONSerialization.data(withJSONObject: oldShape)
    )
    try check(
        decodedLegacy.effectiveAttempts
            == [DeliveryRecord.Attempt(channel: .bark, outcome: .sent)],
        "Legacy history was not interpreted as a Bark delivery"
    )

    let aggregate = DeliveryRecord(
        eventType: .questionRequested,
        projectName: "aggregate",
        attempts: [
            DeliveryRecord.Attempt(channel: .bark, outcome: .sent),
            DeliveryRecord.Attempt(
                channel: .ntfy,
                outcome: .failed,
                detail: "failed"
            ),
        ]
    )
    try check(
        aggregate.outcome == .failed,
        "A partial delivery changed the persisted compatibility outcome"
    )
    try check(
        aggregate.aggregateStatus == .partial,
        "A mixed channel result was not represented as partial"
    )
    try check(aggregate.effectiveAttempts.count == 2, "An event lost a channel result")
    let aggregateJSON = try String(
        decoding: JSONEncoder().encode(aggregate),
        as: UTF8.self
    )
    try check(
        !aggregateJSON.contains("partial"),
        "The computed partial status changed the persisted history contract"
    )

    try store.clear()
    try check(store.load().isEmpty, "History was not cleared")
}

private func testNtfyConfigurationStore() throws {
    try check(
        NtfyConfiguration.serverURL.absoluteString == "https://ntfy.sh",
        "NTFY did not use the fixed official HTTPS service"
    )
    let validTopic = "coping-abcdefghijklmnopqrstuvwxyz"
    let valid = try NtfyConfiguration(topicInput: validTopic)
    try check(valid.topic == validTopic, "A valid generated NTFY topic changed")

    for invalid in [
        "",
        "user-chosen-topic",
        "coping-valid_topic-123",
        "coping-abcdefghijklmnopqrstuvwxy1",
        " \(validTopic)",
        "\(validTopic)\n",
        String(repeating: "a", count: 65),
    ] {
        do {
            _ = try NtfyConfiguration(topicInput: invalid)
            throw TestFailure(description: "An invalid NTFY topic was accepted")
        } catch NtfyConfigurationError.invalidTopic {
            // Expected.
        }
    }

    let generated = NtfyTopicGenerator.generate()
    let secondGenerated = NtfyTopicGenerator.generate()
    try check(
        generated.range(
            of: #"^coping-[a-z2-7]{26}$"#,
            options: .regularExpression
        ) != nil,
        "Generated NTFY topic did not meet the random topic contract"
    )
    try check(generated != secondGenerated, "Two generated NTFY topics were identical")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoPingNtfy-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("ntfy.json")
    let store = NtfyConfigurationStore(fileURL: fileURL)
    let freshConfiguration = try store.read()
    try check(freshConfiguration == nil, "Fresh NTFY configuration was not empty")
    try store.save(valid)
    let savedConfiguration = try store.read()
    try check(savedConfiguration == valid, "NTFY configuration round trip failed")

    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    let directoryPermissions =
        (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue
    try check(directoryPermissions == 0o700, "NTFY directory permissions were not 0700")
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let filePermissions = (fileAttributes[.posixPermissions] as? NSNumber)?.intValue
    try check(filePermissions == 0o600, "NTFY configuration permissions were not 0600")

    let storedJSON = try String(decoding: Data(contentsOf: fileURL), as: UTF8.self)
    try check(!storedJSON.contains("ntfy.sh"), "NTFY service address was stored as a secret")

    let invalidStoredTopic = Data(#"{"topic":"contains/slash"}"#.utf8)
    try invalidStoredTopic.write(to: fileURL, options: [.atomic])
    do {
        _ = try store.read()
        throw TestFailure(description: "An invalid stored NTFY topic bypassed validation")
    } catch NtfyConfigurationError.invalidTopic {
        // Expected.
    }
    let retainedInvalidStoredTopic = try Data(contentsOf: fileURL)
    try check(
        retainedInvalidStoredTopic == invalidStoredTopic,
        "Reading an invalid stored NTFY topic modified the original file"
    )

    let malformed = Data("{broken".utf8)
    try malformed.write(to: fileURL, options: [.atomic])
    do {
        _ = try store.read()
        throw TestFailure(description: "Malformed NTFY configuration was accepted")
    } catch DecodingError.dataCorrupted {
        // Expected.
    } catch DecodingError.keyNotFound {
        // Expected.
    }
    let retainedMalformedConfiguration = try Data(contentsOf: fileURL)
    try check(
        retainedMalformedConfiguration == malformed,
        "Reading malformed NTFY configuration modified the original file"
    )
}

private func testNtfySettingsCoordinator() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "CoPingNtfySettings-\(UUID().uuidString)",
            isDirectory: true
        )
    let suiteName = "CoPingNtfySettingsTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw TestFailure(description: "Unable to create isolated UserDefaults")
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    let fileURL = directory.appendingPathComponent("ntfy.json")
    let store = NtfyConfigurationStore(fileURL: fileURL)

    defaults.set(true, forKey: NtfySettingsCoordinator.enabledDefaultsKey)
    var missing = NtfySettingsCoordinator(
        configurationStore: store,
        defaults: defaults
    )
    try check(!missing.isEnabled, "A missing topic retained an enabled NTFY switch")
    try check(
        defaults.bool(forKey: NtfySettingsCoordinator.enabledDefaultsKey) == false,
        "A missing topic did not persist the fail-closed switch state"
    )
    try check(
        !missing.configurationReadFailed,
        "A missing topic was reported as a corrupt configuration"
    )
    try check(
        !missing.hasCurrentConfiguration,
        "A generated draft was treated as a saved configuration"
    )
    do {
        try missing.setEnabled(true)
        throw TestFailure(description: "An unsaved generated topic was enabled")
    } catch NtfySettingsError.topicNotSaved {
        // Expected.
    }

    try missing.save()
    try missing.setEnabled(true)
    let savedTopic = missing.topic
    try check(missing.isEnabled, "A saved generated topic could not be enabled")

    var restarted = NtfySettingsCoordinator(
        configurationStore: store,
        defaults: defaults
    )
    try check(
        restarted.topic == savedTopic && restarted.isEnabled,
        "A saved and enabled topic did not survive restart"
    )

    restarted.regenerateTopic()
    try check(restarted.topic != savedTopic, "Topic regeneration retained the old topic")
    try check(!restarted.isEnabled, "Topic regeneration left NTFY enabled")
    try check(
        !restarted.hasCurrentConfiguration,
        "An unsaved regenerated topic was treated as active"
    )
    let retainedSavedTopic = try store.read()?.topic
    try check(
        retainedSavedTopic == savedTopic,
        "Topic regeneration overwrote the saved topic before explicit save"
    )
    do {
        try restarted.setEnabled(true)
        throw TestFailure(description: "A regenerated draft was enabled before save")
    } catch NtfySettingsError.topicNotSaved {
        // Expected.
    }

    try restarted.save()
    try restarted.setEnabled(true)
    let rotatedTopic = restarted.topic
    let rotatedRestart = NtfySettingsCoordinator(
        configurationStore: store,
        defaults: defaults
    )
    try check(
        rotatedRestart.topic == rotatedTopic && rotatedRestart.isEnabled,
        "A saved rotated topic did not survive restart"
    )

    let malformed = Data("{broken".utf8)
    try malformed.write(to: fileURL, options: [.atomic])
    defaults.set(true, forKey: NtfySettingsCoordinator.enabledDefaultsKey)
    let corrupted = NtfySettingsCoordinator(
        configurationStore: store,
        defaults: defaults
    )
    try check(
        corrupted.configurationReadFailed,
        "A corrupt topic file was not reported"
    )
    try check(!corrupted.isEnabled, "A corrupt topic file retained enabled NTFY")
    try check(
        defaults.bool(forKey: NtfySettingsCoordinator.enabledDefaultsKey) == false,
        "A corrupt topic file did not persist the fail-closed switch state"
    )
    let retainedMalformed = try Data(contentsOf: fileURL)
    try check(
        retainedMalformed == malformed,
        "Fail-closed startup modified the corrupt configuration"
    )
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
    do {
        _ = try BarkClient(
            baseURL: URL(string: "https://api.day.app/device-key")!,
            deviceKey: "key"
        )
        throw TestFailure(description: "A public Bark URL containing a path was accepted")
    } catch BarkError.invalidPublicBaseURL {
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
        try check(
            json["icon"] as? String
                == "https://raw.githubusercontent.com/massif-01/CoPing/main/assets/icon/CoPing-bark-avatar-v2.png",
            "Bark icon URL was not cache-busted"
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

    URLProtocolStub.handler = { request in
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data(
                #"{"code":400,"message":"failed to get device token: failed to get [secret-device-key] device token from database"}"#.utf8
            )
        )
    }
    do {
        try await client.send(PushNotification(title: "Title", body: "Body"))
        throw TestFailure(description: "An unregistered Bark key was accepted")
    } catch BarkError.deviceKeyNotRegistered {
        try check(
            !(BarkError.deviceKeyNotRegistered.localizedDescription.contains("secret-device-key")),
            "The Bark Device Key leaked through the localized error"
        )
    }
}

private func testNtfyClient() async throws {
    let topic = "coping-abcdefghijklmnopqrstuvwxyz"
    let ntfyConfiguration = try NtfyConfiguration(topicInput: topic)
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [URLProtocolStub.self]
    sessionConfiguration.timeoutIntervalForRequest = 10
    sessionConfiguration.timeoutIntervalForResource = 10
    let session = URLSession(configuration: sessionConfiguration)
    defer { session.invalidateAndCancel() }
    let client = NtfyClient(
        configuration: ntfyConfiguration,
        session: session
    )
    let notification = PushNotification(
        title: "Title",
        body: "private notification body",
        urgency: .high,
        sequenceID: "stable-sequence"
    )
    URLProtocolStub.handler = { request in
        try check(
            request.url?.absoluteString == "https://ntfy.sh",
            "NTFY requested a non-official endpoint"
        )
        try check(
            !(request.url?.absoluteString.contains(topic) ?? true),
            "NTFY topic leaked into the request URL"
        )
        try check(
            !(request.url?.absoluteString.contains("private") ?? true),
            "NTFY notification body leaked into the request URL"
        )
        try check(request.httpMethod == "POST", "NTFY did not publish with POST")
        try check(
            request.value(forHTTPHeaderField: "Content-Type")
                == "application/json; charset=utf-8",
            "NTFY omitted its JSON content type"
        )
        try check(
            request.value(forHTTPHeaderField: "Authorization") == nil,
            "NTFY unexpectedly sent an authorization token"
        )
        let body = try bodyData(from: request)
        guard
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            throw TestFailure(description: "Missing NTFY JSON body")
        }
        try check(json["topic"] as? String == topic, "NTFY topic missing from JSON")
        try check(
            json["message"] as? String == "private notification body",
            "NTFY message missing from JSON"
        )
        try check(json["priority"] as? Int == 4, "NTFY high priority was not 4")
        try check(
            json["sequence_id"] as? String == "stable-sequence",
            "NTFY sequence ID was not stable"
        )
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data(#"{"id":"message-id","topic":"coping-abcdefghijklmnopqrstuvwxyz"}"#.utf8)
        )
    }
    defer { URLProtocolStub.handler = nil }
    try await client.send(notification)

    URLProtocolStub.handler = { request in
        let body = try bodyData(from: request)
        guard
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            throw TestFailure(description: "Missing normal-priority NTFY JSON body")
        }
        try check(json["priority"] as? Int == 3, "NTFY normal priority was not 3")
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data(#"{"id":"normal-id","topic":"coping-abcdefghijklmnopqrstuvwxyz"}"#.utf8)
        )
    }
    let secondClient = NtfyClient(
        configuration: ntfyConfiguration,
        session: session
    )
    try await secondClient.send(
        PushNotification(
            title: "Normal",
            body: "Normal body",
            urgency: .normal,
            sequenceID: "normal-sequence"
        )
    )

    let redirectDelegate = NtfyRedirectRejectingDelegate()
    let redirectTask = session.dataTask(
        with: URL(string: "https://ntfy.sh")!
    )
    let redirectResponse = HTTPURLResponse(
        url: URL(string: "https://ntfy.sh")!,
        statusCode: 302,
        httpVersion: nil,
        headerFields: ["Location": "https://example.com/capture"]
    )!
    var redirectWasFollowed = true
    redirectDelegate.urlSession(
        session,
        task: redirectTask,
        willPerformHTTPRedirection: redirectResponse,
        newRequest: URLRequest(
            url: URL(string: "https://example.com/capture")!
        )
    ) { request in
        redirectWasFollowed = request != nil
    }
    redirectTask.cancel()
    try check(
        !redirectWasFollowed,
        "The NTFY URLSession redirect delegate followed a redirect"
    )

    URLProtocolStub.handler = { request in
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": "https://example.com/capture"]
            )!,
            Data()
        )
    }
    do {
        try await client.send(notification)
        throw TestFailure(description: "An NTFY redirect was accepted")
    } catch NtfyError.redirected {
        // Expected.
    }

    URLProtocolStub.handler = { request in
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data("private notification body \(topic)".utf8)
        )
    }
    do {
        try await client.send(notification)
        throw TestFailure(description: "An unauthorized NTFY response was accepted")
    } catch NtfyError.rejected(401) {
        try check(
            !NtfyError.rejected(401).localizedDescription.contains(topic),
            "NTFY topic leaked through an error"
        )
        try check(
            !NtfyError.rejected(401).localizedDescription.contains("private notification body"),
            "NTFY notification body leaked through an error"
        )
    }

    URLProtocolStub.handler = { request in
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "5"]
            )!,
            Data()
        )
    }
    do {
        try await client.send(notification)
        throw TestFailure(description: "An NTFY rate limit was accepted")
    } catch NtfyError.rateLimited(5) {
        // Expected.
    }

    try check(NtfyError.rejected(408).isRetryable, "NTFY HTTP 408 was not retryable")
    try check(NtfyError.rejected(503).isRetryable, "NTFY HTTP 503 was not retryable")
    try check(!NtfyError.rejected(401).isRetryable, "NTFY HTTP 401 was retryable")
    try check(NtfyError.rateLimited(nil).isRetryable, "NTFY 429 without a delay was not retryable")
    try check(NtfyError.rateLimited(10).isRetryable, "A reasonable NTFY 429 delay was rejected")
    try check(!NtfyError.rateLimited(11).isRetryable, "A long NTFY 429 delay was retried")
    try check(!NtfyError.rateLimited(-1).isRetryable, "A negative NTFY 429 delay was retried")
    try check(BarkError.rejected(429).isRetryable, "Bark HTTP 429 was not retryable")
    try check(BarkError.serverRejected(503).isRetryable, "Bark service 503 was not retryable")
    try check(!BarkError.rejected(401).isRetryable, "Bark HTTP 401 was retryable")
    try check(!BarkError.serverRejected(400).isRetryable, "Bark service 400 was retryable")
}

private struct TemporaryPushFailure: PushRetryClassifyingError {
    let isRetryable = true
    let suggestedRetryDelay: Duration? = .zero
}

private struct PermanentPushFailure: Error {}

private enum ScriptedPushResult: Sendable {
    case success
    case temporaryFailure
    case permanentFailure
}

private actor ScriptedPushProvider: PushProvider {
    private var results: [ScriptedPushResult]
    private(set) var sendCount = 0

    init(_ results: [ScriptedPushResult]) {
        self.results = results
    }

    func send(_ notification: PushNotification) async throws {
        sendCount += 1
        let result = results.isEmpty ? .success : results.removeFirst()
        switch result {
        case .success:
            return
        case .temporaryFailure:
            throw TemporaryPushFailure()
        case .permanentFailure:
            throw PermanentPushFailure()
        }
    }
}

private actor ConcurrencyTracker {
    private var active = 0
    private(set) var maximum = 0

    func begin() {
        active += 1
        maximum = max(maximum, active)
    }

    func end() {
        active -= 1
    }
}

private struct DelayedPushProvider: PushProvider {
    let tracker: ConcurrencyTracker

    func send(_ notification: PushNotification) async throws {
        await tracker.begin()
        try await Task.sleep(for: .milliseconds(40))
        await tracker.end()
    }
}

private actor AsyncSignal {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isSignaled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !isSignaled else { return }
        isSignaled = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private actor CancellablePushProvider: PushProvider {
    let started: AsyncSignal
    private(set) var sendCount = 0

    init(started: AsyncSignal) {
        self.started = started
    }

    func send(_ notification: PushNotification) async throws {
        sendCount += 1
        await started.signal()
        do {
            try await Task.sleep(for: .seconds(60))
        } catch is CancellationError {
            // Deliberately ignore provider cancellation. The dispatcher must
            // still propagate its own cancelled state.
        }
    }
}

private func testPushDeliveryDispatcher() async throws {
    let dispatcher = PushDeliveryDispatcher(retryDelays: [.zero, .zero])
    let notification = PushNotification(
        title: "Title",
        body: "Body",
        sequenceID: "dispatcher-test"
    )

    let retrying = ScriptedPushProvider([.temporaryFailure, .success])
    let permanent = ScriptedPushProvider([.permanentFailure, .success])
    let attempts = try await dispatcher.deliver(
        notification,
        to: [
            PushDeliveryTarget(channel: .bark, provider: retrying),
            PushDeliveryTarget(channel: .ntfy, provider: permanent),
        ]
    )
    let retryingSendCount = await retrying.sendCount
    let permanentSendCount = await permanent.sendCount
    try check(retryingSendCount == 2, "A temporary failure was not retried")
    try check(permanentSendCount == 1, "A permanent failure was retried")
    try check(
        attempts
            == [
                DeliveryRecord.Attempt(channel: .bark, outcome: .sent),
                DeliveryRecord.Attempt(
                    channel: .ntfy,
                    outcome: .failed,
                    detail: AppText.networkRequestFailed
                ),
            ],
        "Partial channel results were not preserved"
    )

    let tracker = ConcurrencyTracker()
    let concurrentAttempts = try await dispatcher.deliver(
        notification,
        to: [
            PushDeliveryTarget(
                channel: .bark,
                provider: DelayedPushProvider(tracker: tracker)
            ),
            PushDeliveryTarget(
                channel: .ntfy,
                provider: DelayedPushProvider(tracker: tracker)
            ),
        ]
    )
    let maximumConcurrency = await tracker.maximum
    try check(maximumConcurrency == 2, "Bark and NTFY were not sent concurrently")
    try check(
        concurrentAttempts.allSatisfy { $0.outcome == .sent },
        "Concurrent delivery did not preserve successful outcomes"
    )

    let allFailed = try await dispatcher.deliver(
        notification,
        to: [
            PushDeliveryTarget(
                channel: .bark,
                provider: ScriptedPushProvider([.permanentFailure])
            ),
            PushDeliveryTarget(
                channel: .ntfy,
                provider: ScriptedPushProvider([.permanentFailure])
            ),
        ]
    )
    try check(
        allFailed.allSatisfy { $0.outcome == .failed },
        "An all-channel failure was not preserved"
    )

    try check(
        PushDeliveryRouting.eventChannels(
            notificationsEnabled: false,
            barkEnabled: true,
            ntfyEnabled: true
        ).isEmpty,
        "Global pause still routed formal notifications"
    )

    let isolatedBark = ScriptedPushProvider([.success])
    let isolatedNtfy = ScriptedPushProvider([.success])
    let ntfyTestAttempts = try await dispatcher.deliver(
        notification,
        to: [
            PushDeliveryTarget(channel: .ntfy, provider: isolatedNtfy),
        ]
    )
    let barkCountAfterNtfyTest = await isolatedBark.sendCount
    let ntfyCountAfterNtfyTest = await isolatedNtfy.sendCount
    try check(
        barkCountAfterNtfyTest == 0
            && ntfyCountAfterNtfyTest == 1
            && ntfyTestAttempts.map(\.channel) == [.ntfy],
        "An NTFY test reached Bark or missed NTFY"
    )

    let barkTestAttempts = try await dispatcher.deliver(
        notification,
        to: [
            PushDeliveryTarget(channel: .bark, provider: isolatedBark),
        ]
    )
    let barkCountAfterBarkTest = await isolatedBark.sendCount
    let ntfyCountAfterBarkTest = await isolatedNtfy.sendCount
    try check(
        barkCountAfterBarkTest == 1
            && ntfyCountAfterBarkTest == 1
            && barkTestAttempts.map(\.channel) == [.bark],
        "A Bark test reached NTFY or missed Bark"
    )
    try check(
        PushDeliveryRouting.eventChannels(
            notificationsEnabled: true,
            barkEnabled: true,
            ntfyEnabled: true
        ) == [.bark, .ntfy],
        "Formal delivery did not route to both enabled channels"
    )

    let cancellationStarted = AsyncSignal()
    let cancellableProvider = CancellablePushProvider(
        started: cancellationStarted
    )
    let cancellationTask = Task {
        try await dispatcher.deliver(
            notification,
            to: [
                PushDeliveryTarget(
                    channel: .ntfy,
                    provider: cancellableProvider
                ),
            ]
        )
    }
    await cancellationStarted.wait()
    cancellationTask.cancel()
    do {
        _ = try await cancellationTask.value
        throw TestFailure(description: "A cancelled delivery returned an outcome")
    } catch is CancellationError {
        // Expected.
    }
    let cancelledSendCount = await cancellableProvider.sendCount
    try check(
        cancelledSendCount == 1,
        "A cancelled delivery retried or skipped its in-flight provider"
    )
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
        AppLanguagePreference.system.resolve(preferredLanguages: ["zh-Hant"]) == .simplifiedChinese,
        "System preference did not map Traditional Chinese to Simplified Chinese"
    )
    try check(
        AppLanguagePreference.system.resolve(preferredLanguages: ["ja-JP"]) == .english,
        "System preference did not map a non-Chinese language to English"
    )
    try check(
        AppLanguagePreference.simplifiedChinese.resolve(preferredLanguages: ["en-US"])
            == .simplifiedChinese,
        "Manual Simplified Chinese did not override the system language"
    )
    try check(
        AppLanguagePreference.english.resolve(preferredLanguages: ["zh-CN"]) == .english,
        "Manual English did not override the system language"
    )
    try check(
        AppText.completedNotificationBody(language: .simplifiedChinese)
            == "Codex 任务完成",
        "Chinese completion body should identify the Codex event"
    )
    try check(
        AppText.completedNotificationBody(
            taskTitle: "让推送显示对话名称",
            language: .simplifiedChinese
        ) == "Codex [让推送显示对话名...] 任务完成",
        "Chinese completion body did not include the task title"
    )
    try check(
        AppText.completedNotificationBody(language: .english)
            == "Codex task completed",
        "English completion body should identify the Codex event"
    )
    try check(
        AppText.permissionNotificationBody(language: .simplifiedChinese)
            == "Codex 需要审批",
        "Chinese approval body should identify the required action"
    )
    try check(
        AppText.permissionNotificationBody(
            taskTitle: "让推送显示对话名称",
            language: .simplifiedChinese
        ) == "Codex [让推送显示对话名...] 需要审批",
        "Chinese approval body did not include the task title"
    )
    try check(
        AppText.permissionNotificationBody(language: .english)
            == "Codex needs approval",
        "English approval body should identify the required action"
    )
    try check(
        AppText.questionNotificationBody(language: .simplifiedChinese)
            == "Codex 等待回答",
        "Chinese question body should identify the required action"
    )
    try check(
        AppText.questionNotificationBody(
            taskTitle: "让推送显示对话名称",
            language: .simplifiedChinese
        ) == "Codex [让推送显示对话名...] 等待回答",
        "Chinese question body did not include the task title"
    )
    try check(
        AppText.completedNotificationBody(
            taskTitle: "这是一个超过十个字的中文任务名称",
            language: .simplifiedChinese
        ) == "Codex [这是一个超过十个...] 任务完成",
        "A long Chinese task title was not limited to eight characters"
    )
    try check(
        AppText.permissionNotificationBody(
            taskTitle: "1234567890ABCDEF",
            language: .english
        ) == "Codex [1234567890ABCDEF] needs approval",
        "An English task title at the limit was truncated"
    )
    try check(
        AppText.questionNotificationBody(
            taskTitle: "1234567890ABCDEFG",
            language: .english
        ) == "Codex [1234567890ABCDEF...] is waiting for an answer",
        "A long English task title was not limited to sixteen characters"
    )
    try check(
        AppText.questionNotificationBody(
            taskTitle: "中文ABCD混合任务名",
            language: .simplifiedChinese
        ) == "Codex [中文ABCD混合任务...] 等待回答",
        "A mixed-language task title did not use its displayed width"
    )
    try check(
        AppText.completedNotificationBody(
            taskTitle: "first line\nsecond line",
            language: .english
        ) == "Codex [first line secon...] task completed",
        "A multiline task title was not normalized to one line before truncation"
    )
    try check(
        AppText.questionNotificationBody(language: .english)
            == "Codex is waiting for an answer",
        "English question body should identify the required action"
    )

    try check(
        AppText.terminalInstalled
            == "CoPing 已安装监听器。\nCoPing hooks are installed.",
        "Terminal setup text was not bilingual"
    )
    try check(
        AppText.terminalHooksInstruction.contains("全部信任并继续")
            && AppText.terminalHooksInstruction.contains("Trust all and continue"),
        "Terminal hook review instructions were not bilingual"
    )
    try check(
        AppText.terminalQuitInstruction.contains("新建一个对话")
            && AppText.terminalQuitInstruction.contains("create a new conversation"),
        "Terminal verification instructions were not bilingual"
    )
    try check(
        AppText.terminalReviewFinished.contains("审核已结束")
            && AppText.terminalReviewFinished.contains("review has finished"),
        "Terminal completion text was not bilingual"
    )

    let localizedHTTPFailure = AppText.localizedHistoryDetail("Bark 请求失败（HTTP 400）。")
    try check(
        localizedHTTPFailure == AppText.barkHTTPFailure(400),
        "Stored Bark HTTP failures did not follow the current language"
    )
}

private func testSemanticVersionAndChecksum() throws {
    let current = try unwrap(
        SemanticVersion(rawValue: "0.1.9"),
        "A valid installed version was rejected"
    )
    let latest = try unwrap(
        SemanticVersion(rawValue: "v0.1.10"),
        "A valid release tag was rejected"
    )
    try check(latest > current, "Semantic versions were compared as strings")
    try check(
        SemanticVersion(rawValue: "0.1") == nil,
        "A two-component version was accepted"
    )
    try check(
        SemanticVersion(rawValue: "v0.1.0-beta") == nil,
        "A prerelease version was accepted"
    )

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoPingRelease-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let archiveURL = directory.appendingPathComponent(AppRelease.archiveName)
    try Data("abc".utf8).write(to: archiveURL)

    let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    let actualHash = try ReleaseArchiveVerifier.sha256(of: archiveURL)
    try check(
        actualHash == expected,
        "The release archive SHA-256 was incorrect"
    )
    let checksum = Data("\(expected)  \(AppRelease.archiveName)\n".utf8)
    let parsedHash = try ReleaseArchiveVerifier.expectedSHA256(
        from: checksum,
        archiveName: AppRelease.archiveName
    )
    try check(
        parsedHash == expected,
        "The release checksum file was not parsed"
    )

    do {
        _ = try ReleaseArchiveVerifier.expectedSHA256(
            from: Data("\(expected)  other.zip\n".utf8),
            archiveName: AppRelease.archiveName
        )
        throw TestFailure(description: "A checksum for another asset was accepted")
    } catch ReleaseDownloadError.invalidChecksumFile {
        // Expected.
    }
}

private func testGitHubReleaseClient() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    let session = URLSession(configuration: configuration)
    defer { URLProtocolStub.handler = nil }

    URLProtocolStub.handler = { request in
        try check(
            request.url?.absoluteString
                == "https://api.github.com/repos/massif-01/CoPing/releases/latest",
            "The release client requested the wrong repository"
        )
        try check(
            request.value(forHTTPHeaderField: "User-Agent") == "CoPing",
            "The release client omitted its User-Agent"
        )
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let data = Data(
            """
            {
              "tag_name":"v0.1.10",
              "published_at":"2026-07-27T12:00:00Z",
              "html_url":"https://github.com/massif-01/CoPing/releases/tag/v0.1.10",
              "draft":false,
              "prerelease":false,
              "assets":[
                {
                  "name":"\(AppRelease.archiveName)",
                  "browser_download_url":"https://github.com/massif-01/CoPing/releases/download/v0.1.10/\(AppRelease.archiveName)",
                  "size":1024
                },
                {
                  "name":"\(AppRelease.checksumName)",
                  "browser_download_url":"https://github.com/massif-01/CoPing/releases/download/v0.1.10/\(AppRelease.checksumName)",
                  "size":96
                }
              ]
            }
            """.utf8
        )
        return (response, data)
    }

    let release = try await GitHubReleaseClient(session: session).latestRelease()
    try check(
        release.version == SemanticVersion(rawValue: "0.1.10"),
        "The latest release version was decoded incorrectly"
    )
    try check(
        release.archive.name == AppRelease.archiveName,
        "The release archive contract changed"
    )

    URLProtocolStub.handler = { request in
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data(
                """
                {
                  "tag_name":"v0.1.10",
                  "published_at":"2026-07-27T12:00:00Z",
                  "html_url":"https://github.com/massif-01/CoPing/releases/tag/v0.1.10",
                  "draft":false,
                  "prerelease":false,
                  "assets":[]
                }
                """.utf8
            )
        )
    }
    do {
        _ = try await GitHubReleaseClient(session: session).latestRelease()
        throw TestFailure(description: "A release missing its archive was accepted")
    } catch GitHubReleaseError.missingAsset(AppRelease.archiveName) {
        // Expected.
    }

    URLProtocolStub.handler = { request in
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data(
                """
                {
                  "tag_name":"v0.1.10",
                  "published_at":"2026-07-27T12:00:00Z",
                  "html_url":"https://github.com/massif-01/CoPing/releases/tag/v0.1.10",
                  "draft":false,
                  "prerelease":false,
                  "assets":[
                    {
                      "name":"\(AppRelease.archiveName)",
                      "browser_download_url":"http://example.com/\(AppRelease.archiveName)",
                      "size":1024
                    },
                    {
                      "name":"\(AppRelease.checksumName)",
                      "browser_download_url":"https://example.com/\(AppRelease.checksumName)",
                      "size":96
                    }
                  ]
                }
                """.utf8
            )
        )
    }
    do {
        _ = try await GitHubReleaseClient(session: session).latestRelease()
        throw TestFailure(description: "An insecure release asset URL was accepted")
    } catch GitHubReleaseError.insecureAssetURL {
        // Expected.
    }

    URLProtocolStub.handler = { request in
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data()
        )
    }
    do {
        _ = try await GitHubReleaseClient(session: session).latestRelease()
        throw TestFailure(description: "A missing GitHub Release was accepted")
    } catch GitHubReleaseError.noPublishedRelease {
        // Expected.
    }
}

private func testReleaseDownloader() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoPingDownload-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let sourceURL = directory.appendingPathComponent("source.zip")
    let archiveData = Data("verified archive".utf8)
    try archiveData.write(to: sourceURL)
    let hash = try ReleaseArchiveVerifier.sha256(of: sourceURL)
    let checksumData = Data("\(hash)  \(AppRelease.archiveName)\n".utf8)

    let archiveURL = URL(string: "https://github.com/example/\(AppRelease.archiveName)")!
    let checksumURL = URL(string: "https://github.com/example/\(AppRelease.checksumName)")!
    let release = AppRelease(
        version: try unwrap(
            SemanticVersion(rawValue: "0.1.1"),
            "The downloader test version was invalid"
        ),
        tagName: "v0.1.1",
        publishedAt: Date(timeIntervalSince1970: 0),
        pageURL: URL(string: "https://github.com/example/release")!,
        archive: ReleaseAsset(
            name: AppRelease.archiveName,
            downloadURL: archiveURL,
            size: Int64(archiveData.count)
        ),
        checksum: ReleaseAsset(
            name: AppRelease.checksumName,
            downloadURL: checksumURL,
            size: Int64(checksumData.count)
        )
    )

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    let session = URLSession(configuration: configuration)
    URLProtocolStub.handler = { request in
        let data = request.url == checksumURL ? checksumData : archiveData
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!,
            data
        )
    }
    defer { URLProtocolStub.handler = nil }

    let destinationURL = directory.appendingPathComponent(AppRelease.archiveName)
    try await ReleaseDownloader(session: session).download(release, to: destinationURL)
    let savedData = try Data(contentsOf: destinationURL)
    try check(
        savedData == archiveData,
        "The verified release archive was not saved"
    )

    URLProtocolStub.handler = { request in
        let data = request.url == checksumURL
            ? Data("\(String(repeating: "0", count: 64))  \(AppRelease.archiveName)\n".utf8)
            : archiveData
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!,
            data
        )
    }
    let rejectedURL = directory.appendingPathComponent("rejected.zip")
    do {
        try await ReleaseDownloader(session: session).download(release, to: rejectedURL)
        throw TestFailure(description: "A release with the wrong checksum was saved")
    } catch ReleaseDownloadError.checksumMismatch {
        try check(
            !FileManager.default.fileExists(atPath: rejectedURL.path),
            "A failed download left an unverified destination file"
        )
    }
}

private func testCodexTaskTitleResolver() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoPingTitleResolver-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let databaseURL = directory.appendingPathComponent("state_5.sqlite")
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
        throw TestFailure(description: "Could not create the task title test database")
    }
    defer { sqlite3_close(database) }

    guard
        sqlite3_exec(
            database,
            "CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT NOT NULL)",
            nil,
            nil,
            nil
        ) == SQLITE_OK,
        sqlite3_exec(
            database,
            "INSERT INTO threads (id, title) VALUES ('session-1', '让推送显示对话名称')",
            nil,
            nil,
            nil
        ) == SQLITE_OK
    else {
        throw TestFailure(description: "Could not populate the task title test database")
    }

    let resolver = CodexTaskTitleResolver(codexDirectory: directory)
    try check(
        resolver.title(for: "session-1") == "让推送显示对话名称",
        "The task title was not resolved by session ID"
    )
    try check(
        resolver.title(for: "missing") == nil,
        "A missing session unexpectedly resolved a task title"
    )
}

@MainActor
private func testNoticeLifecycle() async throws {
    let presenter = NoticePresenter(autoDismissDelay: .milliseconds(20))

    presenter.show("success", kind: .success)
    try await Task.sleep(for: .milliseconds(80))
    try check(presenter.current == nil, "Transient notice did not expire")

    let persistentError = presenter.show("error", kind: .error)
    try await Task.sleep(for: .milliseconds(80))
    try check(
        presenter.current == persistentError,
        "Error notice expired without explicit dismissal"
    )
    presenter.dismiss(id: persistentError.id)

    let superseded = presenter.show("old", kind: .information)
    let replacement = presenter.show("new error", kind: .error)
    try await Task.sleep(for: .milliseconds(80))
    try check(
        presenter.current == replacement,
        "A superseded notice task dismissed the replacement"
    )

    presenter.dismiss(id: superseded.id)
    try check(
        presenter.current == replacement,
        "A stale notice ID dismissed the current notice"
    )

    presenter.dismiss(id: replacement.id)
    try check(presenter.current == nil, "Explicit notice dismissal failed")
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

private func unwrap<Value>(_ value: Value?, _ message: String) throws -> Value {
    guard let value else { throw TestFailure(description: message) }
    return value
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
            try testCodexNotificationPreferences()
            try testCodexConnectionStatus()
            try testCodexTaskTitleResolver()
            try testHookConfiguration()
            try testSocketRoundTrip()
            try testDeviceKeyAndHistory()
            try testNtfyConfigurationStore()
            try testNtfySettingsCoordinator()
            try testSemanticVersionAndChecksum()
            try testLanguageResolution()
            try await testNoticeLifecycle()
            try await testGitHubReleaseClient()
            try await testReleaseDownloader()
            try await testBarkClient()
            try await testNtfyClient()
            try await testPushDeliveryDispatcher()
            print("CoPingSelfTests: PASS")
        } catch {
            fputs("CoPingSelfTests: FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
