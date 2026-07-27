import CoPingCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label(AppText.generalTab, systemImage: "gearshape") }

            BarkSettingsView(model: model)
                .tabItem { Label("Bark", systemImage: "iphone.radiowaves.left.and.right") }

            CodexSettingsView(model: model)
                .tabItem { Label("Codex", systemImage: "terminal") }

            HistorySettingsView(model: model)
                .tabItem { Label(AppText.historyTab, systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 560, height: 420)
        .overlay(alignment: .bottom) {
            if let message = model.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section(AppText.notificationsSection) {
                Toggle(
                    AppText.enableNotifications,
                    isOn: Binding(
                        get: { model.notificationsEnabled },
                        set: { model.setNotificationsEnabled($0) }
                    )
                )
                Text(AppText.notificationsDisabledHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppText.startupSection) {
                Toggle(
                    AppText.launchAtLogin,
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
            }

            Section(AppText.versionScopeSection) {
                LabeledContent(AppText.supportedEventsLabel, value: AppText.supportedEventsValue)
                LabeledContent(AppText.executionFailureLabel, value: AppText.notSupportedInV1)
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 28)
    }
}

private struct BarkSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section(AppText.serviceSection) {
                TextField(AppText.httpsServerAddress, text: $model.baseURLString)
                    .textFieldStyle(.roundedBorder)
                Text(AppText.barkServerHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppText.deviceSection) {
                SecureField(AppText.deviceKeyOrURL, text: $model.deviceKey)
                    .textFieldStyle(.roundedBorder)
                Text(AppText.deviceKeyHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(AppText.save) {
                    model.saveBarkSettings()
                }
                Button(AppText.saveAndSendTest) {
                    model.sendTestNotification()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 28)
    }
}

private struct CodexSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section(AppText.detectionSection) {
                LabeledContent("ChatGPT.app") {
                    Label(
                        model.codexDetected ? AppText.detected : AppText.notDetected,
                        systemImage: model.codexDetected ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(model.codexDetected ? .green : .red)
                }
                LabeledContent(AppText.connectionStatusLabel, value: model.connectionStatus.label)
            }

            Section(AppText.firstConnectionSection) {
                Text(AppText.firstConnectionHelp)
                    .font(.callout)
                Text(AppText.firstConnectionVerificationHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(
                    model.connectionStatus == .disconnected
                        ? AppText.connectCodex
                        : AppText.repairConnection
                ) {
                    model.connectCodex()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || !model.codexDetected)

                Button(AppText.reopenReviewTerminal) {
                    model.openHookReview()
                }
                .disabled(!model.codexDetected)

                Spacer()

                Button(AppText.disconnect, role: .destructive) {
                    model.disconnectCodex()
                }
                .disabled(model.connectionStatus == .disconnected)
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 28)
    }
}

private struct HistorySettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.records.isEmpty {
                ContentUnavailableView(
                    AppText.noNotificationHistory,
                    systemImage: "bell.slash",
                    description: Text(AppText.historyPrivacyHelp)
                )
            } else {
                List(model.records) { record in
                    HStack {
                        Image(systemName: icon(for: record.outcome))
                            .foregroundStyle(color(for: record.outcome))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(eventName(record.eventType)) · \(record.projectName)")
                            if let detail = record.detail {
                                Text(AppText.localizedHistoryDetail(detail))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(record.timestamp, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            HStack {
                Text(AppText.historyLimit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(AppText.clearHistory, role: .destructive) {
                    model.clearHistory()
                }
                .disabled(model.records.isEmpty)
            }
            .padding(12)
        }
        .padding(.bottom, 28)
    }

    private func eventName(_ type: CodexEvent.EventType) -> String {
        switch type {
        case .sessionStarted: return AppText.connectionEvent
        case .completed: return AppText.completionEvent
        case .permissionRequested: return AppText.permissionEvent
        case .questionRequested: return AppText.questionEvent
        }
    }

    private func icon(for outcome: DeliveryRecord.Outcome) -> String {
        switch outcome {
        case .sent: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }

    private func color(for outcome: DeliveryRecord.Outcome) -> Color {
        switch outcome {
        case .sent: return .green
        case .failed: return .red
        case .skipped: return .secondary
        }
    }
}
