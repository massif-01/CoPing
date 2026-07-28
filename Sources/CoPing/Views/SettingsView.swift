import AppKit
import CoPingCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var updateModel = UpdateModel()
    @State private var selection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 8) {
            sidebar

            detailView
                .padding(.top, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .ignoresSafeArea(.container, edges: .top)
        .modifier(SettingsWindowSurface())
        .animation(.snappy, value: model.notice?.id)
        .frame(
            minWidth: 760,
            idealWidth: 840,
            maxWidth: .infinity,
            minHeight: 560,
            idealHeight: 760,
            maxHeight: .infinity
        )
        .modifier(SettingsWindowInteractions())
        .overlay(alignment: .topTrailing) {
            if let notice = model.notice {
                SettingsNoticeView(notice: notice) {
                    model.dismissNotice(id: notice.id)
                }
                .padding(.top, 10)
                .padding(.trailing, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(SettingsWindowCapabilities())
    }

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: $selection) { section in
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .padding(.top, 42)
        .accessibilityLabel(AppText.settingsSidebarAccessibilityLabel)
        .frame(width: 215)
        .modifier(SettingsSidebarSurface())
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                Divider()
                    .padding(.horizontal, 12)

                GitHubProjectLink()
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
        case .ntfy:
            NtfySettingsView(model: model)
        case .codex:
            CodexSettingsView(model: model)
        case .history:
            HistorySettingsView(model: model)
        case .version:
            VersionSettingsView(updateModel: updateModel)
        }
    }
}

private struct SettingsSidebarSurface: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: 22)
                )
        } else {
            content
                .background(.regularMaterial, in: shape)
                .clipShape(shape)
        }
    }
}

private struct SettingsWindowSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .containerBackground(
                    Color(nsColor: .controlBackgroundColor),
                    for: .window
                )
        } else {
            content
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

private struct GitHubProjectLink: View {
    private static let projectURL = URL(
        string: "https://github.com/massif-01/CoPing"
    )!

    var body: some View {
        Link(destination: Self.projectURL) {
            HStack(spacing: 7) {
                GitHubMark()

                Text("© massif-01")

                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("GitHub · massif-01/CoPing")
        .accessibilityLabel("GitHub: massif-01/CoPing")
    }
}

private struct GitHubMark: View {
    private static let image: NSImage? = {
        guard
            let url = Bundle.main.url(
                forResource: "GitHubMark",
                withExtension: "svg"
            ),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.isTemplate = true
        return image
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
        } else {
            Image(systemName: "link")
                .frame(width: 13, height: 13)
        }
    }
}

private struct SettingsWindowInteractions: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .windowMinimizeBehavior(.enabled)
                .windowResizeBehavior(.enabled)
                .windowFullScreenBehavior(.enabled)
        } else {
            content
        }
    }
}

private struct SettingsWindowCapabilities: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowCapabilityView {
        WindowCapabilityView()
    }

    func updateNSView(_ view: WindowCapabilityView, context: Context) {
        view.configureWindow()
    }
}

private final class WindowCapabilityView: NSView {
    private static let toolbarIdentifier = NSToolbar.Identifier(
        "com.coping.settings.toolbar"
    )

    private var windowObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }

        if let window {
            windowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.configureWindow()
            }
        }

        configureWindow()
    }

    func configureWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }

            if window.toolbar?.identifier != Self.toolbarIdentifier {
                let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
                toolbar.allowsUserCustomization = false
                toolbar.autosavesConfiguration = false
                toolbar.displayMode = .iconOnly
                toolbar.showsBaselineSeparator = false
                window.toolbar = toolbar
            }
            if window.toolbarStyle != .unified {
                window.toolbarStyle = .unified
            }
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }

            if !window.styleMask.contains(.miniaturizable) {
                window.styleMask.insert(.miniaturizable)
            }
            if !window.styleMask.contains(.resizable) {
                window.styleMask.insert(.resizable)
            }
            if #unavailable(macOS 15.0) {
                var collectionBehavior = window.collectionBehavior
                collectionBehavior.remove([
                    .fullScreenNone,
                    .fullScreenAuxiliary,
                ])
                collectionBehavior.insert(.fullScreenPrimary)
                if window.collectionBehavior != collectionBehavior {
                    window.collectionBehavior = collectionBehavior
                }
            }

            let minimumSize = NSSize(width: 760, height: 560)
            let maximumSize = NSSize(width: 10_000, height: 10_000)
            if window.minSize != minimumSize {
                window.minSize = minimumSize
            }
            if window.maxSize != maximumSize {
                window.maxSize = maximumSize
            }
            if window.contentMinSize != minimumSize {
                window.contentMinSize = minimumSize
            }
            if window.contentMaxSize != maximumSize {
                window.contentMaxSize = maximumSize
            }

            if let button = window.standardWindowButton(.miniaturizeButton),
               !button.isEnabled {
                button.isEnabled = true
            }
            if let button = window.standardWindowButton(.zoomButton) {
                button.isEnabled = true
                button.needsDisplay = true
            }
        }
    }

    deinit {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case bark
    case ntfy
    case codex
    case history
    case version

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: AppText.generalTab
        case .bark: "Bark"
        case .ntfy: "ntfy"
        case .codex: "Codex"
        case .history: AppText.historyTab
        case .version: AppText.versionTab
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .bark: "iphone.radiowaves.left.and.right"
        case .ntfy: "bell.badge.fill"
        case .codex: "terminal"
        case .history: "clock.arrow.circlepath"
        case .version: "arrow.triangle.2.circlepath"
        }
    }
}
