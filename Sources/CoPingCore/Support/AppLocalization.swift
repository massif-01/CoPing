import Foundation

public enum AppLanguagePreference: String, CaseIterable, Equatable, Sendable {
    case system
    case simplifiedChinese
    case english

    public static let defaultsKey = "appLanguagePreference"

    public static var current: AppLanguagePreference {
        guard
            let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
            let preference = AppLanguagePreference(rawValue: rawValue)
        else {
            return .system
        }
        return preference
    }

    public func resolve(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        switch self {
        case .system:
            return AppLanguage.resolve(preferredLanguages: preferredLanguages)
        case .simplifiedChinese:
            return .simplifiedChinese
        case .english:
            return .english
        }
    }
}

public enum AppLanguage: Equatable, Sendable {
    case simplifiedChinese
    case english

    public static var current: AppLanguage {
        AppLanguagePreference.current.resolve()
    }

    public static func resolve(preferredLanguages: [String]) -> AppLanguage {
        guard let preferred = preferredLanguages.first else { return .english }
        let normalized = preferred
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return normalized == "zh" || normalized.hasPrefix("zh-")
            ? .simplifiedChinese
            : .english
    }

    public func text(chinese: String, english: String) -> String {
        self == .simplifiedChinese ? chinese : english
    }
}

public enum AppText {
    private static func text(_ chinese: String, _ english: String) -> String {
        AppLanguage.current.text(chinese: chinese, english: english)
    }

    // MARK: - Shared errors

    public static func keychainOperationFailed(_ status: Int32) -> String {
        text("钥匙串操作失败（\(status)）。", "Keychain operation failed (\(status)).")
    }

    public static var malformedHooksJSON: String {
        text(
            "现有 hooks.json 不是有效 JSON，CoPing 没有修改它。",
            "The existing hooks.json is invalid. CoPing did not modify it."
        )
    }

    public static var unexpectedHooksShape: String {
        text(
            "现有 hooks.json 结构无法识别，CoPing 没有修改它。",
            "The existing hooks.json structure is not recognized. CoPing did not modify it."
        )
    }

    public static var helperNotInstalled: String {
        text("CoPingHook helper 尚未安装。", "The CoPingHook helper is not installed.")
    }

    public static var invalidBarkBaseURL: String {
        text(
            "Bark 服务地址必须是有效的 HTTPS 地址。",
            "The Bark server address must be a valid HTTPS URL."
        )
    }

    public static var invalidBarkDeviceKey: String {
        text(
            "请输入 Device Key，或粘贴 Bark 提供的完整推送地址。",
            "Enter a Device Key or paste the full push URL provided by Bark."
        )
    }

    public static var invalidBarkResponse: String {
        text("Bark 返回了无法识别的响应。", "Bark returned an unrecognized response.")
    }

    public static func barkHTTPFailure(_ status: Int) -> String {
        text("Bark 请求失败（HTTP \(status)）。", "Bark request failed (HTTP \(status)).")
    }

    public static func barkServerRejected(_ code: Int) -> String {
        text("Bark 服务拒绝了请求（代码 \(code)）。", "Bark rejected the request (code \(code)).")
    }

    // MARK: - App and services

    public static var settingsWindowTitle: String { text("CoPing 设置", "CoPing Settings") }
    public static var bundledHelperMissing: String {
        text("CoPing.app 中缺少 CoPingHook helper。", "CoPing.app is missing the CoPingHook helper.")
    }
    public static var helperSignatureInvalid: String {
        text(
            "CoPingHook 签名校验失败，未安装任何文件。",
            "CoPingHook signature verification failed. No files were installed."
        )
    }
    public static var codexNotFound: String {
        text(
            "未在 /Applications/ChatGPT.app 中找到 Codex。",
            "Codex was not found in /Applications/ChatGPT.app."
        )
    }
    public static var terminalLaunchFailed: String {
        text("无法打开 Hook 审核终端。", "Unable to open the Hook review terminal.")
    }

