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
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 14, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.orange)
                            .frame(width: 28, height: 28)
                            .background(
                                Color.orange.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 7)
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(AppText.approvalNotifications)

                            ZStack(alignment: .topLeading) {
                                ForEach(
                                    ApprovalNotificationMode.allCases,
                                    id: \.self
                                ) { mode in
                                    Text(AppText.approvalNotificationHelp(mode))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .opacity(
                                            model.approvalNotificationMode == mode
                                                ? 1
                                                : 0
                                        )
                                        .accessibilityHidden(
                                            model.approvalNotificationMode != mode
                                        )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            ZStack(alignment: .topLeading) {
                                ForEach(approvalStateStatusCandidates, id: \.self) {
                                    status in
                                    Text(status)
                                        .font(.caption)
                                        .foregroundStyle(
                                            status == AppText.approvalStateUnavailable()
                                                ? Color.orange
                                                : Color.secondary
                                        )
                                        .fixedSize(horizontal: false, vertical: true)
                                        .opacity(
                                            model.approvalNotificationMode
                                                    == .actionNeeded
                                                && model.approvalStateStatusText == status
                                                ? 1
                                                : 0
                                        )
                                        .accessibilityHidden(
                                            model.approvalNotificationMode
                                                    != .actionNeeded
                                                || model.approvalStateStatusText != status
                                        )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { approvalSliderValue },
                                set: { model.setApprovalNotificationMode(mode(for: $0)) }
                            ),
                            in: 0...2,
                            step: 1
                        )
                        .controlSize(.large)
                        .tint(.accentColor)
                        .accessibilityLabel(AppText.approvalNotifications)
                        .accessibilityValue(
                            AppText.approvalNotificationModeLabel(
                                model.approvalNotificationMode
                            )
                        )

                        HStack(spacing: 0) {
                            ForEach(
                                Array(ApprovalNotificationMode.allCases.enumerated()),
                                id: \.element
                            ) { index, mode in
                                Text(AppText.approvalNotificationModeLabel(mode))
                                    .font(.caption)
                                    .fontWeight(
                                        model.approvalNotificationMode == mode
                                            ? .semibold
                                            : .regular
                                    )
                                    .foregroundStyle(
                                        model.approvalNotificationMode == mode
                                            ? Color.accentColor
                                            : Color.secondary
                                    )
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: approvalLabelAlignment(index)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
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

    private var approvalSliderValue: Double {
        Double(
            ApprovalNotificationMode.allCases.firstIndex(
                of: model.approvalNotificationMode
            ) ?? 0
        )
    }

    private var approvalStateStatusCandidates: [String] {
        [
            AppText.approvalStateConnectToUse(),
            AppText.approvalStateChecking(),
            AppText.approvalStateReady(),
            AppText.approvalStateUnavailable(),
        ]
    }

    private func mode(for sliderValue: Double) -> ApprovalNotificationMode {
        let index = min(
            max(Int(sliderValue.rounded()), 0),
            ApprovalNotificationMode.allCases.count - 1
        )
        return ApprovalNotificationMode.allCases[index]
    }

    private func approvalLabelAlignment(_ index: Int) -> Alignment {
        switch index {
        case 0:
            .leading
        case ApprovalNotificationMode.allCases.count - 1:
            .trailing
        default:
            .center
        }
    }
}
