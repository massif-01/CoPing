import AppKit
import CoPingCore
import SwiftUI

struct CodexSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPage("Codex") {
            Form {
                Section(AppText.detectionSection) {
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

                    LabeledContent(AppText.connectionStatusLabel) {
                        Label(
                            model.connectionStatus.label,
                            systemImage: connectionIcon
                        )
                        .foregroundStyle(connectionColor)
                    }
                }

                Section(AppText.firstConnectionSection) {
                    Text(AppText.firstConnectionHelp)
                        .font(.callout)

                    Text(AppText.firstConnectionVerificationHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
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
                    .controlSize(.regular)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
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
