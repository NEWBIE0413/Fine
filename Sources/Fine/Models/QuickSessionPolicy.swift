import Foundation

enum QuickLaunch: Equatable {
    case blank
    case initialPrompt(String)
    case resume(sessionId: String)
    case resumeLatest
}

/// Fine의 일상 대화 탭 규칙. 각 탭은 프로세스 수명에 묶인 일회성 PTY다.
enum QuickSessionPolicy {
    static let initialSessionName = "새 대화 세션"

    static func initialSessionName(for harness: QuickHarness) -> String {
        switch harness {
        case .claude: return initialSessionName
        case .codex: return "Codex 세션"
        case .opencode: return "OpenCode 세션"
        }
    }

    static var ccvExecutablePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("myworld/ccv", isDirectory: false)
            .path
    }

    /// The terminal resolves `opencode` from the interactive PATH, which puts the
    /// standalone installer's binary ahead of Homebrew's. Mirror that order so a
    /// Fine session never runs an older Homebrew build than the terminal does.
    static var opencodeExecutablePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".opencode/bin/opencode").path,
            "/opt/homebrew/bin/opencode",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "opencode"
    }

    static var codexExecutablePath: String {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "codex"
    }

    static var workingDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("cld", isDirectory: true)
            .path
    }

    @discardableResult
    static func ensureWorkingDirectory(
        fileManager: FileManager = .default
    ) -> String {
        let path = workingDirectory
        try? fileManager.createDirectory(
            atPath: path,
            withIntermediateDirectories: true
        )
        return path
    }

    /// Interactive login shell (`-ilc`), not just login (`-lc`): ~/.zshrc is where
    /// the provider keys and the `~/.opencode/bin` PATH entry live, and zsh only
    /// reads it for interactive shells. A Finder-launched Fine inherits none of
    /// that from launchd, so this is what makes a Fine session identical to a
    /// terminal session. The shell `exec`s the agent, so nothing interactive
    /// remains once the agent starts.
    static let shellArguments = ["-ilc"]

    static func launchCommand(
        for launch: QuickLaunch,
        configuration: QuickSessionConfiguration = .default
    ) -> String {
        switch configuration.harness {
        case .claude:
            return claudeLaunchCommand(for: launch, configuration: configuration)
        case .codex:
            return codexLaunchCommand(for: launch, configuration: configuration)
        case .opencode:
            return opencodeLaunchCommand(for: launch, configuration: configuration)
        }
    }

    /// Default mode passes no model or effort flag at all: it is `ccv -y`, the
    /// same command the user types, so Claude Code applies its own settings.
    private static func claudeLaunchCommand(
        for launch: QuickLaunch,
        configuration: QuickSessionConfiguration
    ) -> String {
        var parts = [#"exec "$FINE_CCV""#]
        if case .resume = launch {
            parts.append(#"-ry "$FINE_RESUME_SESSION_ID""#)
        } else if case .resumeLatest = launch {
            parts.append("-y --continue")
        } else {
            parts.append("-y")
        }
        if !configuration.isDefaultModel {
            parts.append(#"--model "$FINE_MODEL" --effort "$FINE_EFFORT""#)
        }
        if case .initialPrompt = launch {
            parts.append(#""$FINE_INITIAL_PROMPT""#)
        }
        return parts.joined(separator: " ")
    }

    /// Codex is launched as its stock CLI. Fine may pass the user's explicit
    /// model/effort choice, without a router or profile. Fine explicitly requests permission-skip mode.
    private static func codexLaunchCommand(
        for launch: QuickLaunch,
        configuration: QuickSessionConfiguration
    ) -> String {
        var parts = [#"exec "$FINE_CODEX""#]
        switch launch {
        case .blank:
            break
        case .initialPrompt:
            break
        case .resume:
            parts.append(#"resume "$FINE_RESUME_SESSION_ID""#)
        case .resumeLatest:
            parts.append("resume --last")
        }
        parts.append("--dangerously-bypass-approvals-and-sandbox")
        if !configuration.isDefaultModel {
            parts.append(#"--model "$FINE_MODEL" -c "model_reasoning_effort=$FINE_EFFORT""#)
        }
        if case .initialPrompt = launch {
            parts.append(#"-- "$FINE_INITIAL_PROMPT""#)
        }
        return parts.joined(separator: " ")
    }

    private static func opencodeLaunchCommand(
        for launch: QuickLaunch,
        configuration: QuickSessionConfiguration
    ) -> String {
        var parts = [#"exec "$FINE_OPENCODE" --auto"#]
        if !configuration.isDefaultModel {
            parts.append(#"--model "$FINE_MODEL""#)
        }
        switch launch {
        case .blank:
            break
        case .initialPrompt:
            parts.append(#"--prompt "$FINE_INITIAL_PROMPT""#)
        case .resume:
            parts.append(#"--session "$FINE_RESUME_SESSION_ID""#)
        case .resumeLatest:
            parts.append("--continue")
        }
        return parts.joined(separator: " ")
    }

    static func environment(
        for launch: QuickLaunch,
        configuration: QuickSessionConfiguration = .default
    ) -> [String: String] {
        var environment = [
            "FINE_CCV": ccvExecutablePath.replacingOccurrences(of: "\0", with: ""),
            "FINE_CODEX": codexExecutablePath.replacingOccurrences(of: "\0", with: ""),
            "FINE_OPENCODE": opencodeExecutablePath.replacingOccurrences(of: "\0", with: ""),
            "FINE_MODEL": configuration.modelID.replacingOccurrences(of: "\0", with: ""),
            "FINE_EFFORT": configuration.effort.rawValue,
        ]
        if configuration.harness == .claude {
            environment["CCV_PROXY"] = configuration.usesProxy ? "1" : "0"
        }
        switch launch {
        case .blank:
            break
        case .initialPrompt(let prompt):
            environment["FINE_INITIAL_PROMPT"] = prompt.replacingOccurrences(of: "\0", with: "")
        case .resume(let sessionId):
            environment["FINE_RESUME_SESSION_ID"] = sessionId
        case .resumeLatest:
            break
        }
        if configuration.usesProxy {
            environment["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:4141"
            environment["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] = "1"
        }
        return environment
    }

    static func applyingEnvironment(
        _ base: [String: String],
        launch: QuickLaunch,
        configuration: QuickSessionConfiguration
    ) -> [String: String] {
        var result = base
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let requiredPaths = [home + "/.local/bin", "/opt/homebrew/bin", home + "/.opencode/bin"]
        let inheritedPaths = (result["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        result["PATH"] = (requiredPaths + inheritedPaths).reduce(into: [String]()) { paths, path in
            guard !path.isEmpty, !paths.contains(path) else { return }
            paths.append(path)
        }.joined(separator: ":")
        // A Fine conversation is a top-level resumable session even when the app
        // was launched from inside Claude Code. Do not inherit the parent's child
        // marker, and explicitly keep transcripts for future resume launches.
        result.removeValue(forKey: "CLAUDE_CODE_CHILD_SESSION")
        result["CLAUDE_CODE_FORCE_SESSION_PERSISTENCE"] = "1"
        // A direct Claude session must stay direct even if Fine itself
        // was launched from a shell that happened to have gateway variables.
        result.removeValue(forKey: "ANTHROPIC_BASE_URL")
        result.removeValue(forKey: "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY")
        result.removeValue(forKey: "CCV_PROXY")
        for (key, value) in environment(for: launch, configuration: configuration) {
            result[key] = value
        }
        return result
    }

}