    public static func terminalInstalled(
        language: AppLanguage = .current
    ) -> String {
        language.text(
            chinese: "CoPing 已安装监听器。",
            english: "CoPing installed its event listeners."
        )
    }
    public static func terminalHooksInstruction(
        language: AppLanguage = .current
    ) -> String {
        language.text(
            chinese: "进入 Codex 后请输入 /hooks，然后检查 CoPingHook 路径并选择信任全部。",
            english: "In Codex, enter /hooks, verify the CoPingHook path, and trust all CoPing hooks."
        )
    }
    public static func terminalQuitInstruction(
        language: AppLanguage = .current
    ) -> String {
        language.text(
            chinese: "完成后输入 /quit 退出此窗口。",
            english: "When finished, enter /quit to exit this window."
        )
    }
    public static func terminalReviewFinished(
        language: AppLanguage = .current
    ) -> String {
        language.text(
            chinese: "审核窗口已结束，现在可以关闭终端。",
            english: "Hook review has finished. You can now close Terminal."
        )
    }

    // MARK: - Connection and menu

    public static var disconnected: String { text("未连接", "Not connected") }
    public static var awaitingVerification: String {
        text("等待新任务验证", "Waiting for a new task")
    }
    public static var connected: String { text("已连接", "Connected") }
    public static var configurationError: String {
        text("配置异常", "Configuration error")
    }
    public static var eventListenerStartFailed: String {
        text("事件监听器启动失败。", "Failed to start the event listener.")
    }
    public static var notificationsPaused: String {
        text("通知已暂停", "Notifications paused")
    }
    public static var recentPushFailed: String {
        text("最近推送失败", "Recent push failed")
    }
    public static var pauseNotifications: String {
        text("暂停通知", "Pause notifications")
    }
    public static var resumeNotifications: String {
        text("恢复通知", "Resume notifications")
    }
    public static var sendTestNotification: String {
        text("发送测试通知", "Send test notification")
    }
    public static var settings: String { text("设置…", "Settings…") }
    public static var quitCoPing: String { text("退出 CoPing", "Quit CoPing") }
    public static var dismiss: String { text("关闭", "Dismiss") }
    public static var menuSubtitle: String {
        text("Codex 推送助手", "Codex push companion")
    }
    public static var connectionSection: String { text("连接", "Connection") }

    // MARK: - Settings

