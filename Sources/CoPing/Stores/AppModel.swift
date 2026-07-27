import CoPingCore
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum ConnectionStatus: String {
        case disconnected = "未连接"
        case awaitingVerification = "等待新任务验证"
        case connected = "已连接"
        case error = "配置异常"
    }

    @Published var baseURLString: String
    @Published var deviceKey: String
    @Published var notificationsEnabled: Bool
    @Published var launchAtLogin: Bool
    @Published var connectionStatus: ConnectionStatus
    @Published var statusMessage: String?
    @Published var records: [DeliveryRecord]
    @Published var isBusy = false

    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore()
    private let historyStore = DeliveryHistoryStore()
    private let helperInstaller = HelperInstaller()
    private let hookManager = HookConfigurationManager()
    private let loginManager = LoginItemManager()
    private var pendingInterventions: [String: Task<Void, Never>] = [:]
    private var seenEventKeys: [String] = []
    private var seenEventSet: Set<String> = []

    private lazy var socketServer = UnixSocketServer { [weak self] event in
        Task { @MainActor in self?.receive(event) }
    }

    init(startServices: Bool = true) {
        baseURLString = defaults.string(forKey: "barkBaseURL") ?? "https://api.day.app"
        deviceKey = (try? keychain.read()) ?? ""
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? true
        records = historyStore.load()

        if hookManager.isInstalled() {
            connectionStatus = defaults.bool(forKey: "codexConnectionVerified")
                ? .connected
                : .awaitingVerification
        } else {
            connectionStatus = .disconnected
        }

        if startServices {
            do {
                try socketServer.start()
            } catch {
                connectionStatus = .error
                statusMessage = "事件监听器启动失败。"
            }

            if defaults.object(forKey: "didConfigureLoginItem") == nil {
                setLaunchAtLogin(true)
                defaults.set(true, forKey: "didConfigureLoginItem")
            } else {
                launchAtLogin = loginManager.isEnabled
            }
        }
    }

    var codexDetected: Bool { CodexDetector.isInstalled }
    var hasBarkConfiguration: Bool {
        !deviceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (try? validatedBaseURL()) != nil
    }

    var menuStatusText: String {
        if !notificationsEnabled { return "通知已暂停" }
        if connectionStatus == .error { return "配置异常" }
        if records.first?.outcome == .failed { return "最近推送失败" }
        return connectionStatus.rawValue
    }

    func saveBarkSettings() {
        do {
            let configuration = try BarkConfiguration(
                baseURLString: baseURLString,
                deviceKeyInput: deviceKey
            )
            try keychain.save(configuration.deviceKey)
            deviceKey = configuration.deviceKey
            baseURLString = configuration.baseURL.absoluteString
            defaults.set(baseURLString, forKey: "barkBaseURL")
            statusMessage = "Bark 配置已保存。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func sendTestNotification() {
        saveBarkSettings()
        guard hasBarkConfiguration else { return }
        isBusy = true
        Task {
            let event = CodexEvent(
                type: .completed,
                sessionID: "test",
                turnID: UUID().uuidString,
                projectName: "CoPing"
            )
            await deliver(
                PushNotification(title: "CoPing · 测试通知", body: "CoPing 已成功连接 Bark"),
                for: event
            )
            isBusy = false
        }
    }

    func connectCodex() {
        guard codexDetected else {
            connectionStatus = .error
            statusMessage = "未检测到 /Applications/ChatGPT.app。"
            return
        }
        isBusy = true
        do {
            try helperInstaller.install()
            _ = try hookManager.installConfiguration()
            defaults.set(false, forKey: "codexConnectionVerified")
            connectionStatus = .awaitingVerification
            try HookTrustLauncher().openReviewTerminal()
            statusMessage = "请在终端输入 /hooks，信任 CoPing 后退出。新建 Codex 任务即可完成验证。"
        } catch {
            connectionStatus = .error
            statusMessage = error.localizedDescription
        }
        isBusy = false
    }

    func openHookReview() {
        do {
            try HookTrustLauncher().openReviewTerminal()
            statusMessage = "完成终端审核后，新建一个 Codex 任务进行验证。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func disconnectCodex() {
        do {
            try hookManager.uninstallConfiguration()
            try helperInstaller.uninstall()
            defaults.set(false, forKey: "codexConnectionVerified")
            connectionStatus = .disconnected
            statusMessage = "已断开，仅移除了 CoPing 自己的 Hook。"
        } catch {
            connectionStatus = .error
            statusMessage = error.localizedDescription
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        defaults.set(enabled, forKey: "notificationsEnabled")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginManager.setEnabled(enabled)
            launchAtLogin = loginManager.isEnabled
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            statusMessage = nil
        } catch {
            launchAtLogin = loginManager.isEnabled
            statusMessage = "登录启动设置失败：\(error.localizedDescription)"
        }
    }

    func clearHistory() {
        do {
            try historyStore.clear()
            records = []
        } catch {
            statusMessage = "无法清空记录。"
        }
    }

    private func receive(_ event: CodexEvent) {
        guard event.version == 1, remember(event.uniqueKey) else { return }

        switch event.type {
        case .sessionStarted:
            defaults.set(true, forKey: "codexConnectionVerified")
            connectionStatus = .connected
            statusMessage = "Codex 桌面事件连接已验证。"
        case .completed:
            pendingInterventions[event.turnKey]?.cancel()
            pendingInterventions[event.turnKey] = nil
            Task {
                await deliver(
                    PushNotification(
                        title: "CoPing · 任务完成",
                        body: "\(event.projectName) — Codex 已完成任务"
                    ),
                    for: event
                )
            }
        case .permissionRequested, .questionRequested:
            scheduleIntervention(event)
        }
    }

    private func scheduleIntervention(_ event: CodexEvent) {
        guard pendingInterventions[event.turnKey] == nil else { return }
        pendingInterventions[event.turnKey] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self else { return }
            let body: String
            switch event.type {
            case .permissionRequested:
                body = "\(event.projectName) — Codex 请求了权限，请查看电脑"
            case .questionRequested:
                body = "\(event.projectName) — Codex 提出了问题，请查看电脑"
            default:
                return
            }
            await self.deliver(
                PushNotification(title: "CoPing · 可能需要介入", body: body),
                for: event
            )
            self.pendingInterventions[event.turnKey] = nil
        }
    }

    private func deliver(_ notification: PushNotification, for event: CodexEvent) async {
        guard notificationsEnabled else {
            appendRecord(for: event, outcome: .skipped, detail: "通知已暂停")
            return
        }
        guard hasBarkConfiguration else {
            appendRecord(for: event, outcome: .skipped, detail: "Bark 未配置")
            return
        }

        do {
            let client = try BarkClient(
                baseURL: validatedBaseURL(),
                deviceKey: deviceKey
            )
            let delays: [Duration] = [.zero, .seconds(2), .seconds(10)]
            var lastError: Error?
            for delay in delays {
                if delay != .zero { try? await Task.sleep(for: delay) }
                do {
                    try await client.send(notification)
                    appendRecord(for: event, outcome: .sent)
                    statusMessage = "通知已发送。"
                    return
                } catch {
                    lastError = error
                }
            }
            throw lastError ?? BarkError.invalidResponse
        } catch {
            appendRecord(for: event, outcome: .failed, detail: safeError(error))
            statusMessage = "推送失败：\(safeError(error))"
        }
    }

    private func appendRecord(
        for event: CodexEvent,
        outcome: DeliveryRecord.Outcome,
        detail: String? = nil
    ) {
        records.insert(
            DeliveryRecord(
                eventType: event.type,
                projectName: event.projectName,
                outcome: outcome,
                detail: detail
            ),
            at: 0
        )
        records = Array(records.prefix(100))
        try? historyStore.save(records)
    }

    private func validatedBaseURL() throws -> URL {
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw BarkError.invalidBaseURL
        }
        _ = try BarkClient(baseURL: url, deviceKey: "validation")
        return url
    }

    private func remember(_ key: String) -> Bool {
        guard seenEventSet.insert(key).inserted else { return false }
        seenEventKeys.append(key)
        if seenEventKeys.count > 200 {
            let removed = seenEventKeys.removeFirst()
            seenEventSet.remove(removed)
        }
        return true
    }

    private func safeError(_ error: Error) -> String {
        if let bark = error as? BarkError {
            return bark.localizedDescription
        }
        return "网络请求失败"
    }
}
