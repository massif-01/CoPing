import CoPingCore
import Foundation

enum HelperInstallerError: LocalizedError {
    case bundledHelperMissing
    case signatureInvalid

    var errorDescription: String? {
        switch self {
        case .bundledHelperMissing:
            return AppText.bundledHelperMissing
        case .signatureInvalid:
            return AppText.helperSignatureInvalid
        }
    }
}

struct HelperInstaller {
    let destinationURL: URL
    private let fileManager = FileManager.default

    init(destinationURL: URL = CoPingPaths.installedHelper()) {
        self.destinationURL = destinationURL
    }

    func install() throws {
        let source = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("CoPingHook", isDirectory: false)
        guard fileManager.isExecutableFile(atPath: source.path) else {
            throw HelperInstallerError.bundledHelperMissing
        }

        let directory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".CoPingHook-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: source, to: temporary)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: temporary.path
        )
        guard verifySignature(at: temporary) else {
            throw HelperInstallerError.signatureInvalid
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporary, to: destinationURL)
    }

    func uninstall() throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
    }

    private func verifySignature(at url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--strict", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
