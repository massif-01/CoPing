import AppKit
import CoPingCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
            .accessibilityLabel(AppText.settingsSidebarAccessibilityLabel)
        } detail: {
            detailView
                .navigationTitle(selection.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(WindowTitleUpdater(title: AppText.settingsWindowTitle))
        .safeAreaInset(edge: .bottom) {
            if let message = model.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(.regularMaterial)
            }
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
