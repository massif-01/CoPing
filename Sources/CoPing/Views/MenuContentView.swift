import AppKit
import CoPingCore
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("CoPing")
                        .font(.headline)
                    Text(AppText.menuSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            GlassCard {
                HStack(spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(statusColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppText.connectionSection)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(model.menuStatusText)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                    }

                    Spacer()
                }
            }

            HStack(spacing: 10) {
                Button {
                    model.setNotificationsEnabled(!model.notificationsEnabled)
                } label: {
                    Label(
                        model.notificationsEnabled
                            ? AppText.pauseNotifications
                            : AppText.resumeNotifications,
                        systemImage: model.notificationsEnabled
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .copingSecondaryButtonStyle()

                SettingsLink {
                    Label(AppText.settings, systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .copingPrimaryButtonStyle()
                .keyboardShortcut(",", modifiers: .command)
            }
            .controlSize(.large)

            Divider()

            HStack {
                Text("CoPing \(AppVersion.current)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(AppText.quitCoPing) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(16)
        .frame(width: 330)
        .background(.ultraThinMaterial)
    }

    private var statusIcon: String {
        if !model.notificationsEnabled {
            return "pause.circle.fill"
        }

        switch model.connectionStatus {
        case .connected:
            return "checkmark.circle.fill"
        case .awaitingVerification, .disconnected, .error:
            return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        if !model.notificationsEnabled {
            return Color(nsColor: .systemYellow)
        }
        return model.connectionStatus == .connected
            ? Color(nsColor: .systemGreen)
            : Color(nsColor: .systemRed)
    }
}
