import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Label(model.menuStatusText, systemImage: statusIcon)
            .foregroundStyle(statusColor)

        Divider()

        Button(model.notificationsEnabled ? "暂停通知" : "恢复通知") {
            model.setNotificationsEnabled(!model.notificationsEnabled)
        }

        Button("发送测试通知") {
            model.sendTestNotification()
        }
        .disabled(!model.hasBarkConfiguration || model.isBusy)

        SettingsLink {
            Text("设置…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("退出 CoPing") {
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
