import Foundation

public enum HookConfigurationError: LocalizedError {
    case malformedJSON
    case unexpectedShape
    case helperMissing

    public var errorDescription: String? {
        switch self {
        case .malformedJSON:
            return AppText.malformedHooksJSON
        case .unexpectedShape:
            return AppText.unexpectedHooksShape
        case .helperMissing:
            return AppText.helperNotInstalled
        }
    }
}

public struct HookConfigurationManager {
    public let hooksURL: URL
    public let helperURL: URL
    private let fileManager: FileManager

    public init(
        hooksURL: URL = CoPingPaths.hooksFile(),
        helperURL: URL = CoPingPaths.installedHelper(),
        fileManager: FileManager = .default
    ) {
        self.hooksURL = hooksURL
        self.helperURL = helperURL
        self.fileManager = fileManager
    }

    public var command: String {
        "\"\(helperURL.path.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    public func isInstalled() -> Bool {
        guard
            fileManager.fileExists(atPath: helperURL.path),
            let root = try? readRoot(),
            let hooks = root["hooks"] as? [String: Any]
        else {
            return false
        }
        return requiredEvents.allSatisfy { event, _ in
            containsCoPingHandler(in: hooks[event] as? [Any] ?? [])
        }
    }

    @discardableResult
    public func installConfiguration() throws -> URL? {
        guard fileManager.fileExists(atPath: helperURL.path) else {
            throw HookConfigurationError.helperMissing
        }
        let existed = fileManager.fileExists(atPath: hooksURL.path)
        var root = try readRoot()
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for (event, matcher) in requiredEvents {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups = groups.compactMap(removingOwnHandler)
            groups.append(makeGroup(matcher: matcher, event: event))
            hooks[event] = groups
        }
        root["hooks"] = hooks

        try fileManager.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let backup = existed ? try makeBackup() : nil
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: hooksURL, options: [.atomic])
        return backup
    }

    public func uninstallConfiguration() throws {
        guard fileManager.fileExists(atPath: hooksURL.path) else { return }
        var root = try readRoot()
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for (event, _) in requiredEvents {
            let groups = (hooks[event] as? [[String: Any]] ?? []).compactMap(removingOwnHandler)
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }
        root["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: hooksURL, options: [.atomic])
    }

    private var requiredEvents: [(String, String?)] {
        [
            ("SessionStart", nil),
            ("Stop", nil),
            ("PermissionRequest", "*"),
            ("PreToolUse", "^request_user_input$"),
        ]
    }

    private func readRoot() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: hooksURL.path) else { return [:] }
        let data = try Data(contentsOf: hooksURL)
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
        return root
    }

    private func makeBackup() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let backup = hooksURL
            .deletingLastPathComponent()
            .appendingPathComponent("hooks.json.coping-backup-\(formatter.string(from: Date()))")
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

    private func containsCoPingHandler(in groups: [Any]) -> Bool {
        groups.contains { value in
            guard
                let group = value as? [String: Any],
                let handlers = group["hooks"] as? [[String: Any]]
            else {
                return false
            }
            return handlers.contains { $0["command"] as? String == command }
        }
    }

    private func removingOwnHandler(_ group: [String: Any]) -> [String: Any]? {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
        let retained = handlers.filter { $0["command"] as? String != command }
        guard !retained.isEmpty else { return nil }
        var updated = group
        updated["hooks"] = retained
        return updated
    }
}
