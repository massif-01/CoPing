import AppKit
import CoPingCore
import SwiftUI

struct CodexSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPage(
            "Codex",
            subtitle: AppText.codexSettingsDescription,
            systemImage: "terminal.fill",
            tint: .indigo
        ) {
            SettingsCard {
                SettingsRow(
                    systemImage: "apps.iphone",
                    tint: model.codexDetected ? .green : .red,
                    title: "ChatGPT.app"
                ) {
                    Label(
                        model.codexDetected
                            ? AppText.detected
                            : AppText.notDetected,
                        systemImage: model.codexDetected
                            ? "checkmark.circle.fill"
                            : "xmark.circle.fill"
                    )
                    .foregroundStyle(
                        model.codexDetected
                            ? Color(nsColor: .systemGreen)
                            : Color(nsColor: .systemRed)
                    )
                }

                SettingsCardDivider()

                SettingsRow(
                    systemImage: connectionIcon,
                    tint: connectionColor,
                    title: AppText.connectionStatusLabel
                ) {
                    Label(
                        model.connectionStatus.label,
                        systemImage: connectionIcon
                    )
                    .foregroundStyle(connectionColor)
                }
            }

            if model.connectionStatus == .awaitingVerification {
                SettingsCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.orange)
                            .frame(width: 28, height: 28)
                            .background(
                                Color.orange.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 7)
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(AppText.awaitingVerificationTitle)
                                .fontWeight(.medium)

                            Text(AppText.awaitingVerificationHelp)
                                .font(.callout)

                            Text(AppText.firstConnectionVerificationHelp)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(AppText.awaitingVerificationTroubleshooting)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(12)
                }
            }

            SettingsCard {
                SettingsRow(
                    systemImage: "bell.slash.fill",
                    tint: .orange,
                    title: AppText.ignorePermissionNotifications,
                    subtitle: AppText.ignorePermissionNotificationsHelp
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.ignorePermissionNotifications },
                            set: { model.setIgnorePermissionNotifications($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(AppText.ignorePermissionNotifications)
                }
            }

            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.indigo)
                        .frame(width: 28, height: 28)
                        .background(
                            Color.indigo.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7)
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppText.firstConnectionSection)
                            .fontWeight(.medium)

                        Text(AppText.firstConnectionHelp)
                            .font(.callout)

                        Text(AppText.firstConnectionVerificationHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(12)
            }

            HStack {
                Button {
                    model.connectCodex()
                } label: {
                    Text(
                        model.connectionStatus == .disconnected
                            ? AppText.connectCodex
                            : AppText.repairConnection
                    )
                    .foregroundStyle(.white)
                }
                .copingPrimaryButtonStyle()
                .disabled(model.isBusy || !model.codexDetected)

                Button(AppText.reopenReviewTerminal) {
                    model.openHookReview()
                }
                .copingSecondaryButtonStyle()
                .disabled(!model.codexDetected)

                Spacer()

                Button(AppText.disconnect, role: .destructive) {
                    model.disconnectCodex()
                }
                .copingSecondaryButtonStyle()
                .disabled(model.connectionStatus == .disconnected)
            }
            .controlSize(.regular)
            .padding(.horizontal, 4)
        }
    }

    private var connectionIcon: String {
        switch model.connectionStatus {
        case .connected:
            "checkmark.circle.fill"
        case .awaitingVerification:
            "clock.fill"
        case .disconnected:
            "xmark.circle.fill"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }

    private var connectionColor: Color {
        switch model.connectionStatus {
        case .connected:
            Color(nsColor: .systemGreen)
        case .awaitingVerification:
            Color(nsColor: .systemOrange)
        case .disconnected, .error:
            Color(nsColor: .systemRed)
        }
    }
}
