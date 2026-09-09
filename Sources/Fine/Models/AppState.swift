import Combine
import Foundation

final class AppState: ObservableObject {
    private let storage: WindowStateStorage
    private let configurationStorage: QuickSessionConfigurationStorage
    let windowStateID: UUID
    private(set) var restoredFrame: WindowFrameState?
    private(set) var restoredIsZoomed = false
    private(set) var restoredIsFullscreen = false

    @Published var sessions: [TerminalSession] = []
    @Published var selectedSession: TerminalSession? {
        didSet { observeSelectedSession() }
    }
    private var selectedSessionObservation: AnyCancellable?

    init(
        requestedWindowStateID: UUID? = nil,
        storage: WindowStateStorage = .shared,
        configurationStorage: QuickSessionConfigurationStorage = .shared
    ) {
        self.storage = storage
        self.configurationStorage = configurationStorage
        let claimed = requestedWindowStateID.flatMap { storage.claim(id: $0) }
            ?? (requestedWindowStateID == nil ? storage.claimNext() : nil)
        if let claimed {
            windowStateID = claimed.id
            restoredFrame = claimed.frame
            restoredIsZoomed = claimed.resolvedIsZoomed
            restoredIsFullscreen = claimed.resolvedIsFullscreen
            sessions = (claimed.sessions ?? []).map {
                TerminalSession(snapshot: $0, configurationStorage: configurationStorage)
            }
            sessions.forEach(bindPersistence)
            selectedSession = sessions.first { $0.id == claimed.selectedSessionID }
        } else {
            if let requestedWindowStateID, !storage.contains(id: requestedWindowStateID) {
                windowStateID = requestedWindowStateID
            } else {
                windowStateID = UUID()
            }
            storage.registerClaimed(windowStateID)
            persistWindowState()
        }
        FineWindowRegistry.shared.register(self)
    }

    deinit {
        FineWindowRegistry.shared.unregister(self)
        if !AppTermination.isTerminating {
            storage.remove(id: windowStateID)
        }
    }

    var windowTitle: String { selectedSession?.name ?? "Fine" }

    func addSession(
        initialPrompt: String? = nil,
        resumeSessionId: String? = nil,
        configuration: QuickSessionConfiguration = .default,
        startImmediately: Bool = true
    ) {
        let launch: QuickLaunch
        if let resumeSessionId, QuickSessionIdentifier.isValid(resumeSessionId, for: configuration.harness) {
            launch = .resume(sessionId: resumeSessionId)
        } else if let initialPrompt {
            let trimmed = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            launch = trimmed.isEmpty ? .blank : .initialPrompt(trimmed)
        } else {
            launch = .blank
        }
        let session = TerminalSession(
            name: QuickSessionPolicy.initialSessionName(for: configuration.harness),
            launch: launch,
            configuration: configuration,
            configurationStorage: configurationStorage
        )
        bindPersistence(session)
        sessions.append(session)
        selectSession(session)
        if startImmediately { session.startImmediately() }
    }

    func resumeConversation(_ conversation: QuickConversation, startImmediately: Bool = true) {
        guard QuickSessionIdentifier.isValid(conversation.id, for: conversation.harness) else { return }
        if let existing = sessions.first(where: {
            $0.configuration.harness == conversation.harness && $0.matchesConversation(sessionId: conversation.id)
        }) {
            selectSession(existing)
            return
        }
        var configuration = QuickSessionConfiguration.defaultConfiguration(for: conversation.harness)
        if let saved = configurationStorage.configuration(for: conversation.id), saved.harness == conversation.harness {
            configuration = saved
        }
        addSession(
            resumeSessionId: conversation.id,
            configuration: configuration,
            startImmediately: startImmediately
        )
        selectedSession?.name = conversation.title
    }

    func resumeConversation(sessionId: String) {
        if let existing = sessions.first(where: { $0.matchesConversation(sessionId: sessionId) }) {
            selectSession(existing)
            return
        }
        addSession(
            resumeSessionId: sessionId,
            configuration: resumeConfiguration(for: sessionId)
        )
    }

    @discardableResult
    func restartSession(
        _ session: TerminalSession,
        with configuration: QuickSessionConfiguration,
        startImmediately: Bool = true
    ) -> Bool {
        guard let index = sessions.firstIndex(of: session),
              let sessionID = session.resumableSessionID else {
            return false
        }
        configurationStorage.save(configuration, for: sessionID)
        let replacement = TerminalSession(
            name: session.name,
            launch: .resume(sessionId: sessionID),
            configuration: configuration,
            configurationStorage: configurationStorage
        )
        bindPersistence(replacement)
        let wasSelected = selectedSession === session
        session.cleanup(force: true)
        sessions[index] = replacement
        if wasSelected {
            selectedSession = replacement
            if startImmediately {
                replacement.startImmediately()
                replacement.focusTerminal()
            }
        }
        return true
    }

