import Foundation

/// Opt-in data root for isolated instances. macOS Foundation ignores a shell's
/// HOME override; every app-owned path must share this explicit root instead.
enum FinePaths {
    static var home: URL { home(environment: ProcessInfo.processInfo.environment) }

    static func codexHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home(environment: environment).appendingPathComponent(".codex")
    }

    static func home(environment: [String: String]) -> URL {
        if let root = environment["FINE_HOME"], root.hasPrefix("/"), !root.contains("\0") {
            return URL(fileURLWithPath: root, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
