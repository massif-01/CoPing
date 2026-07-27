import Foundation

enum CodexDetector {
    static let appURL = URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true)
    static let executableURL = appURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("codex", isDirectory: false)

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: executableURL.path)
    }
}
