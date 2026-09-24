import Foundation

public enum HelperInstallerError: LocalizedError {
    case bundledHelperMissing
    case signatureInvalid

    public var errorDescription: String? {
        switch self {
        case .bundledHelperMissing:
            return AppText.bundledHelperMissing
        case .signatureInvalid:
            return AppText.helperSignatureInvalid
        }
    }
}

public struct HelperInstaller {
    public let destinationURL: URL
    private let sourceURL: URL
    private let signatureVerifier: (URL) -> Bool
    private let fileManager = FileManager.default

    public init(destinationURL: URL = CoPingPaths.installedHelper(),
                sourceURL: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CoPingHook"),
                signatureVerifier: @escaping (URL) -> Bool = HelperInstaller.verifySignature) {
        self.destinationURL = destinationURL
        self.sourceURL = sourceURL
        self.signatureVerifier = signatureVerifier
    }

    public func install() throws {
        let source = sourceURL
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
        guard signatureVerifier(temporary) else {
            throw HelperInstallerError.signatureInvalid
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            if try Data(contentsOf: destinationURL) == Data(contentsOf: temporary) { return }
            // Atomic replacement retains the installed helper if replacement fails.
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporary,
                                             backupItemName: "CoPingHook.previous-\(UUID().uuidString)",
                                             options: [.withoutDeletingBackupItem])
        } else {
            try fileManager.moveItem(at: temporary, to: destinationURL)
        }
    }

    public func uninstall() throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
    }

    public static func verifySignature(at url: URL) -> Bool {
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
