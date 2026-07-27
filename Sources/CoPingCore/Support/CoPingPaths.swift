import Darwin
import Foundation

public enum CoPingPaths {
    public static func applicationSupport(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("CoPing", isDirectory: true)
    }

    public static func installedHelper(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        applicationSupport(homeDirectory: homeDirectory)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("CoPingHook", isDirectory: false)
    }

    public static func historyFile(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        applicationSupport(homeDirectory: homeDirectory)
            .appendingPathComponent("history.json", isDirectory: false)
    }

    public static func configurationFile(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        applicationSupport(homeDirectory: homeDirectory)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    public static func socketPath(userID: uid_t = getuid()) -> String {
        "/tmp/coping-\(userID).sock"
    }

    public static func hooksFile(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json", isDirectory: false)
    }
}
