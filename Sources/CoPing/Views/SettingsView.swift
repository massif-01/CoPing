import AppKit
import CoPingCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)

                    Text("CoPing")
                        .font(.headline)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 10)

                List(SettingsSection.allCases, selection: $selection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
                .listStyle(.sidebar)
                .accessibilityLabel(AppText.settingsSidebarAccessibilityLabel)
            }
            .navigationSplitViewColumnWidth(168)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .copingSettingsToolbar()
        .frame(width: 760, height: 500)
        .background(WindowTitleUpdater(title: AppText.settingsWindowTitle))
        .overlay(alignment: .topTrailing) {
            if let notice = model.notice {
                SettingsNoticeView(notice: notice) {
                    model.dismissNotice(id: notice.id)
                }
                .padding(20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.notice?.id)
        .task(id: model.notice?.id) {
            guard
                let notice = model.notice,
                notice.kind != .error
            else {
                return
            }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            model.dismissNotice(id: notice.id)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            GeneralSettingsView(model: model)
        case .bark:
            BarkSettingsView(model: model)
        case .codex:
            CodexSettingsView(model: model)
        case .history:
            HistorySettingsView(model: model)
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case bark
    case codex
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: AppText.generalTab
        case .bark: "Bark"
        case .codex: "Codex"
        case .history: AppText.historyTab
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .bark: "iphone.radiowaves.left.and.right"
        case .codex: "terminal"
        case .history: "clock.arrow.circlepath"
        }
    }
}

private struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        updateWindowTitle(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        updateWindowTitle(from: view)
    }

    private func updateWindowTitle(from view: NSView) {
        DispatchQueue.main.async {
            view.window?.title = title
        }
    }
}