    public static var generalTab: String { text("通用", "General") }
    public static var historyTab: String { text("记录", "History") }
    public static var settingsSidebarAccessibilityLabel: String {
        text("设置分类", "Settings sections")
    }
    public static var appVersionLabel: String { text("版本", "Version") }
    public static var currentVersionLabel: String {
        text("当前版本", "Current version")
    }
    public static var languageSection: String { text("语言", "Language") }
    public static var languagePickerLabel: String {
        text("显示语言", "Display language")
    }
    public static var followSystemLanguage: String {
        text("跟随系统", "Follow System")
    }
    public static var simplifiedChineseLanguage: String { "简体中文" }
    public static var englishLanguage: String { "English" }
    public static var languagePreferenceHelp: String {
        text(
            "默认跟随系统；所有中文系统均使用简体中文。",
            "The default follows the system. All Chinese system languages use Simplified Chinese."
        )
    }
    public static var notificationsSection: String { text("通知", "Notifications") }
    public static var enableNotifications: String {
        text("启用 CoPing 通知", "Enable CoPing notifications")
    }
    public static var notificationsDisabledHelp: String {
        text(
            "关闭后仍会接收 Codex 事件，但不会发送到 Bark。",
            "CoPing will still receive Codex events, but will not send them to Bark."
        )
    }
    public static var startupSection: String { text("启动", "Startup") }
    public static var launchAtLogin: String {
        text("登录 Mac 时自动启动", "Launch automatically when you log in")
    }
    public static var versionScopeSection: String {
        text("版本范围", "Version scope")
    }
    public static var supportedEventsLabel: String {
        text("支持事件", "Supported events")
    }
    public static var supportedEventsValue: String {
        text(
            "完成、权限请求、普通问题",
            "Completion, permission requests, questions"
        )
    }
    public static var executionFailureLabel: String {
        text("执行失败", "Execution failures")
    }
    public static func notSupportedInVersion(_ version: String) -> String {
        text(
            "\(version) 暂不支持",
            "Not supported in \(version)"
        )
    }
    public static var serviceSection: String { text("服务", "Service") }
    public static var httpsServerAddress: String {
        text("HTTPS 服务地址", "HTTPS server address")
    }
    public static var barkServerHelp: String {
        text(
            "默认 https://api.day.app；自建服务也必须使用 HTTPS。",
            "The default is https://api.day.app. Self-hosted servers must also use HTTPS."
        )
    }
    public static var deviceSection: String { text("设备", "Device") }
    public static var deviceKeyOrURL: String {
        text("Device Key 或完整 Bark 地址", "Device Key or full Bark URL")
    }
    public static var deviceKeyHelp: String {
        text(
            "可直接粘贴 Bark 复制的完整推送地址；CoPing 会自动提取 Device Key 并保存到 macOS 钥匙串。",
            "Paste the full push URL copied from Bark. CoPing extracts the Device Key and stores it in macOS Keychain."
        )
    }
    public static var save: String { text("保存", "Save") }
    public static var saveAndSendTest: String {
        text("保存并发送测试通知", "Save and send test notification")
    }
    public static var detectionSection: String { text("检测", "Detection") }
    public static var detected: String { text("已检测到", "Detected") }
    public static var notDetected: String { text("未检测到", "Not detected") }
    public static var connectionStatusLabel: String {
        text("连接状态", "Connection status")
    }
    public static var firstConnectionSection: String {
        text("首次连接", "First connection")
    }
    public static var firstConnectionHelp: String {
        text(
            "CoPing 会安装用户级 Hook，然后打开一次终端。请在 Codex 中输入 /hooks，检查 CoPingHook 路径并选择信任全部。",
            "CoPing installs user-level Hooks and opens Terminal once. In Codex, enter /hooks, verify the CoPingHook path, and trust all CoPing hooks."
        )
    }
    public static var firstConnectionVerificationHelp: String {
        text(
            "完成后退出终端并新建一个 Codex 桌面任务；收到 SessionStart 后会自动显示“已连接”。",
            "Exit Terminal and create a new Codex desktop task. CoPing will show “Connected” after receiving SessionStart."
        )
    }
    public static var connectCodex: String { text("连接 Codex", "Connect Codex") }
    public static var repairConnection: String {
        text("修复连接", "Repair connection")
    }
    public static var reopenReviewTerminal: String {
        text("重新打开审核终端", "Reopen review terminal")
    }
    public static var disconnect: String { text("断开连接", "Disconnect") }
    public static var noNotificationHistory: String {
        text("暂无通知记录", "No notification history")
    }
    public static var historyPrivacyHelp: String {
        text(
            "这里只记录事件类型、项目名和发送结果。",
            "Only the event type, project name, and delivery result are recorded."
        )
    }
    public static var historyLimit: String {
        text("最多保留最近 100 条", "Up to 100 recent records are kept")
    }
    public static var clearHistory: String { text("清空记录", "Clear history") }
    public static var connectionEvent: String { text("连接", "Connection") }
    public static var completionEvent: String { text("完成", "Completion") }
    public static var permissionEvent: String { text("权限请求", "Permission request") }
    public static var questionEvent: String { text("普通问题", "Question") }

    // MARK: - Runtime status

