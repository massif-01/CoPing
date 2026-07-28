import AppKit
import CoPingCore
import CoPingAppSupport
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    typealias Notice = NoticePresenter.Notice

    @Published var baseURLString: String
    @Published var deviceKey: String
    @Published var barkEnabled: Bool
    @Published private var ntfySettings: NtfySettingsCoordinator
    @Published var notificationsEnabled: Bool
    @Published var ignorePermissionNotifications: Bool
    @Published var launchAtLogin: Bool
    @Published var languagePreference: AppLanguagePreference
    @Published var connectionStatus: CodexConnectionStatus
    @Published var notice: Notice?
    @Published var records: [DeliveryRecord]
    @Published var isBusy = false

    private let defaults = UserDefaults.standard
    private let deviceKeyStore = DeviceKeyStore()
    private let historyStore = DeliveryHistoryStore()
    private let deliveryDispatcher = PushDeliveryDispatcher()
    private let ntfySession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()
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
        let loadedDeviceKey: String
        baseURLString = defaults.string(forKey: "barkBaseURL") ?? "https://api.day.app"
        do {
            loadedDeviceKey = try deviceKeyStore.read() ?? ""
            deviceKeyReadFailed = false
        } catch {
            loadedDeviceKey = ""
            deviceKeyReadFailed = true
        }
        deviceKey = loadedDeviceKey
        ntfySettings = NtfySettingsCoordinator(defaults: defaults)
        barkEnabled =
            defaults.object(forKey: "barkEnabled") as? Bool
            ?? !loadedDeviceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        } else if ntfySettings.configurationReadFailed {
            showNotice(AppText.ntfyConfigurationReadFailed, kind: .error)
        }
    }

    deinit {
        ntfySession.invalidateAndCancel()
    }

    var codexDetected: Bool { CodexDetector.isInstalled }
    var hasBarkConfiguration: Bool {
        !deviceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (try? validatedBaseURL()) != nil
    }
    var hasNtfyConfiguration: Bool {
        ntfySettings.hasCurrentConfiguration
    }
    var ntfyTopic: String { ntfySettings.topic }
    var ntfyEnabled: Bool { ntfySettings.isEnabled }

    var menuStatusText: String {
        if !notificationsEnabled { return AppText.notificationsPaused }
        if connectionStatus == .error { return AppText.configurationError }
        if records.first?.aggregateStatus == .failed { return AppText.recentPushFailed }
        if records.first?.aggregateStatus == .partial {
            return AppText.recentPushPartiallyFailed
        }
        return connectionStatus.label
    }

    func saveBarkSettings() {
        _ = persistBarkSettings(showConfirmation: true)
    }

    @discardableResult
    private func persistBarkSettings(showConfirmation: Bool) -> Bool {
        do {
            let configuration = try BarkConfiguration(
                baseURLString: baseURLString,
                deviceKeyInput: deviceKey
            )
            try deviceKeyStore.save(configuration.deviceKey)
            deviceKey = configuration.deviceKey
            baseURLString = configuration.baseURL.absoluteString
            defaults.set(baseURLString, forKey: "barkBaseURL")
            if showConfirmation {
                showNotice(AppText.barkSettingsSaved, kind: .success)
            }
            return true
        } catch {
            showNotice(error.localizedDescription, kind: .error)
            return false
        }
    }

    func setBarkEnabled(_ enabled: Bool) {
        guard !enabled || hasBarkConfiguration else {
            showNotice(AppText.barkNotConfigured, kind: .error)
            return
        }
        barkEnabled = enabled
        defaults.set(enabled, forKey: "barkEnabled")
    }

    func saveNtfySettings() {
        _ = persistNtfySettings(showConfirmation: true)
    }

    @discardableResult
    private func persistNtfySettings(showConfirmation: Bool) -> Bool {
        do {
            try ntfySettings.save()
            if showConfirmation {
                showNotice(AppText.ntfySettingsSaved, kind: .success)
            }
            return true
        } catch {
            showNotice(error.localizedDescription, kind: .error)
            return false
        }
    }

    func setNtfyEnabled(_ enabled: Bool) {
        do {
            try ntfySettings.setEnabled(enabled)
        } catch {
            showNotice(error.localizedDescription, kind: .error)
        }
    }

    func copyNtfyTopic() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ntfyTopic, forType: .string)
        showNotice(AppText.ntfyTopicCopied, kind: .success)
    }

    func regenerateNtfyTopic() {
        ntfySettings.regenerateTopic()
        showNotice(AppText.ntfyTopicRegenerated, kind: .information)
    }

    func sendBarkTestNotification() {
        guard !isBusy else { return }
        guard persistBarkSettings(showConfirmation: false) else { return }
        do {
            sendTestNotification(
                PushNotification(
                    title: AppText.testNotificationTitle,
                    body: AppText.testNotificationBody
                ),
                to: try barkTarget()
            )
        } catch {
            showNotice(error.localizedDescription, kind: .error)
        }
    }

    func sendNtfyTestNotification() {
        guard !isBusy else { return }
        guard
            persistNtfySettings(showConfirmation: false),
            let target = ntfyTarget()
        else {
            return
        }
        sendTestNotification(
            PushNotification(
                title: AppText.testNotificationTitle,
                body: AppText.ntfyTestNotificationBody
            ),
            to: target
        )
    }

    private func sendTestNotification(
        _ notification: PushNotification,
        to target: PushDeliveryTarget
    ) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            let event = CodexEvent(
                type: .completed,
                sessionID: "test",
                turnID: UUID().uuidString,
                projectName: "CoPing"
            )
            do {
                let attempts = try await deliveryDispatcher.deliver(
                    notification,
                    to: [target]
                )
                appendRecord(for: event, attempts: attempts)
                presentDeliveryResult(attempts)
            } catch is CancellationError {
                return
            } catch {
                showNotice(AppText.networkRequestFailed, kind: .error)
            }
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
            do {
                try HookTrustLauncher().openReviewTerminal()
                showNotice(AppText.trustHooksStatus, kind: .information)
            } catch {
                showNotice(error.localizedDescription, kind: .error)
            }
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
        guard event.verifiesConnection else { return }

        if connectionStatus.verify(with: event) {
            defaults.set(true, forKey: "codexConnectionVerified")
            showNotice(AppText.codexConnectionVerified, kind: .success)
        }

        guard remember(event.uniqueKey) else { return }

        switch event.type {
        case .sessionStarted:
            break
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
                PushNotification(
                    title: title,
                    body: body,
                    urgency: .high
                ),
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
        let deliveryChannels = PushDeliveryRouting.eventChannels(
            notificationsEnabled: notificationsEnabled,
            barkEnabled: barkEnabled,
            ntfyEnabled: ntfyEnabled
        )
        guard notificationsEnabled else {
            let attempts = enabledChannels.map {
                DeliveryRecord.Attempt(
                    channel: $0,
                    outcome: .skipped,
                    detail: AppText.notificationsPaused
                )
            }
            appendRecord(
                for: event,
                attempts: attempts,
                detail: attempts.isEmpty ? AppText.notificationsPaused : nil
            )
            return
        }

        var targets: [PushDeliveryTarget] = []
        var attemptsByChannel: [PushChannel: DeliveryRecord.Attempt] = [:]

        if deliveryChannels.contains(.bark) {
            do {
                targets.append(try barkTarget())
            } catch {
                attemptsByChannel[.bark] = DeliveryRecord.Attempt(
                    channel: .bark,
                    outcome: .failed,
                    detail: AppText.barkNotConfigured
                )
            }
        }

        if deliveryChannels.contains(.ntfy) {
            if let target = ntfyTarget() {
                targets.append(target)
            } else {
                attemptsByChannel[.ntfy] = DeliveryRecord.Attempt(
                    channel: .ntfy,
                    outcome: .failed,
                    detail: AppText.ntfyNotConfigured
                )
            }
        }

        let deliveredAttempts: [DeliveryRecord.Attempt]
        do {
            deliveredAttempts = try await deliveryDispatcher.deliver(
                notification,
                to: targets
            )
        } catch is CancellationError {
            return
        } catch {
            assertionFailure("Push dispatcher threw a non-cancellation error")
            return
        }
        for attempt in deliveredAttempts {
            attemptsByChannel[attempt.channel] = attempt
        }
        let attempts = PushChannel.allCases.compactMap { attemptsByChannel[$0] }
        appendRecord(
            for: event,
            attempts: attempts,
            detail: attempts.isEmpty ? AppText.noPushChannelEnabled : nil
        )
        presentDeliveryResult(attempts)
    }

    private func appendRecord(
        for event: CodexEvent,
        attempts: [DeliveryRecord.Attempt],
        detail: String? = nil
    ) {
        records.insert(
            DeliveryRecord(
                eventType: event.type,
                projectName: event.projectName,
                attempts: attempts,
                detail: detail
            ),
            at: 0
        )
        records = Array(records.prefix(100))
        try? historyStore.save(records)
    }

    private var enabledChannels: [PushChannel] {
        PushDeliveryRouting.eventChannels(
            notificationsEnabled: true,
            barkEnabled: barkEnabled,
            ntfyEnabled: ntfyEnabled
        )
    }

    private func barkTarget() throws -> PushDeliveryTarget {
        let client = try BarkClient(
            baseURL: validatedBaseURL(),
            deviceKey: deviceKey
        )
        return PushDeliveryTarget(channel: .bark, provider: client)
    }

    private func ntfyTarget() -> PushDeliveryTarget? {
        guard let configuration = ntfySettings.deliveryConfiguration else {
            return nil
        }
        return PushDeliveryTarget(
            channel: .ntfy,
            provider: NtfyClient(
                configuration: configuration,
                session: ntfySession
            )
        )
    }

    private func presentDeliveryResult(_ attempts: [DeliveryRecord.Attempt]) {
        let status = DeliveryRecord.aggregateStatus(for: attempts)
        let sentCount = attempts.count { $0.outcome == .sent }

        switch status {
        case .sent:
            showNotice(
                sentCount == 1
                    ? AppText.notificationSent
                    : AppText.notificationsSent(sentCount),
                kind: .success
            )
        case .partial:
            showNotice(AppText.notificationPartiallySent, kind: .error)
        case .failed, .skipped:
            guard let detail = attempts.first(where: { $0.outcome != .sent })?.detail else {
                return
            }
            showNotice(AppText.pushFailed(detail), kind: .error)
        }
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

    func dismissNotice(id: UUID? = nil) {
        noticePresenter.dismiss(id: id)
    }

    private func showNotice(_ message: String, kind: Notice.Kind) {
        noticePresenter.show(message, kind: kind)
    }
}
