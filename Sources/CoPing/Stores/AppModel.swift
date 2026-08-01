import AppKit
import CoPingCore
import CoPingAppSupport
import Combine
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    typealias Notice = NoticePresenter.Notice

    @Published private var barkSettings: BarkSettingsCoordinator
    @Published private var ntfySettings: NtfySettingsCoordinator
    @Published var notificationsEnabled: Bool
    @Published var approvalNotificationMode: ApprovalNotificationMode
    @Published var launchAtLogin: Bool
    @Published var languagePreference: AppLanguagePreference
    @Published var connectionStatus: CodexConnectionStatus
    @Published var approvalStateHealth: CodexApprovalMonitorHealth = .stopped
    @Published var notice: Notice?
    @Published var records: [DeliveryRecord]
    @Published var isBusy = false

    private let defaults = UserDefaults.standard
    private let historyStore = DeliveryHistoryStore()
    private let deliveryDispatcher = PushDeliveryDispatcher()
    private let barkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()
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
    private let approvalLogger = Logger(
        subsystem: "com.coping.app",
        category: "ApprovalNotifications"
    )
    private struct PendingIntervention {
        let event: CodexEvent
        var task: Task<Void, Never>?
    }

    private var approvalStateMonitor: CodexApprovalStateMonitor?
    private var approvalCoordinator = CodexApprovalNotificationCoordinator()
    private var approvalFallbackTasks: [String: Task<Void, Never>] = [:]
    private var approvalDeliveryTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingInterventions: [String: PendingIntervention] = [:]
    private var codexEventProcessingSuspended = true
    private var seenEventKeys: [String] = []
    private var seenEventSet: Set<String> = []

    private lazy var noticePresenter = NoticePresenter { [weak self] notice in
        self?.notice = notice
    }

    private lazy var socketServer = UnixSocketServer { [weak self] event in
        Task { @MainActor in self?.receive(event) }
    }

    init(startServices: Bool = true) {
        barkSettings = BarkSettingsCoordinator(defaults: defaults)
        ntfySettings = NtfySettingsCoordinator(defaults: defaults)
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        let loadedApprovalNotificationMode = ApprovalNotificationMode.migrated(
            storedRawValue: defaults.string(forKey: "approvalNotificationMode"),
            legacyIgnorePermissionNotifications:
                defaults.object(forKey: "ignorePermissionNotifications") as? Bool
        )
        approvalNotificationMode = loadedApprovalNotificationMode
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? true
        languagePreference = AppLanguagePreference.current
        records = historyStore.load()
        defaults.set(loadedApprovalNotificationMode.rawValue, forKey: "approvalNotificationMode")

        if hookManager.isInstalled() {
            connectionStatus = defaults.bool(forKey: "codexConnectionVerified")
                ? .connected
                : .awaitingVerification
            codexEventProcessingSuspended = false
        } else {
            connectionStatus = .disconnected
            codexEventProcessingSuspended = true
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

        if barkSettings.configurationReadFailed {
            showNotice(AppText.barkConfigurationReadFailed, kind: .error)
        } else if barkSettings.configurationMigrationFailed {
            showNotice(AppText.barkConfigurationMigrationFailed, kind: .error)
        } else if ntfySettings.configurationReadFailed {
            showNotice(AppText.ntfyConfigurationReadFailed, kind: .error)
        }

        if
            startServices,
            approvalNotificationMode == .actionNeeded,
            !codexEventProcessingSuspended
        {
            startApprovalStateMonitor()
        }
    }

    deinit {
        approvalStateMonitor?.stop()
        approvalFallbackTasks.values.forEach { $0.cancel() }
        approvalDeliveryTasks.values.forEach { $0.cancel() }
        barkSession.invalidateAndCancel()
        ntfySession.invalidateAndCancel()
    }

    var codexDetected: Bool { CodexDetector.isInstalled }
    var baseURLString: String { barkSettings.baseURLString }
    var barkDestinationDrafts: [BarkDestinationDraft] { barkSettings.destinationDrafts }
    var barkValidationErrors: [UUID: String] { barkSettings.validationErrors }
    var barkBaseURLValidationError: String? { barkSettings.baseURLValidationError }
    var barkEnabled: Bool { barkSettings.isEnabled }
    var ntfyTopic: String { ntfySettings.topic }
    var ntfyEnabled: Bool { ntfySettings.isEnabled }
    var approvalStateStatusText: String {
        if codexEventProcessingSuspended {
            return AppText.approvalStateConnectToUse()
        }
        switch approvalStateHealth {
        case .stopped, .connecting:
            return AppText.approvalStateChecking()
        case .ready:
            return AppText.approvalStateReady()
        case .unavailable, .unsupportedProtocol:
            return AppText.approvalStateUnavailable()
        }
    }

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

    func setBarkBaseURLString(_ value: String) {
        barkSettings.setBaseURLString(value)
    }

    func setBarkAddressInput(_ value: String, for id: UUID) {
        barkSettings.setAddressInput(value, for: id)
    }

    @discardableResult
    func addBarkDestination() -> UUID {
        barkSettings.addDestination()
    }

    func removeBarkDestination(id: UUID) {
        barkSettings.removeDestination(id: id)
    }

    @discardableResult
    private func persistBarkSettings(showConfirmation: Bool) -> Bool {
        do {
            try barkSettings.save()
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
        do {
            try barkSettings.setEnabled(enabled)
        } catch {
            showNotice(error.localizedDescription, kind: .error)
        }
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
                to: try barkTargets()
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
            to: [target]
        )
    }

    private func sendTestNotification(
        _ notification: PushNotification,
        to targets: [PushDeliveryTarget]
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
                    to: targets
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
            codexEventProcessingSuspended = false
            defaults.set(false, forKey: "codexConnectionVerified")
            connectionStatus = .awaitingVerification
            if approvalNotificationMode == .actionNeeded {
                startApprovalStateMonitor()
            }
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
        codexEventProcessingSuspended = true
        cancelCodexNotificationProcessing()
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

    func setApprovalNotificationMode(_ mode: ApprovalNotificationMode) {
        guard approvalNotificationMode != mode else { return }
        let approvalEvents = approvalCoordinator.pendingEvents
        approvalNotificationMode = mode
        defaults.set(mode.rawValue, forKey: "approvalNotificationMode")
        defaults.set(mode == .none, forKey: "ignorePermissionNotifications")

        let pendingPermissionKeys = pendingInterventions.compactMap { key, pending in
            pending.event.type == .permissionRequested ? key : nil
        }

        switch mode {
        case .all:
            cancelApprovalDeliveries()
            applyApprovalEffects(approvalCoordinator.reset())
            stopApprovalStateMonitor()
            for event in approvalEvents {
                scheduleIntervention(event, delay: .milliseconds(100))
            }
            for key in pendingPermissionKeys {
                armPendingIntervention(key, delay: .milliseconds(100))
            }
        case .actionNeeded:
            if !codexEventProcessingSuspended {
                startApprovalStateMonitor()
            }
            for key in pendingPermissionKeys {
                guard let pending = pendingInterventions[key] else { continue }
                cancelPendingIntervention(key)
                applyApprovalEffects(approvalCoordinator.receive(pending.event))
            }
        case .none:
            cancelApprovalDeliveries()
            applyApprovalEffects(approvalCoordinator.reset())
            stopApprovalStateMonitor()
            for key in pendingPermissionKeys {
                cancelPendingIntervention(key)
            }
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
        guard !codexEventProcessingSuspended, event.verifiesConnection else {
            return
        }

        if connectionStatus.verify(with: event) {
            defaults.set(true, forKey: "codexConnectionVerified")
            showNotice(AppText.codexConnectionVerified, kind: .success)
        }

        guard remember(event.uniqueKey) else { return }

        switch event.type {
        case .sessionStarted:
            break
        case .completed:
            cancelPendingInterventions(turnKey: event.turnKey)
            applyApprovalEffects(
                approvalCoordinator.complete(
                    sessionID: event.sessionID,
                    turnID: event.turnID
                )
            )
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
            approvalLogger.info(
                "Permission request session=\(event.sessionID, privacy: .public) turn=\(event.turnID ?? "-", privacy: .public) mode=\(self.approvalNotificationMode.rawValue, privacy: .public)"
            )
            switch approvalNotificationMode {
            case .all:
                scheduleIntervention(event)
            case .actionNeeded:
                startApprovalStateMonitor()
                applyApprovalEffects(approvalCoordinator.receive(event))
            case .none:
                break
            }
        case .questionRequested:
            scheduleIntervention(event)
        }
    }

    private func scheduleIntervention(
        _ event: CodexEvent,
        delay: Duration = .seconds(5)
    ) {
        let key = event.uniqueKey
        guard pendingInterventions[key] == nil else { return }
        pendingInterventions[key] = PendingIntervention(
            event: event,
            task: nil
        )
        armPendingIntervention(key, delay: delay)
    }

    private func armPendingIntervention(_ key: String, delay: Duration) {
        guard var pending = pendingInterventions[key] else { return }
        pending.task?.cancel()
        let task = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.deliverPendingIntervention(key)
        }
        pending.task = task
        pendingInterventions[key] = pending
    }

    private func deliverPendingIntervention(_ key: String) async {
        guard let pending = pendingInterventions.removeValue(forKey: key) else { return }

        let event = pending.event
        let title: String
        let body: String
        let taskTitle = taskTitleResolver.title(for: event.sessionID)
        switch event.type {
        case .permissionRequested:
            guard approvalNotificationMode == .all else { return }
            approvalLogger.info(
                "Delivering permission notification session=\(event.sessionID, privacy: .public) turn=\(event.turnID ?? "-", privacy: .public) mode=\(self.approvalNotificationMode.rawValue, privacy: .public)"
            )
            title = AppText.permissionNotificationTitle
            body = AppText.permissionNotificationBody(taskTitle: taskTitle)
        case .questionRequested:
            title = AppText.questionNotificationTitle
            body = AppText.questionNotificationBody(taskTitle: taskTitle)
        default:
            return
        }

        await deliver(
            PushNotification(
                title: title,
                body: body,
                urgency: .high
            ),
            for: event
        )
    }

    private func cancelPendingIntervention(_ key: String) {
        pendingInterventions.removeValue(forKey: key)?.task?.cancel()
    }

    private func cancelPendingInterventions(turnKey: String) {
        let keys = pendingInterventions.compactMap { key, pending in
            pending.event.turnKey == turnKey ? key : nil
        }
        for key in keys {
            cancelPendingIntervention(key)
        }
    }

    private func startApprovalStateMonitor() {
        guard
            approvalNotificationMode == .actionNeeded,
            !codexEventProcessingSuspended
        else {
            return
        }
        if approvalStateMonitor == nil {
            approvalStateMonitor = CodexApprovalStateMonitor(
                healthHandler: { [weak self] health in
                    Task { @MainActor in
                        self?.receiveApprovalStateHealth(health)
                    }
                },
                observationHandler: { [weak self] observations in
                    Task { @MainActor in
                        self?.receiveApprovalObservations(observations)
                    }
                }
            )
        }
        approvalStateMonitor?.start()
    }

    private func stopApprovalStateMonitor() {
        approvalStateHealth = .stopped
        approvalStateMonitor?.stop()
        approvalStateMonitor = nil
    }

    private func receiveApprovalObservations(
        _ observations: [CodexApprovalObservation]
    ) {
        guard
            approvalNotificationMode == .actionNeeded,
            !codexEventProcessingSuspended
        else {
            return
        }

        for observation in observations {
            applyApprovalEffects(approvalCoordinator.receive(observation))
        }
    }

    private func receiveApprovalStateHealth(
        _ health: CodexApprovalMonitorHealth
    ) {
        guard
            approvalNotificationMode == .actionNeeded,
            !codexEventProcessingSuspended
        else {
            return
        }
        approvalStateHealth = health
        applyApprovalEffects(approvalCoordinator.monitorHealthChanged(health))
    }

    private func applyApprovalEffects(
        _ effects: [CodexApprovalCoordinatorEffect]
    ) {
        for effect in effects {
            switch effect {
            case let .scheduleUnknownFallback(key):
                scheduleApprovalFallback(key: key)
            case let .cancelUnknownFallback(key):
                approvalFallbackTasks.removeValue(forKey: key)?.cancel()
            case let .notify(event, cause):
                beginApprovalDelivery(event: event, cause: cause)
            case let .followSession(sessionID):
                approvalStateMonitor?.follow(sessionID: sessionID)
            case let .unfollowSession(sessionID):
                approvalStateMonitor?.unfollow(sessionID: sessionID)
            }
        }
    }

    private func scheduleApprovalFallback(key: String) {
        guard approvalFallbackTasks[key] == nil else { return }
        approvalFallbackTasks[key] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self else { return }
            approvalFallbackTasks.removeValue(forKey: key)
            guard
                approvalNotificationMode == .actionNeeded,
                !codexEventProcessingSuspended
            else {
                return
            }
            applyApprovalEffects(approvalCoordinator.unknownFallbackFired(key: key))
        }
    }

    private func beginApprovalDelivery(
        event: CodexEvent,
        cause: CodexApprovalNotificationCause
    ) {
        guard
            approvalNotificationMode == .actionNeeded,
            !codexEventProcessingSuspended
        else {
            return
        }
        let taskID = UUID()
        let taskTitle = taskTitleResolver.title(for: event.sessionID)
        let body: String
        switch cause {
        case .requiresUserAction:
            body = AppText.manualApprovalNotificationBody(taskTitle: taskTitle)
        case .unknownState:
            body = AppText.permissionNotificationBody(taskTitle: taskTitle)
        }
        approvalLogger.info(
            "Delivering filtered permission notification session=\(event.sessionID, privacy: .public) turn=\(event.turnID ?? "-", privacy: .public) cause=\(String(describing: cause), privacy: .public)"
        )
        approvalDeliveryTasks[taskID] = Task { [weak self] in
            guard let self else { return }
            await deliver(
                PushNotification(
                    title: AppText.permissionNotificationTitle,
                    body: body,
                    urgency: .high
                ),
                for: event
            )
            approvalDeliveryTasks.removeValue(forKey: taskID)
        }
    }

    private func cancelApprovalDeliveries() {
        for task in approvalDeliveryTasks.values {
            task.cancel()
        }
        approvalDeliveryTasks.removeAll()
    }

    private func cancelCodexNotificationProcessing() {
        for pending in pendingInterventions.values {
            pending.task?.cancel()
        }
        pendingInterventions.removeAll()
        applyApprovalEffects(approvalCoordinator.reset())
        for task in approvalFallbackTasks.values {
            task.cancel()
        }
        approvalFallbackTasks.removeAll()
        cancelApprovalDeliveries()
        stopApprovalStateMonitor()
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
        var attemptsByChannel: [PushChannel: [DeliveryRecord.Attempt]] = [:]

        if deliveryChannels.contains(.bark) {
            do {
                targets.append(contentsOf: try barkTargets())
            } catch {
                attemptsByChannel[.bark] = [
                    DeliveryRecord.Attempt(
                        channel: .bark,
                        outcome: .failed,
                        detail: AppText.barkNotConfigured
                    )
                ]
            }
        }

        if deliveryChannels.contains(.ntfy) {
            if let target = ntfyTarget() {
                targets.append(target)
            } else {
                attemptsByChannel[.ntfy] = [
                    DeliveryRecord.Attempt(
                        channel: .ntfy,
                        outcome: .failed,
                        detail: AppText.ntfyNotConfigured
                    )
                ]
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
            attemptsByChannel[attempt.channel, default: []].append(attempt)
        }
        let attempts = PushChannel.allCases.flatMap { attemptsByChannel[$0] ?? [] }
        appendRecord(
            for: event,
            attempts: attempts,
            detail: attempts.isEmpty ? AppText.noPushChannelEnabled : nil
        )
        if event.type == .permissionRequested {
            approvalLogger.info(
                "Recorded permission notification session=\(event.sessionID, privacy: .public) turn=\(event.turnID ?? "-", privacy: .public) attempts=\(attempts.count, privacy: .public)"
            )
        }
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

    private func barkTargets() throws -> [PushDeliveryTarget] {
        let destinations = barkSettings.deliveryDestinations
        guard !destinations.isEmpty else {
            throw BarkSettingsError.configurationNotSaved
        }
        return try destinations.enumerated().map { index, destination in
            PushDeliveryTarget(
                channel: .bark,
                destinationID: destination.id,
                destinationLabel: "Bark \(index + 1) · \(destination.baseURL.host ?? "HTTPS")",
                provider: try BarkClient(
                    baseURL: destination.baseURL,
                    deviceKey: destination.deviceKey,
                    session: barkSession
                )
            )
        }
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
            showNotice(
                AppText.notificationsPartiallySent(sent: sentCount, total: attempts.count),
                kind: .error
            )
        case .failed, .skipped:
            guard let detail = attempts.first(where: { $0.outcome != .sent })?.detail else {
                return
            }
            showNotice(AppText.pushFailed(detail), kind: .error)
        }
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