    public static var barkSettingsSaved: String {
        text("Bark 配置已保存。", "Bark settings saved.")
    }
    public static var chatGPTNotDetected: String {
        text(
            "未检测到 /Applications/ChatGPT.app。",
            "/Applications/ChatGPT.app was not detected."
        )
    }
    public static var trustHooksStatus: String {
        text(
            "请在终端输入 /hooks，信任 CoPing 后退出。新建 Codex 任务即可完成验证。",
            "In Terminal, enter /hooks, trust CoPing, and exit. Create a new Codex task to complete verification."
        )
    }
    public static var reviewFinishedStatus: String {
        text(
            "完成终端审核后，新建一个 Codex 任务进行验证。",
            "After reviewing the Hooks in Terminal, create a new Codex task to verify the connection."
        )
    }
    public static var disconnectedStatus: String {
        text(
            "已断开，仅移除了 CoPing 自己的 Hook。",
            "Disconnected. Only CoPing Hooks were removed."
        )
    }
    public static func loginItemFailure(_ detail: String) -> String {
        text("登录启动设置失败：\(detail)", "Failed to update launch at login: \(detail)")
    }
    public static var clearHistoryFailed: String {
        text("无法清空记录。", "Unable to clear history.")
    }
    public static var codexConnectionVerified: String {
        text("Codex 桌面事件连接已验证。", "Codex desktop event connection verified.")
    }
    public static var barkNotConfigured: String {
        text("Bark 未配置", "Bark is not configured")
    }
    public static var notificationSent: String {
        text("通知已发送。", "Notification sent.")
    }
    public static func pushFailed(_ detail: String) -> String {
        text("推送失败：\(detail)", "Push failed: \(detail)")
    }
    public static var networkRequestFailed: String {
        text("网络请求失败", "Network request failed")
    }

    public static func localizedHistoryDetail(_ stored: String) -> String {
        let exactMappings: [([String], String)] = [
            (["通知已暂停", "Notifications paused"], notificationsPaused),
            (["Bark 未配置", "Bark is not configured"], barkNotConfigured),
            (["网络请求失败", "Network request failed"], networkRequestFailed),
            ([
                "Bark 服务地址必须是有效的 HTTPS 地址。",
                "The Bark server address must be a valid HTTPS URL.",
            ], invalidBarkBaseURL),
            ([
                "请输入 Device Key，或粘贴 Bark 提供的完整推送地址。",
                "Enter a Device Key or paste the full push URL provided by Bark.",
            ], invalidBarkDeviceKey),
            ([
                "Bark 返回了无法识别的响应。",
                "Bark returned an unrecognized response.",
            ], invalidBarkResponse),
        ]
        for (variants, localized) in exactMappings where variants.contains(stored) {
            return localized
        }

        let number = stored
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .first
        if stored.hasPrefix("Bark"), stored.contains("HTTP"), let number {
            return barkHTTPFailure(number)
        }
        if
            stored.hasPrefix("Bark"),
            stored.contains("拒绝") || stored.lowercased().contains("rejected"),
            let number
        {
            return barkServerRejected(number)
        }
        return stored
    }

    // MARK: - Push notifications

    public static var testNotificationTitle: String {
        text("CoPing · 测试通知", "CoPing · Test notification")
    }
    public static var testNotificationBody: String {
        text("CoPing 已成功连接 Bark", "CoPing connected to Bark successfully")
    }
    public static var completedNotificationTitle: String {
        text("CoPing · Codex 任务完成", "CoPing · Codex task completed")
    }
    public static func completedNotificationBody(project: String) -> String {
        text(
            "\(project) — Codex 已完成任务",
            "\(project) — Codex completed the task"
        )
    }
    public static var permissionNotificationTitle: String {
        text("CoPing · Codex 请求权限", "CoPing · Codex requests permission")
    }
    public static func permissionNotificationBody(project: String) -> String {
        text(
            "\(project) — Codex 请求了权限，请查看电脑",
            "\(project) — Codex requested permission. Check your Mac."
        )
    }
    public static var questionNotificationTitle: String {
        text("CoPing · Codex 提出问题", "CoPing · Codex asked a question")
    }
    public static func questionNotificationBody(project: String) -> String {
        text(
            "\(project) — Codex 提出了问题，请查看电脑",
            "\(project) — Codex asked a question. Check your Mac."
        )
    }

    public static func hookStatus(event: String) -> String {
        let label: String
        switch event {
        case "SessionStart":
            label = text("连接", "Connection")
        case "Stop":
            label = text("任务完成", "Task completed")
        case "PermissionRequest":
            label = text("权限请求", "Permission request")
        case "PreToolUse":
            label = text("普通问题", "Question")
        default:
            label = event
        }
        return "CoPing: \(label)"
    }
}
