import AppKit
import CoPingCore
import SwiftUI

struct NtfySettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPage(
            "NTFY",
            subtitle: AppText.ntfySettingsDescription,
            systemImage: "bell.badge.fill",
            tint: .purple
        ) {
            SettingsCard {
                SettingsRow(
                    systemImage: "bell.fill",
                    tint: .purple,
                    title: AppText.enableNtfy,
                    subtitle: AppText.enableNtfyHelp
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.ntfyEnabled },
                            set: { model.setNtfyEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(AppText.enableNtfy)
                    .disabled(model.isBusy)
                }

                SettingsCardDivider()

                SettingsRow(
                    systemImage: "network",
                    tint: .blue,
                    title: AppText.ntfyOfficialService,
                    subtitle: AppText.ntfyOfficialServiceHelp
                ) {
                    Text("https://ntfy.sh")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(width: 280, alignment: .trailing)
                }

                SettingsCardDivider()

                SettingsRow(
                    systemImage: "key.fill",
                    tint: .orange,
                    title: AppText.ntfyTopic,
                    subtitle: AppText.ntfyTopicHelp
                ) {
                    HStack(spacing: 4) {
                        TextField(
                            "",
                            text: Binding(
                                get: { model.ntfyTopic },
                                set: { _ in }
                            )
                        )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .allowsHitTesting(false)
                            .accessibilityLabel(
                                "\(AppText.ntfyTopic): \(model.ntfyTopic)"
                            )

                        Button {
                            model.copyNtfyTopic()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(TopicIconButtonStyle())
                        .help(AppText.copyNtfyTopic)
                        .accessibilityLabel(AppText.copyNtfyTopic)
                        .disabled(model.isBusy)

                        Button {
                            model.regenerateNtfyTopic()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(TopicIconButtonStyle())
                        .help(AppText.regenerateNtfyTopic)
                        .accessibilityLabel(AppText.regenerateNtfyTopic)
                        .disabled(model.isBusy)
                    }
                    .frame(width: 280)
                }
            }

            HStack {
                Spacer()

                Button(AppText.save) {
                    model.saveNtfySettings()
                }
                .copingSecondaryButtonStyle()
                .disabled(model.isBusy)

                Button {
                    model.sendNtfyTestNotification()
                } label: {
                    Text(AppText.saveAndSendTest)
                        .foregroundStyle(.white)
                }
                .copingPrimaryButtonStyle()
                .disabled(model.isBusy)
            }
            .controlSize(.regular)
            .padding(.horizontal, 4)
        }
    }
}

private struct TopicIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let isEmphasized = isHovered || configuration.isPressed

        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(
                Color.primary.opacity(
                    isEnabled ? (isEmphasized ? 0.9 : 0.7) : 0.3
                )
            )
            .frame(width: 26, height: 26)
            .background {
                shape.fill(
                    Color.primary.opacity(
                        isEnabled
                            ? (configuration.isPressed
                                ? 0.13
                                : (isHovered ? 0.085 : 0.045))
                            : 0.025
                    )
                )
            }
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(
                        isEnabled
                            ? (configuration.isPressed
                                ? 0.16
                                : (isHovered ? 0.12 : 0.07))
                            : 0.04
                    ),
                    lineWidth: 0.5
                )
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}
