import Foundation

public enum HookConfigurationError: LocalizedError {
    case malformedJSON
    case unexpectedShape
    case helperMissing
    case concurrentModification

    public var errorDescription: String? {
        switch self {
        case .malformedJSON:
            return AppText.malformedHooksJSON
        case .unexpectedShape:
            return AppText.unexpectedHooksShape
        case .helperMissing:
            return AppText.helperNotInstalled
        case .concurrentModification:
            return AppText.hookConfigurationConflict
        }
    }
}

public struct HookConfigurationManager {
    public let hooksURL: URL
    public let helperURL: URL
    public let sourceID: String?
    public let verifiedToolLifecycle: Bool
    private let beforeCommit: () throws -> Void
    private let fileManager: FileManager

    public init(
        hooksURL: URL = CoPingPaths.hooksFile(),
        helperURL: URL = CoPingPaths.installedHelper(),
        fileManager: FileManager = .default,
        sourceID: String? = nil,
        verifiedToolLifecycle: Bool = false,
        beforeCommit: @escaping () throws -> Void = {}
    ) {
        self.hooksURL = hooksURL
        self.helperURL = helperURL
        self.fileManager = fileManager
        self.sourceID = sourceID
        self.verifiedToolLifecycle = verifiedToolLifecycle
        self.beforeCommit = beforeCommit
    }

    public var command: String {
        let prefix = sourceID.map { "COPING_SOURCE_ID=" + shellQuote($0) + " " } ?? ""
        return prefix + shellQuote(helperURL.path)
    }

    private var ownedCommands: Set<String> {
        // Exact previous 0.1.6 spelling at this installation path, never substring matching.
        let legacy = "\"" + helperURL.path.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        return [command, shellQuote(helperURL.path), legacy]
    }

    public func hasLegacyInstallation() -> Bool {
        guard fileManager.fileExists(atPath: helperURL.path),
            let root = try? readRoot(), let hooks = root["hooks"] as? [String: Any] else { return false }
        return ["SessionStart", "Stop", "PermissionRequest", "PreToolUse"].allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains {
                    ownedCommands.contains($0["command"] as? String ?? "")
                }
            }
        }
    }

    public func isInstalled() -> Bool {
        guard
            fileManager.fileExists(atPath: helperURL.path),
            let root = try? readRoot(),
            let hooks = root["hooks"] as? [String: Any]
        else {
            return false
        }
        return requiredEvents.allSatisfy { event, matcher in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                guard group["matcher"] as? String == matcher,
                    let handlers = group["hooks"] as? [[String: Any]] else { return false }
                return handlers.contains {
                    $0["command"] as? String == command && $0["type"] as? String == "command"
                        && ($0["timeout"] as? Int) == 1
                }
            }
        }
    }

    @discardableResult
    public func installConfiguration() throws -> URL? {
        guard fileManager.fileExists(atPath: helperURL.path) else {
            throw HookConfigurationError.helperMissing
        }
        let existed = fileManager.fileExists(atPath: hooksURL.path)
        let existingData = existed ? try Data(contentsOf: hooksURL) : nil
        var root = try readRoot(data: existingData)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        // Strip only our exact handlers, including previously enabled lifecycle events.
        for event in ["SessionStart", "Stop", "PermissionRequest", "PreToolUse", "PostToolUse"] {
            if let groups = hooks[event] as? [[String: Any]] {
                let retained = groups.compactMap(removingOwnHandler)
                if retained.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = retained }
            }
        }
        for (event, matcher) in requiredEvents {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups = groups.compactMap(removingOwnHandler)
            groups.append(makeGroup(matcher: matcher, event: event))
            hooks[event] = groups
        }
        root["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        guard data != existingData else { return nil }

        try fileManager.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try commit(data, replacing: existingData)
    }

    public func uninstallConfiguration() throws {
        guard fileManager.fileExists(atPath: hooksURL.path) else { return }
        let original = try Data(contentsOf: hooksURL)
        var root = try readRoot(data: original)
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for event in ["SessionStart", "Stop", "PermissionRequest", "PreToolUse", "PostToolUse"] {
            let groups = (hooks[event] as? [[String: Any]] ?? []).compactMap(removingOwnHandler)
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }
        root["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        if data != original { _ = try commit(data, replacing: original) }
    }

    private func commit(_ data: Data, replacing original: Data?) throws -> URL? {
        _ = try readRoot(data: data)
        try beforeCommit()
        var coordinationError: NSError?
        var result: Result<URL?, Error>!
        NSFileCoordinator().coordinate(writingItemAt: hooksURL, options: .forReplacing,
                                       error: &coordinationError) { url in
            result = Result {
                let current = fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
                guard current == original else { throw HookConfigurationError.concurrentModification }
                let backup = original != nil ? try makeBackup() : nil
                // Detect edits during backup as well. Atomic rename prevents partial JSON.
                let checked = fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
                guard checked == original else { throw HookConfigurationError.concurrentModification }
                try data.write(to: url, options: .atomic)
                return backup
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private var requiredEvents: [(String, String?)] {
        let events: [(String, String?)] = [
            ("SessionStart", nil),
            ("Stop", nil),
            ("PermissionRequest", "*"),
            ("PreToolUse", verifiedToolLifecycle ? "^(request_user_input|request_user_input_async)$" : "^request_user_input$"),
            // Even the synchronous compatibility path needs an end-of-wait signal.
            ("PostToolUse", verifiedToolLifecycle ? "^(request_user_input|request_user_input_async)$" : "^request_user_input$"),
        ]
        return events
    }

    private func readRoot(data supplied: Data? = nil) throws -> [String: Any] {
        guard supplied != nil || fileManager.fileExists(atPath: hooksURL.path) else { return [:] }
        let data = try supplied ?? Data(contentsOf: hooksURL)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HookConfigurationError.malformedJSON
        }
        guard let root = object as? [String: Any] else {
            throw HookConfigurationError.unexpectedShape
        }
        if let hooks = root["hooks"], !(hooks is [String: Any]) {
            throw HookConfigurationError.unexpectedShape
        }
        if let hooks = root["hooks"] as? [String: Any] {
            for value in hooks.values {
                guard let groups = value as? [[String: Any]],
                    groups.allSatisfy({ $0["hooks"] is [[String: Any]] }) else {
                    throw HookConfigurationError.unexpectedShape
                }
            }
        }
        return root
    }

    private func makeBackup() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let backup = hooksURL
            .deletingLastPathComponent()
            .appendingPathComponent("hooks.json.coping-backup-\(formatter.string(from: Date()))-\(UUID().uuidString)")
        try fileManager.copyItem(at: hooksURL, to: backup)
        return backup
    }

    private func makeGroup(matcher: String?, event: String) -> [String: Any] {
        var group: [String: Any] = [
            "hooks": [[
                "type": "command",
                "command": command,
                "timeout": 1,
                "statusMessage": AppText.hookStatus(event: event),
            ]],
        ]
        if let matcher { group["matcher"] = matcher }
        return group
    }

    private func removingOwnHandler(_ group: [String: Any]) -> [String: Any]? {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
        let retained = handlers.filter { !ownedCommands.contains($0["command"] as? String ?? "") }
        guard !retained.isEmpty else { return nil }
        var updated = group
        updated["hooks"] = retained
        return updated
    }
}
