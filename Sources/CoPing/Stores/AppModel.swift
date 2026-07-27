import CoPingCore
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    struct Notice: Equatable, Identifiable {
        enum Kind {
            case success
            case information
            case error
        }

        let id = UUID()
        let message: String
        let kind: Kind
    }

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
    @Published var launchAtLogin: Bool
    @Published var languagePreference: AppLanguagePreference
    @Published var connectionStatus: ConnectionStatus
    @Published var notice: Notice?
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
            try keychain.save(configuration.deviceKey)
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

    func setLanguagePreference(_ preference: AppLanguagePreference) {
        defaults.set(preference.rawValue, forKey: AppLanguagePreference.defaultsKey)
        languagePreference = preference
        notice = nil
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginManager.setEnabled(enabled)
            launchAtLogin = loginManager.isEnabled
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            notice = nil
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
            pendingInterventions[event.turnKey]?.cancel()
            pendingInterventions[event.turnKey] = nil
            Task {
                await deliver(
                    PushNotification(
                        title: AppText.completedNotificationTitle,
                        body: AppText.completedNotificationBody(project: event.projectName)
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
            let title: String
            let body: String
            switch event.type {
            case .permissionRequested:
                title = AppText.permissionNotificationTitle
                body = AppText.permissionNotificationBody(project: event.projectName)
            case .questionRequested:
                title = AppText.questionNotificationTitle
                body = AppText.questionNotificationBody(project: event.projectName)
            default:
                return
            }
            await self.deliver(
                PushNotification(title: title, body: body),
                for: event
            )
            self.pendingInterventions[event.turnKey] = nil
        }
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
        guard id == nil || notice?.id == id else { return }
        notice = nil
    }

    private func showNotice(_ message: String, kind: Notice.Kind) {
        notice = Notice(message: message, kind: kind)
    }
}
