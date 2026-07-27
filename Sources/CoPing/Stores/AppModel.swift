import CoPingCore
import CoPingAppSupport
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    typealias Notice = NoticePresenter.Notice

    enum ConnectionStatus {
        case disconnected
        case awaitingVerification
        case connected
        case error

        var label: String {
            switch self {
            case .disconnected: return AppText.disconnected
            case .awaitingVerification: return AppText.awaitingVerification
            case .connected: return AppText.connected
            case .error: return AppText.configurationError
            }
        }
    }

    @Published var baseURLString: String
    @Published var deviceKey: String
    @Published var notificationsEnabled: Bool
    @Published var ignorePermissionNotifications: Bool
    @Published var launchAtLogin: Bool
    @Published var languagePreference: AppLanguagePreference
    @Published var connectionStatus: ConnectionStatus
    @Published var notice: Notice?
    @Published var records: [DeliveryRecord]
    @Published var isBusy = false

    private let defaults = UserDefaults.standard
    private let deviceKeyStore = DeviceKeyStore()
    private let historyStore = DeliveryHistoryStore()
    private let helperInstaller = HelperInstaller()
    private let hookManager = HookConfigurationManager()
    private let loginManager = LoginItemManager()
    private let taskTitleResolver = CodexTaskTitleResolver()
    private struct PendingIntervention {
        let eventType: CodexEvent.EventType
        let task: Task<Void, Never>
    }

    private var pendingInterventions: [String: PendingIntervention] = [:]
    private var seenEventKeys: [String] = []
    private var seenEventSet: Set<String> = []

    private lazy var noticePresenter = NoticePresenter { [weak self] notice in
        self?.notice = notice
    }

    private lazy var socketServer = UnixSocketServer { [weak self] event in
        Task { @MainActor in self?.receive(event) }
    }

    init(startServices: Bool = true) {
        let deviceKeyReadFailed: Bool
        baseURLString = defaults.string(forKey: "barkBaseURL") ?? "https://api.day.app"
        do {
            deviceKey = try deviceKeyStore.read() ?? ""
            deviceKeyReadFailed = false
        } catch {
            deviceKey = ""
            deviceKeyReadFailed = true
        }
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        ignorePermissionNotifications =
            defaults.object(forKey: "ignorePermissionNotifications") as? Bool ?? false
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? true
        languagePreference = AppLanguagePreference.current
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
                showNotice(AppText.eventListenerStartFailed, kind: .error)
            }

            if defaults.object(forKey: "didConfigureLoginItem") == nil {
                setLaunchAtLogin(true)
                defaults.set(true, forKey: "didConfigureLoginItem")
            } else {
                launchAtLogin = loginManager.isEnabled
            }
        }

        if deviceKeyReadFailed {
            showNotice(AppText.barkConfigurationReadFailed, kind: .error)
        }
    }

    var codexDetected: Bool { CodexDetector.isInstalled }
    var hasBarkConfiguration: Bool {
        !deviceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (try? validatedBaseURL()) != nil
    }

    var menuStatusText: String {
        if !notificationsEnabled { return AppText.notificationsPaused }
        if connectionStatus == .error { return AppText.configurationError }
        if records.first?.outcome == .failed { return AppText.recentPushFailed }
        return connectionStatus.label
    }

    func saveBarkSettings() {
        do {
            let configuration = try BarkConfiguration(
                baseURLString: baseURLString,
                deviceKeyInput: deviceKey
            )
            try deviceKeyStore.save(configuration.deviceKey)
            deviceKey = configuration.deviceKey
            baseURLString = configuration.baseURL.absoluteString
            defaults.set(baseURLString, forKey: "barkBaseURL")
            showNotice(AppText.barkSettingsSaved, kind: .success)
        } catch {
            showNotice(error.localizedDescription, kind: .error)
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
                PushNotification(
                    title: AppText.testNotificationTitle,
                    body: AppText.testNotificationBody
                ),
                for: event
            )
            isBusy = false
        }
    }

    func connectCodex() {
        guard codexDetected else {
            connectionStatus = .error
            showNotice(AppText.chatGPTNotDetected, kind: .error)
            return
        }
        isBusy = true
        do {
            try helperInstaller.install()
            _ = try hookManager.installConfiguration()
            defaults.set(false, forKey: "codexConnectionVerified")
            connectionStatus = .awaitingVerification
            try HookTrustLauncher().openReviewTerminal()
            showNotice(AppText.trustHooksStatus, kind: .information)
        } catch {
            connectionStatus = .error
            showNotice(error.localizedDescription, kind: .error)
        }
        isBusy = false
    }

    func openHookReview() {
        do {
            try HookTrustLauncher().openReviewTerminal()
            showNotice(AppText.reviewFinishedStatus, kind: .information)
        } catch {
            showNotice(error.localizedDescription, kind: .error)
        }
    }

    func disconnectCodex() {
        do {
            try hookManager.uninstallConfiguration()
            try helperInstaller.uninstall()
            defaults.set(false, forKey: "codexConnectionVerified")
            connectionStatus = .disconnected
            showNotice(AppText.disconnectedStatus, kind: .information)
        } catch {
            connectionStatus = .error
            showNotice(error.localizedDescription, kind: .error)
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        defaults.set(enabled, forKey: "notificationsEnabled")
    }

    func setIgnorePermissionNotifications(_ ignored: Bool) {
        ignorePermissionNotifications = ignored
        defaults.set(ignored, forKey: "ignorePermissionNotifications")

        guard ignored else { return }
        let pendingPermissionKeys = pendingInterventions.compactMap { key, pending in
            pending.eventType == .permissionRequested ? key : nil
        }
        for key in pendingPermissionKeys {
            pendingInterventions.removeValue(forKey: key)?.task.cancel()
        }
    }

    func setLanguagePreference(_ preference: AppLanguagePreference) {
        defaults.set(preference.rawValue, forKey: AppLanguagePreference.defaultsKey)
        languagePreference = preference
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginManager.setEnabled(enabled)
            launchAtLogin = loginManager.isEnabled
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
        } catch {
            launchAtLogin = loginManager.isEnabled
            showNotice(
                AppText.loginItemFailure(error.localizedDescription),
                kind: .error
            )
        }
    }

    func clearHistory() {
        do {
            try historyStore.clear()
            records = []
        } catch {
            showNotice(AppText.clearHistoryFailed, kind: .error)
        }
    }

    private func receive(_ event: CodexEvent) {
        guard event.version == 1, remember(event.uniqueKey) else { return }

        switch event.type {
        case .sessionStarted:
            defaults.set(true, forKey: "codexConnectionVerified")
            connectionStatus = .connected
            showNotice(AppText.codexConnectionVerified, kind: .success)
        case .completed:
            pendingInterventions.removeValue(forKey: event.turnKey)?.task.cancel()
            let taskTitle = taskTitleResolver.title(for: event.sessionID)
            Task {
                await deliver(
                    PushNotification(
                        title: AppText.completedNotificationTitle,
                        body: AppText.completedNotificationBody(taskTitle: taskTitle)
                    ),
                    for: event
                )
            }
        case .permissionRequested:
            let preferences = CodexNotificationPreferences(
                ignorePermissionNotifications: ignorePermissionNotifications
            )
            guard preferences.allows(event.type) else { return }
            scheduleIntervention(event)
        case .questionRequested:
            scheduleIntervention(event)
        }
    }

    private func scheduleIntervention(_ event: CodexEvent) {
        guard pendingInterventions[event.turnKey] == nil else { return }
        let task = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self else { return }
            let title: String
            let body: String
            let taskTitle = self.taskTitleResolver.title(for: event.sessionID)
            switch event.type {
            case .permissionRequested:
                title = AppText.permissionNotificationTitle
                body = AppText.permissionNotificationBody(taskTitle: taskTitle)
            case .questionRequested:
                title = AppText.questionNotificationTitle
                body = AppText.questionNotificationBody(taskTitle: taskTitle)
            default:
                return
            }
            await self.deliver(
                PushNotification(title: title, body: body),
                for: event
            )
            self.pendingInterventions[event.turnKey] = nil
        }
        pendingInterventions[event.turnKey] = PendingIntervention(
            eventType: event.type,
            task: task
        )
    }

    private func deliver(_ notification: PushNotification, for event: CodexEvent) async {
        guard notificationsEnabled else {
            appendRecord(for: event, outcome: .skipped, detail: AppText.notificationsPaused)
            return
        }
        guard hasBarkConfiguration else {
            appendRecord(for: event, outcome: .skipped, detail: AppText.barkNotConfigured)
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
                    showNotice(AppText.notificationSent, kind: .success)
                    return
                } catch {
                    lastError = error
                }
            }
            throw lastError ?? BarkError.invalidResponse
        } catch {
            appendRecord(for: event, outcome: .failed, detail: safeError(error))
            showNotice(AppText.pushFailed(safeError(error)), kind: .error)
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
        return AppText.networkRequestFailed
    }

    func dismissNotice(id: UUID? = nil) {
        noticePresenter.dismiss(id: id)
    }

    private func showNotice(_ message: String, kind: Notice.Kind) {
        noticePresenter.show(message, kind: kind)
    }
}
