import Foundation

final class QuickSessionConfigurationStorage {
    static let shared = QuickSessionConfigurationStorage()

    private let fileManager: FileManager
    private let stateFile: URL
    private var configurations: [String: QuickSessionConfiguration]

    init(fileManager: FileManager = .default, stateFile: URL? = nil) {
        self.fileManager = fileManager
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".fine", isDirectory: true)
        self.stateFile = stateFile
            ?? directory.appendingPathComponent("quick-session-configurations.json")
        try? fileManager.createDirectory(
            at: self.stateFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        configurations = (try? Data(contentsOf: self.stateFile))
            .flatMap {
                try? JSONDecoder().decode(
                    [String: QuickSessionConfiguration].self,
                    from: $0
                )
            } ?? [:]
    }

    func configuration(for sessionID: String) -> QuickSessionConfiguration? {
        guard let key = QuickSessionIdentifier.storageKey(sessionID) else { return nil }
        return configurations[key]
    }

    func saveIfAbsent(_ configuration: QuickSessionConfiguration, for sessionID: String) {
        guard let key = QuickSessionIdentifier.storageKey(sessionID) else { return }
        guard configurations[key] == nil else { return }
        configurations[key] = configuration
        persist()
    }

    func save(_ configuration: QuickSessionConfiguration, for sessionID: String) {
        guard let key = QuickSessionIdentifier.storageKey(sessionID) else { return }
        configurations[key] = configuration
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(configurations) else { return }
        try? data.write(to: stateFile, options: .atomic)
    }
}
