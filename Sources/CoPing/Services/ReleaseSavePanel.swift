import AppKit
import CoPingCore
import UniformTypeIdentifiers

@MainActor
enum ReleaseSavePanel {
    static func chooseDestination(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = AppText.chooseDownloadLocation
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
