import Combine
import Foundation

final class AppState: ObservableObject {
    private let storage: WindowStateStorage
    let windowStateID: UUID
    private(set) var restoredFrame: WindowFrameState?
    private(set) var restoredIsZoomed = false
    private(set) var restoredIsFullscreen = false

    @Published var sessions: [TerminalSession] = []
    @Published var selectedSession: TerminalSession? {
        didSet { observeSelectedSession() }
    }
    private var selectedSessionObservation: AnyCancellable?

    init(requestedWindowStateID: UUID? = nil, storage: WindowStateStorage = .shared) {
        self.storage = storage
        let claimed = requestedWindowStateID.flatMap { storage.claim(id: $0) }
            ?? (requestedWindowStateID == nil ? storage.claimNext() : nil)
        if let claimed {
            windowStateID = claimed.id
            restoredFrame = claimed.frame
            restoredIsZoomed = claimed.resolvedIsZoomed
            restoredIsFullscreen = claimed.resolvedIsFullscreen
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
        configuration: QuickSessionConfiguration = .default
    ) {
        let launch: QuickLaunch
        if let resumeSessionId, UUID(uuidString: resumeSessionId) != nil {
            launch = .resume(sessionId: resumeSessionId)
        } else if let initialPrompt {
            let trimmed = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            launch = trimmed.isEmpty ? .blank : .initialPrompt(trimmed)
        } else {
            launch = .blank
        }
        let session = TerminalSession(launch: launch, configuration: configuration)
        sessions.append(session)
        selectSession(session)
        session.startImmediately()
    }

    func resumeConversation(sessionId: String) {
        if let existing = sessions.first(where: { $0.matchesConversation(sessionId: sessionId) }) {
            selectSession(existing)
            return
        }
        addSession(resumeSessionId: sessionId)
    }

    func showHome() {
        selectedSession = nil
    }

    func removeSession(_ session: TerminalSession) {
        session.cleanup(force: true)
        sessions.removeAll { $0.id == session.id }
        if selectedSession?.id == session.id {
            selectedSession = sessions.first
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
            isFullscreen: restoredIsFullscreen
        ))
    }

    private func observeSelectedSession() {
        selectedSessionObservation = selectedSession?.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }
}
