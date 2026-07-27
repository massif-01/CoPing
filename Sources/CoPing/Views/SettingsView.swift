import CoPingCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label("通用", systemImage: "gearshape") }

            BarkSettingsView(model: model)
                .tabItem { Label("Bark", systemImage: "iphone.radiowaves.left.and.right") }

            CodexSettingsView(model: model)
                .tabItem { Label("Codex", systemImage: "terminal") }

            HistorySettingsView(model: model)
                .tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }
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
            Section("通知") {
                Toggle(
                    "启用 CoPing 通知",
                    isOn: Binding(
                        get: { model.notificationsEnabled },
                        set: { model.setNotificationsEnabled($0) }
                    )
                )
                Text("关闭后仍会接收 Codex 事件，但不会发送到 Bark。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("启动") {
                Toggle(
                    "登录 Mac 时自动启动",
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
            }

            Section("版本范围") {
                LabeledContent("支持事件", value: "完成、权限请求、普通问题")
                LabeledContent("执行失败", value: "v1 暂不支持")
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
            Section("服务") {
                TextField("HTTPS 服务地址", text: $model.baseURLString)
                    .textFieldStyle(.roundedBorder)
                Text("默认 https://api.day.app；自建服务也必须使用 HTTPS。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("设备") {
                SecureField("Device Key 或完整 Bark 地址", text: $model.deviceKey)
                    .textFieldStyle(.roundedBorder)
                Text("可直接粘贴 Bark 复制的完整推送地址；CoPing 会自动提取 Device Key 并保存到 macOS 钥匙串。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("保存") {
                    model.saveBarkSettings()
                }
                Button("保存并发送测试通知") {
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
            Section("检测") {
                LabeledContent("ChatGPT.app") {
                    Label(
                        model.codexDetected ? "已检测到" : "未检测到",
                        systemImage: model.codexDetected ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(model.codexDetected ? .green : .red)
                }
                LabeledContent("连接状态", value: model.connectionStatus.rawValue)
            }

            Section("首次连接") {
                Text("CoPing 会安装用户级 Hook，然后打开一次终端。请在 Codex 中输入 /hooks，检查 CoPingHook 路径并选择信任全部。")
                    .font(.callout)
                Text("完成后退出终端并新建一个 Codex 桌面任务；收到 SessionStart 后会自动显示“已连接”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(model.connectionStatus == .disconnected ? "连接 Codex" : "修复连接") {
                    model.connectCodex()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || !model.codexDetected)

                Button("重新打开审核终端") {
                    model.openHookReview()
                }
                .disabled(!model.codexDetected)

                Spacer()

                Button("断开连接", role: .destructive) {
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
                    "暂无通知记录",
                    systemImage: "bell.slash",
                    description: Text("这里只记录事件类型、项目名和发送结果。")
                )
            } else {
                List(model.records) { record in
                    HStack {
                        Image(systemName: icon(for: record.outcome))
                            .foregroundStyle(color(for: record.outcome))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(eventName(record.eventType)) · \(record.projectName)")
                            if let detail = record.detail {
                                Text(detail)
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
                Text("最多保留最近 100 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空记录", role: .destructive) {
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
        case .sessionStarted: return "连接"
        case .completed: return "完成"
        case .permissionRequested: return "权限请求"
        case .questionRequested: return "普通问题"
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
