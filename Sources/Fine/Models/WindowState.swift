import Foundation

struct WindowFrameState: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct WindowState: Codable, Identifiable, Equatable {
    let id: UUID
    var frame: WindowFrameState?
    var isZoomed: Bool?
    var isFullscreen: Bool?

    var resolvedIsZoomed: Bool { isZoomed ?? false }
    var resolvedIsFullscreen: Bool { isFullscreen ?? false }
}

final class WindowStateStorage {
    static let shared = WindowStateStorage()

    private let fileManager: FileManager
    private let stateFile: URL
    private(set) var states: [WindowState]
    private var claimedIDs: Set<UUID> = []

    init(
        fileManager: FileManager = .default,
        stateFile: URL? = nil
    ) {
        self.fileManager = fileManager
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".fine", isDirectory: true)
        self.stateFile = stateFile ?? directory.appendingPathComponent("window-states.json")
        try? fileManager.createDirectory(at: self.stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        states = (try? Data(contentsOf: self.stateFile))
            .flatMap { try? JSONDecoder().decode([WindowState].self, from: $0) } ?? []
    }

    func claim(id: UUID) -> WindowState? {
        guard let state = Self.exactUnclaimedState(id: id, states: states, claimedIDs: claimedIDs) else {
            return nil
        }
        claimedIDs.insert(id)
        return state
    }

    func claimNext() -> WindowState? {
        guard let state = states.first(where: { !claimedIDs.contains($0.id) }) else { return nil }
        claimedIDs.insert(state.id)
        return state
    }

    func registerClaimed(_ id: UUID) { claimedIDs.insert(id) }
    func contains(id: UUID) -> Bool { states.contains { $0.id == id } }
    func unclaimedStates() -> [WindowState] { states.filter { !claimedIDs.contains($0.id) } }

    func update(_ state: WindowState) {
        if let index = states.firstIndex(where: { $0.id == state.id }) {
            states[index] = state
        } else {
            states.append(state)
        }
        save()
    }

    func remove(id: UUID) {
        claimedIDs.remove(id)
        states.removeAll { $0.id == id }
        save()
    }

    static func exactUnclaimedState(
        id: UUID,
        states: [WindowState],
        claimedIDs: Set<UUID>
    ) -> WindowState? {
        guard !claimedIDs.contains(id) else { return nil }
        return states.first { $0.id == id }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(states) else { return }
        try? data.write(to: stateFile, options: .atomic)
    }
}
