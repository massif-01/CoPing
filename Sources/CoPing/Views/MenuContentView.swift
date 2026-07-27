import AppKit
import CoPingCore
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Label(model.menuStatusText, systemImage: statusIcon)
            .foregroundStyle(statusColor)

        Divider()

        Button(model.notificationsEnabled ? AppText.pauseNotifications : AppText.resumeNotifications) {
            model.setNotificationsEnabled(!model.notificationsEnabled)
        }

        Button(AppText.sendTestNotification) {
            model.sendTestNotification()
        }
        .disabled(!model.hasBarkConfiguration || model.isBusy)

        SettingsLink {
            Text(AppText.settings)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(AppText.quitCoPing) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var statusIcon: String {
        switch model.connectionStatus {
        case .connected:
            return model.notificationsEnabled ? "checkmark.circle.fill" : "pause.circle"
        case .awaitingVerification:
            return "clock"
        case .disconnected:
            return "link.badge.plus"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        model.connectionStatus == .error ? .red : .primary
    }
}
