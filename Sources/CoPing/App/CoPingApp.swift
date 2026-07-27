import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var qaWindow: NSWindow?
    private var qaModel: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("--show-settings") else { return }
        NSApp.setActivationPolicy(.regular)
        let model = AppModel(startServices: false)
        let controller = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: controller)
        window.title = "CoPing 设置"
        window.setContentSize(NSSize(width: 560, height: 420))
        window.center()
        window.makeKeyAndOrderFront(nil)
        qaModel = model
        qaWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct CoPingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Image(nsImage: Self.menuBarImage)
                .accessibilityLabel("CoPing")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }

    private static let menuBarImage: NSImage = {
        guard
            let url = Bundle.main.url(
                forResource: "CoPing-orbit-mark",
                withExtension: "svg"
            ),
            let image = NSImage(contentsOf: url)
        else {
            fatalError("Missing CoPing menu bar icon resource")
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}
