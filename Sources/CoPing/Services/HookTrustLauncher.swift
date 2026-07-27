import CoPingCore
import AppKit
import Foundation

enum HookTrustLauncherError: LocalizedError {
    case codexNotFound
    case terminalLaunchFailed

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return AppText.codexNotFound
        case .terminalLaunchFailed:
            return AppText.terminalLaunchFailed
        }
    }
}

struct HookTrustLauncher {
    func openReviewTerminal() throws {
        guard CodexDetector.isInstalled else {
            throw HookTrustLauncherError.codexNotFound
        }

        let support = CoPingPaths.applicationSupport()
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let scriptURL = support.appendingPathComponent("review-hooks.command")
        let codex = shellQuote(CodexDetector.executableURL.path)
        let script = """
        #!/bin/zsh
        clear
        echo \(shellQuote(AppText.terminalInstalled()))
        echo \(shellQuote(AppText.terminalHooksInstruction()))
        echo \(shellQuote(AppText.terminalQuitInstruction()))
        echo
        COPING_SETUP=1 \(codex) -C "$HOME"
        echo
        echo \(shellQuote(AppText.terminalReviewFinished()))
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: scriptURL.path
        )
        guard NSWorkspace.shared.open(scriptURL) else {
            throw HookTrustLauncherError.terminalLaunchFailed
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
