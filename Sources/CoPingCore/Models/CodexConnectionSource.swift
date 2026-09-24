import Foundation

/// One active source. Selection does not install hooks or alter trust.
public struct CodexConnectionSource: Codable, Equatable {
    public var appPath: String
    public var codexHomePath: String
    public var homeOrigin: String
    public var id: String
    /// Opt in only after checking the target's lifecycle hook contract.
    public var verifiedToolLifecycle: Bool

    public init(appPath: String, codexHomePath: String, homeOrigin: String,
                id: String = UUID().uuidString, verifiedToolLifecycle: Bool = false) {
        self.appPath = appPath
        self.codexHomePath = codexHomePath
        self.homeOrigin = homeOrigin
        self.id = id
        self.verifiedToolLifecycle = verifiedToolLifecycle
    }
    public var appURL: URL { URL(fileURLWithPath: appPath, isDirectory: true) }
    public var homeURL: URL { URL(fileURLWithPath: codexHomePath, isDirectory: true) }
    public var executableURL: URL { appURL.appendingPathComponent("Contents/Resources/codex") }
    public var hooksURL: URL { homeURL.appendingPathComponent("hooks.json") }
    public var ipcPath: String { homeURL.appendingPathComponent("ipc/ipc.sock").path }

    public static func initial(environment: [String: String] = ProcessInfo.processInfo.environment,
                               home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
        let explicit = environment["CODEX_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        return Self(appPath: "/Applications/ChatGPT.app",
                    codexHomePath: explicit ?? home.appendingPathComponent(".codex").path,
                    homeOrigin: explicit == nil ? "default" : "process environment")
    }
}

public func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}