    private func resumeConfiguration(for sessionID: String) -> QuickSessionConfiguration {
        configurationStorage.configuration(for: sessionID) ?? .default
    }

    func showHome() {
        selectedSession = nil
        persistWindowState()
    }

    func removeSession(_ session: TerminalSession) {
        session.cleanup(force: true)
        sessions.removeAll { $0.id == session.id }
        if selectedSession?.id == session.id {
            selectedSession = sessions.first
        }
        persistWindowState()
    }

    /// Move existing objects, preserving the PTY, selection and conversation identity.
    @discardableResult
    func moveSession(id: UUID, to targetID: UUID) -> Bool {
        guard id != targetID,
              let source = sessions.firstIndex(where: { $0.id == id }),
              let target = sessions.firstIndex(where: { $0.id == targetID }) else { return false }
        return moveSession(id: id, relativeTo: targetID, edge: source < target ? .after : .before)
    }

    /// Insert at a boundary in the original list, adjusting for removal of the source.
    @discardableResult
    func moveSession(id: UUID, relativeTo targetID: UUID, edge: SessionInsertionEdge) -> Bool {
        guard let target = sessions.firstIndex(where: { $0.id == targetID }),
              let source = sessions.firstIndex(where: { $0.id == id }) else { return false }
        let boundary = target + (edge == .after ? 1 : 0)
        let destination = boundary - (source < boundary ? 1 : 0)
        guard source != destination else { return false }
        let session = sessions.remove(at: source)
        sessions.insert(session, at: destination)
        persistWindowState()
        return true
    }

    func moveSession(id: UUID, by offset: Int) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              sessions.indices.contains(index + offset) else { return }
        moveSession(id: id, to: sessions[index + offset].id)
    }

    /// 창이 닫히거나 앱이 종료될 때 이 창의 모든 세션을 정리한다.
    /// 이 경로가 없으면 대화를 하나씩 닫았을 때만 자식이 정리되고, 창을 통째로
    /// 닫으면 deinit의 SIGHUP만 받은 자식들이 그대로 살아남는다.
    /// synchronous는 앱 종료 경로 — 비동기 승격을 기다릴 수 없을 때 쓴다.
    func cleanupAllSessions(synchronous: Bool = false) {
        let closing = sessions
        sessions.removeAll()
        selectedSession = nil
        for session in closing {
            if synchronous {
                session.cleanupForTermination()
            } else {
                session.cleanup(force: true)
            }
        }
    }

    func selectSession(_ session: TerminalSession) {
        guard selectedSession?.id != session.id else {
            session.focusTerminal()
            return
        }
        selectedSession = session
        session.restartIfDead()
        session.focusTerminal()
        persistWindowState()
    }

    func selectNextSession() {
        guard !sessions.isEmpty else { return }
        guard let selectedSession,
              let index = sessions.firstIndex(of: selectedSession) else {
            selectSession(sessions[0])
            return
        }
        selectSession(sessions[(index + 1) % sessions.count])
    }

    func selectPreviousSession() {
        guard !sessions.isEmpty else { return }
        guard let selectedSession,
              let index = sessions.firstIndex(of: selectedSession) else {
            selectSession(sessions[0])
            return
        }
        selectSession(sessions[(index - 1 + sessions.count) % sessions.count])
    }

    func updateWindowPresentation(
        frame: WindowFrameState?,
        isZoomed: Bool,
        isFullscreen: Bool
    ) {
        if let frame { restoredFrame = frame }
        restoredIsZoomed = isZoomed
        restoredIsFullscreen = isFullscreen
        persistWindowState()
    }

    private func persistWindowState() {
        storage.update(WindowState(
            id: windowStateID,
            frame: restoredFrame,
            isZoomed: restoredIsZoomed,
            isFullscreen: restoredIsFullscreen,
            sessions: sessions.map { $0.snapshot() },
            selectedSessionID: selectedSession?.id
        ))
    }

    private func observeSelectedSession() {
        selectedSessionObservation = selectedSession?.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }

    private func bindPersistence(_ session: TerminalSession) {
        session.setPersistenceHandler { [weak self, weak session] in
            guard let self, session != nil, !AppTermination.isTerminating else { return }
            self.persistWindowState()
        }
    }
}
