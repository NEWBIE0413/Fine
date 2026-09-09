import Foundation

struct QuickConversation: Identifiable, Equatable {
    let id: String          // Native harness session ID, passed unchanged to resume.
    let title: String
    let aiTitle: String?
    let modifiedAt: Date
    let transcriptURL: URL?
    var harness: QuickHarness = .claude

    var listID: String { "\(harness.rawValue):\(id)" }
}

/// Metadata-only, demand-paged recent conversations shared by all windows.
final class QuickConversationScanner: ObservableObject {
    static let shared = QuickConversationScanner()
    static let refreshInterval: TimeInterval = 5
    static let pageSize = 30

    @Published private(set) var conversations: [QuickConversation] = []
    @Published private(set) var aiTitlesBySessionId: [String: String] = [:]
    @Published private(set) var hasMore = false
    @Published private(set) var isLoading = false
    private(set) var metadataBytesRead = 0
    private var requestedCount = pageSize
    private var trackedSessions: [UUID: String] = [:]
    private var rescanPending = false
    private var titleIndex = TranscriptTitleIndex()
    private let transcriptsDirectory: URL
    private let queue = DispatchQueue(label: "Fine.QuickConversations", qos: .utility)
    private var timer: Timer?
    private let sessionStore: HarnessSessionStore?
    private let workingDirectory: String
    init(transcriptsDirectory: URL = QuickConversationScanner.defaultTranscriptsDirectory(),
         sessionStore: HarnessSessionStore? = .local, workingDirectory: String = QuickSessionPolicy.workingDirectory) {
        self.transcriptsDirectory = transcriptsDirectory
        self.sessionStore = sessionStore
        self.workingDirectory = workingDirectory
    }

    static func defaultTranscriptsDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let encoded = QuickSessionPolicy.workingDirectory.replacingOccurrences(of: "/", with: "-")
        return home.appendingPathComponent(".claude/projects").appendingPathComponent(encoded)
    }

    func start() {
        guard timer == nil else { return }
        rescan()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            guard AppResourcePolicy.hasVisibleWindows else { return }
            self?.rescan()
        }
        timer?.tolerance = 1
    }

    func stop() { timer?.invalidate(); timer = nil }

    func track(sessionID: String, owner: UUID) {
        guard trackedSessions[owner] != sessionID else { return }
        trackedSessions[owner] = sessionID
        rescan()
    }

    func untrack(owner: UUID) { trackedSessions.removeValue(forKey: owner) }

    func loadNextPage() {
        guard hasMore, !isLoading else { return }
        requestedCount += Self.pageSize
        rescan()
    }

    func rescan() {
        guard !isLoading else { rescanPending = true; return }
        isLoading = true
        let limit = requestedCount
        let tracked = Set(trackedSessions.values)
        queue.async { [weak self] in
            guard let self else { return }
            let result = Self.scanClaude(directory: self.transcriptsDirectory, limit: limit + 1,
                                         tracked: tracked, index: &self.titleIndex)
            let combined = Self.merged(result.rows, self.sessionStore?.recentConversations(workingDirectory: self.workingDirectory, limit: limit + 1) ?? [])
            let bytes = self.titleIndex.bytesRead
            DispatchQueue.main.async {
                let visible = Array(combined.prefix(limit))
                if self.conversations != visible { self.conversations = visible }
                if self.aiTitlesBySessionId != result.titles { self.aiTitlesBySessionId = result.titles }
                self.hasMore = result.hasMore || combined.count > limit
                self.metadataBytesRead = bytes
                self.isLoading = false
                if self.rescanPending {
                    self.rescanPending = false
                    self.rescan()
                }
            }
        }
    }

    static func scan(directory: URL, sessionStore: HarnessSessionStore? = nil, workingDirectory: String = QuickSessionPolicy.workingDirectory) -> [QuickConversation] {
        var index = TranscriptTitleIndex()
        let result = scanClaude(directory: directory, limit: Int.max, tracked: [], index: &index)
        return merged(result.rows, sessionStore?.recentConversations(workingDirectory: workingDirectory) ?? [])
    }

    static func scanAITitles(directory: URL) -> [String: String] {
        var index = TranscriptTitleIndex()
        return scanClaude(directory: directory, limit: Int.max, tracked: [], index: &index).titles
    }

    static func merged(_ first: [QuickConversation], _ second: [QuickConversation]) -> [QuickConversation] {
        let unique = Dictionary((first + second).map { ($0.listID, $0) }, uniquingKeysWith: {
            $0.modifiedAt >= $1.modifiedAt ? $0 : $1
        })
        return unique.values.sorted {
            $0.modifiedAt == $1.modifiedAt ? $0.listID < $1.listID : $0.modifiedAt > $1.modifiedAt
        }
    }

    private static func scanClaude(
        directory: URL, limit: Int, tracked: Set<String>, index: inout TranscriptTitleIndex
    ) -> (rows: [QuickConversation], titles: [String: String], hasMore: Bool) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        let descriptors = files.compactMap { file -> (URL, String, Date)? in
            let id = file.deletingPathExtension().lastPathComponent
            guard file.pathExtension == "jsonl", UUID(uuidString: id) != nil,
                  let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
            return (file, id, modified)
        }.sorted { $0.2 == $1.2 ? $0.1 < $1.1 : $0.2 > $1.2 }
        var rows: [QuickConversation] = []
        var titles: [String: String] = [:]
        var seenTitles = Set<String>()
        var retained = Set<String>()
        var hasMore = false
        for (url, id, modified) in descriptors {
            let neededForPage = rows.count < limit
            if !neededForPage { hasMore = true }
            guard neededForPage || tracked.contains(id) else { continue }
            retained.insert(url.path)
            guard let metadata = index.metadata(for: url) else { continue }
            if let title = metadata.aiTitle { titles[id] = title }
            guard neededForPage, let title = metadata.title else { continue }
            let normalized = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard seenTitles.insert(normalized).inserted else { continue }
            rows.append(QuickConversation(id: id, title: title, aiTitle: metadata.aiTitle,
                                          modifiedAt: modified, transcriptURL: url))
        }
        index.retain(paths: retained)
        return (rows, titles, hasMore)
    }
}
