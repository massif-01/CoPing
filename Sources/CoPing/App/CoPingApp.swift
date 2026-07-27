import AppKit
import CoPingCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("--show-settings") else { return }
        NSApp.setActivationPolicy(.regular)
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
            MenuBarLabel(image: Self.menuBarImage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
        .defaultSize(width: 840, height: 656)
        .windowResizability(.automatic)
        .windowToolbarStyle(.unified(showsTitle: false))
    }

    private static let menuBarImage: NSImage = {
        guard
            let url = Bundle.main.url(
                forResource: "CoPing-orbit-mark",
                withExtension: "svg"
            ),
            let mark = NSImage(contentsOf: url)
        else {
            fatalError("Missing CoPing menu bar icon resource")
        }

        let size = NSSize(width: 18.8568, height: 18.8568)
        let visualScale = 0.95
        let visualInset = size.width * (1 - visualScale) / 2
        let image = NSImage(size: size, flipped: false) { bounds in
            let visualBounds = bounds.insetBy(dx: visualInset, dy: visualInset)
            let outerShape = NSBezierPath(
                roundedRect: visualBounds.insetBy(
                    dx: 0.6 * visualScale,
                    dy: 0.6 * visualScale
                ),
                xRadius: 4.8 * visualScale,
                yRadius: 4.8 * visualScale
            )
            NSColor.black.setFill()
            outerShape.fill()

            let sourceScale = 0.95
            let inset = visualBounds.width * (1 - sourceScale) / 2
            mark.draw(
                in: visualBounds.insetBy(dx: inset, dy: inset),
                from: .zero,
                operation: .destinationOut,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return true
        }

        image.isTemplate = true
        return image
    }()
}

private struct MenuBarLabel: View {
    let image: NSImage

    @Environment(\.openSettings) private var openSettings
    @State private var didOpenSettingsForQA = false

    var body: some View {
        Image(nsImage: image)
            .accessibilityLabel("CoPing")
            .task {
                guard
                    ProcessInfo.processInfo.arguments.contains("--show-settings"),
                    !didOpenSettingsForQA
                else {
                    return
                }

                didOpenSettingsForQA = true
                openSettings()

                try? await Task.sleep(for: .milliseconds(100))
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.windows
                    .first {
                        $0.isVisible
                            && $0.styleMask.contains(.titled)
                            && !($0 is NSPanel)
                    }?
                    .makeKeyAndOrderFront(nil)
            }
    }
}
