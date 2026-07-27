import CoPingCore
import AppKit
import Foundation

enum HookTrustLauncherError: LocalizedError {
    case codexNotFound
    case terminalLaunchFailed

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "未在 /Applications/ChatGPT.app 中找到 Codex。"
        case .terminalLaunchFailed:
            return "无法打开 Hook 审核终端。"
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
        echo 'CoPing 已安装监听器。'
        echo '进入 Codex 后请输入 /hooks，然后检查 CoPingHook 路径并选择信任全部。'
        echo '完成后输入 /quit 退出此窗口。'
        echo
        COPING_SETUP=1 \(codex) -C "$HOME"
        echo
        echo '审核窗口已结束，现在可以关闭终端。'
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
