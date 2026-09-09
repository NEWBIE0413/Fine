import Combine
import Foundation

/// One ephemeral agent conversation backed by a direct PTY and xterm.js view.
final class TerminalSession: Identifiable, ObservableObject, Equatable {
    let id: UUID
    @Published var name: String
    @Published var isRunning = false
    @Published var startError: String?
    @Published var isModelPickerPresented = false

    let launch: QuickLaunch
    let configuration: QuickSessionConfiguration
    private let initialName: String
    private(set) var terminalView: TerminalWebView?
    private var pty: PTYProcess?
    private var started = false
    private var sessionId: String?
    private var identityTimer: Timer?
    private var titleCancellable: AnyCancellable?
    private let configurationStorage: QuickSessionConfigurationStorage
    private var persistenceHandler: (() -> Void)?
    private var identityStartedAt = Date()
    private var metadataGeneration = UUID()
    private var metadataRefreshInFlight = false
    private let metadataQueue = DispatchQueue(label: "Fine.SessionMetadata", qos: .utility)

    var resumableSessionID: String? { sessionId }

    init(
        id: UUID = UUID(),
        name: String = QuickSessionPolicy.initialSessionName,
        launch: QuickLaunch = .blank,
        configuration: QuickSessionConfiguration = .default,
        configurationStorage: QuickSessionConfigurationStorage = .shared
    ) {
        self.id = id
        self.name = name
        self.initialName = name
        self.launch = launch
        self.configuration = configuration
        self.configurationStorage = configurationStorage
        if case .resume(let sessionId) = launch {
            self.sessionId = sessionId
        }
    }

    convenience init(
        snapshot: QuickSessionSnapshot,
        configurationStorage: QuickSessionConfigurationStorage = .shared
    ) {
        self.init(
            id: snapshot.id,
            name: snapshot.name,
            launch: snapshot.conversationID.map { .resume(sessionId: $0) } ?? .resumeLatest,
            configuration: snapshot.configuration,
            configurationStorage: configurationStorage
        )
    }

    func snapshot() -> QuickSessionSnapshot {
        QuickSessionSnapshot(
            id: id,
            name: name,
            conversationID: sessionId,
            configuration: configuration
        )
    }

    func setPersistenceHandler(_ handler: @escaping () -> Void) {
        persistenceHandler = handler
    }

    func getOrCreateTerminal() -> TerminalWebView {
        if let terminalView { return terminalView }
        let view = TerminalWebView(
            frame: .zero,
            palette: .quickLight,
            statusText: configuration.terminalStatus,
            // OpenCode draws its own input and status rows at the bottom; only
            // Claude Code's hint row is replaced by Fine's status rail.
            footerCrop: configuration.harness == .claude ? TerminalWebView.claudeFooterCrop : 0
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        view.onUserInput = { [weak self] data in self?.pty?.write(data) }
        view.onResize = { [weak self] columns, rows in
            self?.pty?.resize(cols: columns, rows: rows)
        }
        view.onReady = { [weak self] in self?.startIfNeeded() }
        view.onWebProcessCrash = { [weak self] in self?.recoverFromCrash() }
        view.onStatusClick = { [weak self] in
            DispatchQueue.main.async {
                self?.isModelPickerPresented = true
            }
        }
        terminalView = view
        return view
    }

    /// Start page loading and the child process together. Output received before xterm is
    /// ready is retained by TerminalWebView and flushed by its ready handler.
    func startImmediately() {
        _ = getOrCreateTerminal()
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        startPTY()
    }

    private func startPTY() {
        identityStartedAt = Date()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let executableName = "-" + (shell as NSString).lastPathComponent
        let directory = QuickSessionPolicy.ensureWorkingDirectory()
        // Pin a restored "latest" launch before starting the CLI so title lookup
        // and the actual resume command use exactly the same conversation.
        let effectiveLaunch = HarnessSessionStore.local.resolvingLatest(
            launch, harness: configuration.harness, workingDirectory: directory
        )
        if case .resume(let id) = effectiveLaunch { sessionId = id }
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment = QuickSessionPolicy.applyingEnvironment(
            environment,
            launch: effectiveLaunch,
            configuration: configuration
        )

        let process = PTYProcess()
        let view = terminalView
        process.onOutput = { [weak view] data in view?.feed(data) }
        process.onExit = { [weak self] _ in
            DispatchQueue.main.async { self?.isRunning = false }
        }
        do {
            try process.start(
                executable: shell,
                execName: executableName,
                arguments: Self.launchArguments(launch: effectiveLaunch, configuration: configuration),
                environment: environment,
                workingDirectory: directory,
                cols: view?.lastCols ?? 80,
                rows: view?.lastRows ?? 24
            )
            pty = process
            isRunning = true
            startError = nil
            if let processIdentifier = process.processIdentifier {
                beginIdentityUpdates(processIdentifier: processIdentifier)
            }
        } catch {
            startError = "터미널 시작 실패: \(error)"
            isRunning = false
        }
    }

    private func beginIdentityUpdates(processIdentifier: pid_t) {
        identityTimer?.invalidate()
        titleCancellable = nil
        metadataGeneration = UUID()
        metadataRefreshInFlight = false
        if case .resume = launch {} else if case .resumeLatest = launch, sessionId != nil {} else {
            sessionId = nil
            name = initialName
        }

        if configuration.harness == .claude {
            let scanner = QuickConversationScanner.shared
            titleCancellable = scanner.$aiTitlesBySessionId
                .receive(on: DispatchQueue.main)
                .sink { [weak self] titles in self?.updateTitle(titlesBySessionId: titles) }
            scanner.start()
            if let sessionId { scanner.track(sessionID: sessionId, owner: id) }
        }

        refreshSessionMetadata(processIdentifier: processIdentifier)
        identityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
            [weak self] timer in
            guard let self, self.isRunning else {
                timer.invalidate()
                return
            }
            if self.configuration.harness == .claude && self.sessionId != nil {
                timer.invalidate()
                self.identityTimer = nil
                return
            }
            if self.sessionId == nil || AppResourcePolicy.hasVisibleWindows {
                self.refreshSessionMetadata(processIdentifier: processIdentifier)
            }
        }
        identityTimer?.tolerance = 0.5
    }

