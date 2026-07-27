import AppKit
import CoPingCore
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("CoPing")
                        .font(.headline)
                    Text(AppText.menuSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(AppText.connectionSection)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.menuStatusText)
                        .font(.body.weight(.medium))
                }

                Spacer()
            }
            .padding(.vertical, 4)

            menuActions

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
        .frame(width: 310)
    }

    @ViewBuilder
    private var menuActions: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                actionButtons
            }
        } else {
            actionButtons
        }
    }

    private var actionButtons: some View {
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

            Button {
                openSettings()
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label(AppText.settings, systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .copingSecondaryButtonStyle()
            .keyboardShortcut(",", modifiers: .command)
        }
        .controlSize(.regular)
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
