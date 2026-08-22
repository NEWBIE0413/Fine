import Combine
import Foundation

/// One ephemeral Claude conversation backed by a direct PTY and xterm.js view.
final class TerminalSession: Identifiable, ObservableObject, Equatable {
    let id: UUID
    @Published var name: String
    @Published var isRunning = false
    @Published var startError: String?

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

    func getOrCreateTerminal() -> TerminalWebView {
        if let terminalView { return terminalView }
        let view = TerminalWebView(
            frame: .zero,
            palette: .quickLight,
            statusText: configuration.terminalStatus
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        view.onUserInput = { [weak self] data in self?.pty?.write(data) }
        view.onResize = { [weak self] columns, rows in
            self?.pty?.resize(cols: columns, rows: rows)
        }
        view.onReady = { [weak self] in self?.startIfNeeded() }
        view.onWebProcessCrash = { [weak self] in self?.recoverFromCrash() }
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
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let executableName = "-" + (shell as NSString).lastPathComponent
        let directory = QuickSessionPolicy.ensureWorkingDirectory()
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment = QuickSessionPolicy.applyingEnvironment(
            environment,
            launch: launch,
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
                arguments: Self.launchArguments(launch: launch, configuration: configuration),
                environment: environment,
                workingDirectory: directory,
                cols: view?.lastCols ?? 80,
                rows: view?.lastRows ?? 24
            )
            pty = process
            isRunning = true
            startError = nil
            if let processIdentifier = process.processIdentifier {
                beginTitleUpdates(processIdentifier: processIdentifier)
            }
        } catch {
            startError = "터미널 시작 실패: \(error)"
            isRunning = false
        }
    }

    private func beginTitleUpdates(processIdentifier: pid_t) {
        let scanner = QuickConversationScanner.shared
        if case .resume = launch {} else {
            sessionId = nil
            name = initialName
        }
        titleCancellable = scanner.$aiTitlesBySessionId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] titles in self?.updateTitle(titlesBySessionId: titles) }
        scanner.start()
        scanner.rescan()

        guard sessionId == nil else { return }
        resolveSessionId(processIdentifier: processIdentifier)
        guard sessionId == nil else { return }
        identityTimer?.invalidate()
        identityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] timer in
            guard let self, self.isRunning else {
                timer.invalidate()
                return
            }
            self.resolveSessionId(processIdentifier: processIdentifier)
            if self.sessionId != nil {
                timer.invalidate()
                self.identityTimer = nil
            }
        }
    }

    private func resolveSessionId(processIdentifier: pid_t) {
        guard sessionId == nil,
              let resolved = QuickSessionTitleResolver.sessionId(
                  processIdentifier: processIdentifier
              ) else { return }
        sessionId = resolved
        configurationStorage.saveIfAbsent(configuration, for: resolved)
        updateTitle(titlesBySessionId: QuickConversationScanner.shared.aiTitlesBySessionId)
        QuickConversationScanner.shared.rescan()
    }

    func updateTitle(titlesBySessionId: [String: String]) {
        guard let sessionId, let title = titlesBySessionId[sessionId] else { return }
        name = title
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
        ["-lc", QuickSessionPolicy.launchCommand(for: launch, configuration: configuration)]
    }

    static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        lhs.id == rhs.id
    }
}
