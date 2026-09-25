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
        case .omp: return "OMP 세션"
        }
    }

    /// `ccv`는 Claude Code에 짧은 플래그를 붙여주는 개인용 런처다. 있으면 그것을 쓰고,
    /// 없으면 `claude`를 직접 부른다 — 이 저장소를 받은 사람에게 ccv가 있을 이유가 없다.
    static var ccvExecutablePath: String {
        let home = FinePaths.home
        let candidates = [
            home.appendingPathComponent("myworld/ccv", isDirectory: false).path,
            home.appendingPathComponent(".local/bin/claude", isDirectory: false).path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
    }

    /// 런처를 거치지 않은 Claude Code 자체. 한 번 묻고 끝나는 `claude -p`는 ccv의 플래그가 필요 없다.
    static var claudeExecutablePath: String {
        let candidates = [
            FinePaths.home.appendingPathComponent(".local/bin/claude", isDirectory: false).path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/claude"
    }

    /// 어떤 런처를 잡았는지. 플래그 모양이 다르므로 명령을 만들 때 알아야 한다.
    static var usesCcvWrapper: Bool {
        URL(fileURLWithPath: ccvExecutablePath).lastPathComponent == "ccv"
    }

    /// The terminal resolves `opencode` from the interactive PATH, which puts the
    /// standalone installer's binary ahead of Homebrew's. Mirror that order so a
    /// Fine session never runs an older Homebrew build than the terminal does.
    static var opencodeExecutablePath: String {
        let home = FinePaths.home
        let candidates = [
            home.appendingPathComponent(".opencode/bin/opencode").path,
            "/opt/homebrew/bin/opencode",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "opencode"
    }

    /// 터미널이 PATH에서 찾는 순서를 그대로 따른다.
    static var ompExecutablePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".bun/bin/omp").path,
            "/opt/homebrew/bin/omp",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "omp"
    }

    static var codexExecutablePath: String {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "codex"
    }

    static var workingDirectory: String {
        FinePaths.home
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
        configuration: QuickSessionConfiguration = .default,
        usesWrapper: Bool = usesCcvWrapper
    ) -> String {
        switch configuration.harness {
        case .claude:
            return claudeLaunchCommand(
                for: launch, configuration: configuration, usesWrapper: usesWrapper
            )
        case .codex:
            return codexLaunchCommand(for: launch, configuration: configuration)
        case .opencode:
            return opencodeLaunchCommand(for: launch, configuration: configuration)
        case .omp:
            return ompLaunchCommand(for: launch, configuration: configuration)
        }
    }

    /// Default mode passes no model or effort flag at all: it is `ccv -y`, the
    /// same command the user types, so Claude Code applies its own settings.
    static func claudeLaunchCommand(
        for launch: QuickLaunch,
        configuration: QuickSessionConfiguration,
        usesWrapper: Bool = usesCcvWrapper
    ) -> String {
        var parts = [#"exec "$FINE_CCV""#]
        // ccv는 -y/-ry로 줄여 받고, claude 본체는 긴 플래그를 받는다.
        let skipPermissions = usesWrapper ? "-y" : "--dangerously-skip-permissions"
        if case .resume = launch {
            parts.append(usesWrapper
                ? #"-ry "$FINE_RESUME_SESSION_ID""#
                : #"--resume "$FINE_RESUME_SESSION_ID" --dangerously-skip-permissions"#)
        } else if case .resumeLatest = launch {
            parts.append("\(skipPermissions) --continue")
        } else {
            parts.append(skipPermissions)
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

    /// omp는 모델이 세션당 하나가 아니라 역할 슬롯(default/smol/slow/plan)이다.
    /// `--model`은 그중 default만 덮으므로, 나머지는 `~/.omp/agent/config.yml`이 그대로 결정한다.
    /// 하네스 UI에서 모델 하나를 고르는 것이 이 구조를 무너뜨리지 않는 이유다.
    ///
    /// 토큰은 공유하지 않는다: omp는 Codex OAuth를 자기 `agent.db`에 별도 체인으로 들고 있고,
    /// `~/.codex/auth.json`과 리프레시 토큰이 다르다. Fine은 PTY만 띄우고 인증에 손대지 않는다.
    private static func ompLaunchCommand(
        for launch: QuickLaunch,
        configuration: QuickSessionConfiguration
    ) -> String {
        var parts = [#"exec "$FINE_OMP" --auto-approve"#]
        if !configuration.isDefaultModel {
            parts.append(#"--model "$FINE_MODEL" --thinking="$FINE_EFFORT""#)
        }
        switch launch {
        case .blank, .initialPrompt:
            break
        case .resume:
            parts.append(#"-r "$FINE_RESUME_SESSION_ID""#)
        case .resumeLatest:
            parts.append("-c")
        }
        // 메시지는 위치 인자다. 플래그를 모두 붙인 뒤에 온다.
        if case .initialPrompt = launch {
            parts.append(#""$FINE_INITIAL_PROMPT""#)
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
            "FINE_OMP": ompExecutablePath.replacingOccurrences(of: "\0", with: ""),
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
        let home = FinePaths.home.path
        let requiredPaths = [
            home + "/.local/bin", "/opt/homebrew/bin",
            home + "/.opencode/bin", home + "/.bun/bin",
        ]
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
