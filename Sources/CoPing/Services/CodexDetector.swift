import CoPingCore
import Foundation

enum CodexDetector {
    static func initialSource() -> CodexConnectionSource {
        var source = CodexConnectionSource.initial()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = ["/Applications/ChatGPT.app", "/Applications/Codex.app",
                          home.appendingPathComponent("Applications/ChatGPT.app").path,
                          home.appendingPathComponent("Applications/Codex.app").path]
        for path in candidates {
            source.appPath = path
            if isInstalled(source: source) { return source }
        }
        return .initial()
    }
    static func isInstalled(source: CodexConnectionSource) -> Bool {
        guard let bundle = Bundle(url: source.appURL),
            let identifier = bundle.bundleIdentifier,
            ["com.openai.chat", "com.openai.codex"].contains(identifier) else { return false }
        return FileManager.default.isExecutableFile(atPath: source.executableURL.path)
    }
}