    func refreshSessionMetadata(processIdentifier: pid_t, store: HarnessSessionStore? = nil) {
        guard !metadataRefreshInFlight else { return }
        metadataRefreshInFlight = true
        let generation = metadataGeneration
        let knownID = sessionId
        let harness = configuration.harness
        let startedAt = identityStartedAt
        let initialPrompt: String?
        if case .initialPrompt(let prompt) = launch { initialPrompt = prompt } else { initialPrompt = nil }
        metadataQueue.async { [weak self] in
            let store = store ?? HarnessSessionStore.local
            let resolvedID: String?
            if let knownID {
                resolvedID = knownID
            } else {
                switch harness {
                case .claude:
                    resolvedID = QuickSessionTitleResolver.sessionId(processIdentifier: processIdentifier)
                case .codex:
                    resolvedID = CodexSessionResolver.sessionId(processIdentifier: processIdentifier)
                        ?? store.newSessionID(
                            harness: harness, createdAfter: startedAt,
                            workingDirectory: QuickSessionPolicy.workingDirectory,
                            initialPrompt: initialPrompt
                        )
                case .opencode:
                    resolvedID = store.newSessionID(
                        harness: harness, createdAfter: startedAt,
                        workingDirectory: QuickSessionPolicy.workingDirectory, initialPrompt: initialPrompt
                    )
                }
            }
            let metadata = resolvedID.map { id in
                store.metadata(harness: harness, sessionID: id)
                    ?? HarnessSessionMetadata(id: id, title: nil)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.metadataGeneration == generation else { return }
                self.metadataRefreshInFlight = false
                if let metadata { self.applyMetadata(metadata) }
            }
        }
    }

    func applyMetadata(_ metadata: HarnessSessionMetadata) {
        guard sessionId == nil || sessionId == metadata.id else { return }
        let identityChanged = sessionId == nil
        sessionId = metadata.id
        if identityChanged {
            configurationStorage.saveIfAbsent(configuration, for: metadata.id)
            persistenceHandler?()
        }
        if configuration.harness == .claude {
            updateTitle(titlesBySessionId: QuickConversationScanner.shared.aiTitlesBySessionId)
            if identityChanged { QuickConversationScanner.shared.track(sessionID: metadata.id, owner: id) }
        } else if let title = metadata.title {
            updateTitle(titlesBySessionId: [metadata.id: title])
        }
    }

    func updateTitle(titlesBySessionId: [String: String]) {
        guard let sessionId, let title = titlesBySessionId[sessionId],
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title != name else { return }
        name = title
        persistenceHandler?()
    }

    func matchesConversation(sessionId: String) -> Bool {
        self.sessionId == sessionId
    }

    func restartIfDead() {
        guard started, pty?.isRunning != true else { return }
        pty?.terminate()
        pty = nil
        startError = nil
        startPTY()
    }

    private func recoverFromCrash() {
        pty?.terminate()
        pty = nil
        started = false
        terminalView?.reloadPage()
    }

    func focusTerminal() {
        DispatchQueue.main.async { [weak self] in self?.terminalView?.focusTerminal() }
    }

    func cleanup(force: Bool = false) {
        QuickConversationScanner.shared.untrack(owner: id)
        metadataGeneration = UUID()
        identityTimer?.invalidate()
        identityTimer = nil
        titleCancellable = nil
        pty?.terminate(force: force)
        pty = nil
        terminalView?.removeFromSuperview()
        terminalView = nil
    }

    /// 앱 종료 경로 — 비동기 승격이 실행될 기회가 없으므로 동기적으로 종료한다.
    func cleanupForTermination() {
        QuickConversationScanner.shared.untrack(owner: id)
        metadataGeneration = UUID()
        identityTimer?.invalidate()
        identityTimer = nil
        titleCancellable = nil
        pty?.terminateSynchronously()
        pty = nil
        terminalView?.removeFromSuperview()
        terminalView = nil
    }

    static func launchArguments(
        launch: QuickLaunch = .blank,
        configuration: QuickSessionConfiguration = .default
    ) -> [String] {
        QuickSessionPolicy.shellArguments
            + [QuickSessionPolicy.launchCommand(for: launch, configuration: configuration)]
    }

    static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        lhs.id == rhs.id
    }
}
