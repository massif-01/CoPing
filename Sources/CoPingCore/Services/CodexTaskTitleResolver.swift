import Foundation
import SQLite3

public struct CodexTaskTitleResolver {
    private let codexDirectory: URL
    private let fileManager: FileManager

    public init(
        codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.codexDirectory = codexDirectory
        self.fileManager = fileManager
    }

    public func title(for sessionID: String) -> String? {
        guard !sessionID.isEmpty else { return nil }

        for databaseURL in stateDatabaseURLs() {
            if let title = title(for: sessionID, in: databaseURL) {
                return title
            }
        }
        return nil
    }

    private func stateDatabaseURLs() -> [URL] {
        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: codexDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return urls.compactMap { url -> (version: Int, url: URL)? in
            let name = url.lastPathComponent
            guard
                name.hasPrefix("state_"),
                name.hasSuffix(".sqlite"),
                let version = Int(name.dropFirst(6).dropLast(7))
            else {
                return nil
            }
            return (version, url)
        }
        .sorted { $0.version > $1.version }
        .map(\.url)
    }

    private func title(for sessionID: String, in databaseURL: URL) -> String? {
        var database: OpaquePointer?
        guard
            sqlite3_open_v2(
                databaseURL.path,
                &database,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
                nil
            ) == SQLITE_OK,
            let database
        else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                database,
                "SELECT title FROM threads WHERE id = ? LIMIT 1",
                -1,
                &statement,
                nil
            ) == SQLITE_OK,
            let statement
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard
            sqlite3_bind_text(statement, 1, sessionID, -1, sqliteTransient) == SQLITE_OK,
            sqlite3_step(statement) == SQLITE_ROW,
            let text = sqlite3_column_text(statement, 0)
        else {
            return nil
        }

        let title = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
