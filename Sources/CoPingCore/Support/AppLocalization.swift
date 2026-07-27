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

    public static var invalidPublicBarkBaseURL: String {
        text(
            "公共 Bark 服务地址只能填写 https://api.day.app；完整推送地址请粘贴到 Device Key 一栏。",
            "The public Bark server address must be https://api.day.app. Paste the full push URL into the Device Key field."
        )
    }

    public static var invalidBarkDeviceKey: String {
        text(
            "请输入 Device Key，或粘贴 Bark 提供的完整推送地址。",
            "Enter a Device Key or paste the full push URL provided by Bark."
        )
    }

    public static var barkConfigurationReadFailed: String {
        text(
            "无法读取本地 Bark 配置，原文件未被修改。请检查配置文件后重试。",
            "Unable to read the local Bark configuration. The original file was not modified. Check the configuration file and try again."
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

    public static var barkDeviceKeyNotRegistered: String {
        text(
            "当前 Device Key 未在这个 Bark 服务上注册。请从 Bark App 重新复制完整推送地址。",
            "The current Device Key is not registered with this Bark server. Copy the full push URL from the Bark app again."
        )
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

    public static var terminalInstalled: String {
        """
        CoPing 已安装监听器。
        CoPing hooks are installed.
        """
    }
    public static var terminalHooksInstruction: String {
        """
        在 Codex 中输入 /hooks，确认 CoPingHook 路径，然后选择“全部信任并继续”。
        In Codex, enter /hooks, verify the CoPingHook path, then choose “Trust all and continue”.
        """
    }
    public static var terminalQuitInstruction: String {
        """
        完成后输入 /quit 并按回车。
        When finished, enter /quit and press Return.

        回到 Codex 桌面版，新建一个对话进行验证；不要使用安装前已经打开的旧对话。
        Return to Codex Desktop and create a new conversation to verify the connection. Do not use a conversation opened before installation.
        """
    }
    public static var terminalReviewFinished: String {
        """
        Hook 审核已结束，现在可以关闭终端。
        Hook review has finished. You can now close Terminal.
        """
    }

    // MARK: - Connection and menu

    public static var disconnected: String { text("未连接", "Not connected") }
    public static var awaitingVerification: String {
        text("等待新对话验证", "Waiting for a new conversation")
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
    public static var versionTab: String { text("版本", "Version") }
    public static var generalSettingsDescription: String {
        text(
            "设置 CoPing 的显示语言、通知和启动行为。",
            "Choose CoPing's language, notification, and startup behavior."
        )
    }
    public static var barkSettingsDescription: String {
        text(
            "配置 CoPing 如何通过 Bark 向你的 iPhone 发送通知。",
            "Configure how CoPing sends notifications to your iPhone through Bark."
        )
    }
    public static var codexSettingsDescription: String {
        text(
            "连接本机 Codex，并管理 Hook 的安装与信任状态。",
            "Connect local Codex and manage Hook installation and trust."
        )
    }
    public static var historySettingsDescription: String {
        text(
            "查看最近的通知发送结果；不保存提示词或回复正文。",
            "Review recent delivery results. Prompts and responses are never stored."
        )
    }
    public static var versionSettingsDescription: String {
        text(
            "查看当前版本，并从 GitHub Releases 检查和下载更新。",
            "View the current version and check GitHub Releases for updates."
        )
    }
    public static var settingsSidebarAccessibilityLabel: String {
        text("设置分类", "Settings sections")
    }
    public static var appVersionLabel: String { text("版本", "Version") }
    public static var currentVersionLabel: String {
        text("当前版本", "Current version")
    }
    public static var unknownVersion: String {
        text("未知", "Unknown")
    }
    public static var invalidCurrentVersion: String {
        text(
            "当前 App 包缺少有效版本号。",
            "The current app bundle does not contain a valid version."
        )
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
    public static var ignorePermissionNotifications: String {
        text("忽略审批通知", "Ignore approval notifications")
    }
    public static var ignorePermissionNotificationsHelp: String {
        text(
            "如果你使用“替我审批”，建议开启。开启后 CoPing 不再发送任何审批通知；任务完成和提问通知不受影响。",
            "Turn this on if you use “Review for me.” CoPing will stop all approval notifications; completion and question notifications are unaffected."
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
    public static var softwareUpdate: String {
        text("软件更新", "Software Update")
    }
    public static var checkForUpdates: String {
        text("检查更新", "Check for Updates")
    }
    public static var checkForUpdatesHelp: String {
        text(
            "手动检查 GitHub 上最新的正式版本。",
            "Manually check the latest stable release on GitHub."
        )
    }
    public static var checkingForUpdates: String {
        text("正在检查更新…", "Checking for updates…")
    }
    public static var upToDate: String {
        text("当前已是最新版", "CoPing is up to date")
    }
    public static var updateAvailable: String {
        text("发现新版本", "Update available")
    }
    public static func latestVersionValue(_ version: String) -> String {
        text("最新版本 \(version)", "Latest version \(version)")
    }
    public static var downloadUpdate: String {
        text("下载更新", "Download Update")
    }
    public static var download: String {
        text("下载", "Download")
    }
    public static func downloadingVersion(_ version: String) -> String {
        text("正在下载 \(version)…", "Downloading \(version)…")
    }
    public static var cancelDownload: String {
        text("取消", "Cancel")
    }
    public static var downloadComplete: String {
        text("下载完成", "Download complete")
    }
    public static func downloadedVersion(_ version: String) -> String {
        text(
            "CoPing \(version) 已保存到所选位置。",
            "CoPing \(version) was saved to the selected location."
        )
    }
    public static var showInFinder: String {
        text("在 Finder 中显示", "Show in Finder")
    }
    public static var updateFailed: String {
        text("更新失败", "Update failed")
    }
    public static var retryDownload: String {
        text("重新下载", "Retry Download")
    }
    public static var chooseDownloadLocation: String {
        text("选择更新包的保存位置", "Choose Where to Save the Update")
    }
    public static var updateInvalidResponse: String {
        text(
            "GitHub 返回了无法识别的响应。",
            "GitHub returned an unrecognized response."
        )
    }
    public static var noPublishedRelease: String {
        text(
            "GitHub 上还没有可用的正式版本。",
            "No stable release is available on GitHub yet."
        )
    }
    public static var noPublishedReleaseTitle: String {
        text("暂无正式版本", "No Stable Release")
    }
    public static func updateHTTPFailure(_ status: Int) -> String {
        text(
            "检查更新失败（HTTP \(status)）。",
            "Failed to check for updates (HTTP \(status))."
        )
    }
    public static var invalidReleaseMetadata: String {
        text(
            "GitHub Release 的版本信息无效。",
            "The GitHub Release has invalid version metadata."
        )
    }
    public static func missingReleaseAsset(_ name: String) -> String {
        text(
            "GitHub Release 缺少 \(name)。",
            "The GitHub Release is missing \(name)."
        )
    }
    public static var insecureReleaseAsset: String {
        text(
            "GitHub Release 提供了不安全的下载地址。",
            "The GitHub Release provided an insecure download URL."
        )
    }
    public static var downloadInvalidResponse: String {
        text(
            "下载服务器返回了无法识别的响应。",
            "The download server returned an unrecognized response."
        )
    }
    public static func downloadHTTPFailure(_ status: Int) -> String {
        text(
            "下载更新失败（HTTP \(status)）。",
            "Failed to download the update (HTTP \(status))."
        )
    }
    public static var invalidReleaseChecksum: String {
        text(
            "Release 校验文件格式无效。",
            "The release checksum file is invalid."
        )
    }
    public static var releaseChecksumMismatch: String {
        text(
            "下载文件校验失败，文件没有保存。",
            "The downloaded file failed verification and was not saved."
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
        text("Bark 推送地址", "Bark push URL")
    }
    public static var deviceKeyHelp: String {
        text(
            "在 iPhone 上打开 Bark，点击示例通知右侧的复制按钮，再把复制的完整地址粘贴到这里。CoPing 会自动完成设置。",
            "On your iPhone, open Bark, tap the copy button next to an example notification, then paste the full URL here. CoPing will finish the setup automatically."
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
            "无需另行安装终端版 Codex。点击“连接 Codex”后，CoPing 会使用 Codex 桌面应用自带的版本，并自动打开终端。看到输入光标后，输入 /hooks 并按回车；在打开的列表中找到 CoPingHook，按界面提示选择“信任全部”。",
            "You do not need to install the Codex CLI separately. After you click “Connect Codex,” CoPing uses the version included with the Codex desktop app and opens Terminal automatically. At the prompt, enter /hooks and press Return. Find CoPingHook in the list, then follow the on-screen instructions to trust all of its hooks."
        )
    }
    public static var firstConnectionVerificationHelp: String {
        text(
            "完成后输入 /quit 并关闭终端。安装前已经打开的旧对话可能不会加载新的监听器。",
            "When finished, enter /quit and close Terminal. Conversations opened before installation may not load the new hooks."
        )
    }
    public static var awaitingVerificationTitle: String {
        text("还差最后一步", "One last step")
    }
    public static var awaitingVerificationHelp: String {
        text(
            "退出安装终端，回到 Codex 桌面版新建一个对话，并发送任意消息。",
            "Exit the setup Terminal, return to Codex Desktop, create a new conversation, and send any message."
        )
    }
    public static var awaitingVerificationTroubleshooting: String {
        text(
            "如果仍无反应，请完全退出并重新打开 Codex 后再试。",
            "If nothing happens, quit Codex completely, reopen it, and try again."
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
            "请在终端输入 /hooks，信任 CoPing 后退出，再回到 Codex 桌面版新建对话。",
            "In Terminal, enter /hooks, trust CoPing, and exit. Then return to Codex Desktop and create a new conversation."
        )
    }
    public static var reviewFinishedStatus: String {
        text(
            "完成终端审核后，请回到 Codex 桌面版新建对话进行验证。",
            "After reviewing the hooks, return to Codex Desktop and create a new conversation to verify the connection."
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
        "CoPing"
    }
    public static var testNotificationBody: String {
        text("Bark 测试通知", "Bark test notification")
    }
    public static var completedNotificationTitle: String {
        "CoPing"
    }
    public static func completedNotificationBody(
        taskTitle: String? = nil,
        language: AppLanguage = .current
    ) -> String {
        if let taskTitle = notificationTaskTitle(taskTitle) {
            return language.text(
                chinese: "Codex [\(taskTitle)] 任务完成",
                english: "Codex [\(taskTitle)] task completed"
            )
        }
        return language.text(
            chinese: "Codex 任务完成",
            english: "Codex task completed"
        )
    }
    public static var permissionNotificationTitle: String {
        "CoPing"
    }
    public static func permissionNotificationBody(
        taskTitle: String? = nil,
        language: AppLanguage = .current
    ) -> String {
        if let taskTitle = notificationTaskTitle(taskTitle) {
            return language.text(
                chinese: "Codex [\(taskTitle)] 需要审批",
                english: "Codex [\(taskTitle)] needs approval"
            )
        }
        return language.text(
            chinese: "Codex 需要审批",
            english: "Codex needs approval"
        )
    }
    public static var questionNotificationTitle: String {
        "CoPing"
    }
    public static func questionNotificationBody(
        taskTitle: String? = nil,
        language: AppLanguage = .current
    ) -> String {
        if let taskTitle = notificationTaskTitle(taskTitle) {
            return language.text(
                chinese: "Codex [\(taskTitle)] 等待回答",
                english: "Codex [\(taskTitle)] is waiting for an answer"
            )
        }
        return language.text(
            chinese: "Codex 等待回答",
            english: "Codex is waiting for an answer"
        )
    }

    private static func notificationTaskTitle(_ taskTitle: String?) -> String? {
        guard let taskTitle else { return nil }

        let singleLineTitle = taskTitle
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !singleLineTitle.isEmpty else { return nil }

        let widthLimit = 16
        var displayedWidth = 0
        let displayedCharacters = singleLineTitle.prefix { character in
            let characterWidth = character.isASCII ? 1 : 2
            guard displayedWidth + characterWidth <= widthLimit else { return false }
            displayedWidth += characterWidth
            return true
        }
        guard displayedCharacters.count < singleLineTitle.count else {
            return singleLineTitle
        }
        return "\(displayedCharacters)..."
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
