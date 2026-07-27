import AppKit
import CoPingCore
import SwiftUI

struct CodexSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(spacing: 12) {
                        LabeledContent("ChatGPT.app") {
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

                        Divider()

                        LabeledContent(AppText.connectionStatusLabel) {
                            Label(
                                model.connectionStatus.label,
                                systemImage: connectionIcon
                            )
                            .foregroundStyle(connectionColor)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            AppText.firstConnectionSection,
                            systemImage: "link"
                        )
                        .font(.headline)

                        Text(AppText.firstConnectionHelp)
                            .font(.callout)

                        Text(AppText.firstConnectionVerificationHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button(
                        model.connectionStatus == .disconnected
                            ? AppText.connectCodex
                            : AppText.repairConnection
                    ) {
                        model.connectCodex()
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
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private var connectionIcon: String {
        model.connectionStatus == .connected
            ? "checkmark.circle.fill"
            : "xmark.circle.fill"
    }

    private var connectionColor: Color {
        model.connectionStatus == .connected
            ? Color(nsColor: .systemGreen)
            : Color(nsColor: .systemRed)
    }
}
