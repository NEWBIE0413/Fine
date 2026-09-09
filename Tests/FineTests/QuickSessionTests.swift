import XCTest
@testable import Fine

final class QuickSessionTests: XCTestCase {
    func testRestartReplacesSessionAndPreservesResumeID() {
        let sessionID = UUID().uuidString
        let stateFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("fine-window-state-\(UUID().uuidString).json")
        let configurationFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("fine-session-state-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: stateFile)
            try? FileManager.default.removeItem(at: configurationFile)
        }
        let configurationStorage = QuickSessionConfigurationStorage(stateFile: configurationFile)
        let state = AppState(
            storage: WindowStateStorage(stateFile: stateFile),
            configurationStorage: configurationStorage
        )
        let original = TerminalSession(
            name: "Study",
            launch: .resume(sessionId: sessionID),
            configuration: .default,
            configurationStorage: configurationStorage
        )
        state.sessions = [original]
        state.selectedSession = original
        let replacement = QuickSessionConfiguration(
            modelID: "claude-codex-gpt-5.6-terra[1m]",
            effort: .high,
            proxyEnabled: true
        )

        XCTAssertTrue(
            state.restartSession(
                original,
                with: replacement,
                startImmediately: false
            )
        )
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertFalse(state.sessions[0] === original)
        XCTAssertEqual(state.sessions[0].name, "Study")
        XCTAssertEqual(state.sessions[0].launch, .resume(sessionId: sessionID))
        XCTAssertEqual(state.sessions[0].configuration, replacement)
        XCTAssertTrue(state.selectedSession === state.sessions[0])
        XCTAssertEqual(configurationStorage.configuration(for: sessionID), replacement)
    }

    /// Default mode is the terminal's `ccv -y`: no model, no effort, no router.
    func testSessionUsesFriendlyInitialNameAndDirectClaudePTY() {
        XCTAssertEqual(QuickSessionPolicy.initialSessionName, "새 대화 세션")
        XCTAssertEqual(QuickSessionPolicy.initialSessionName(for: .codex), "Codex 세션")
        XCTAssertEqual(QuickSessionPolicy.initialSessionName(for: .opencode), "OpenCode 세션")
        XCTAssertTrue(QuickSessionConfiguration.default.isDefaultModel)
        XCTAssertEqual(
            TerminalSession.launchArguments(),
            ["-ilc", #"exec "$FINE_CCV" -y"#]
        )
    }

    func testCodexHarnessSkipsPermissionsForNewAndResumedSessions() {
        let configuration = QuickSessionConfiguration.defaultConfiguration(for: .codex)
        let prompt = QuickLaunch.initialPrompt("hello")
        XCTAssertEqual(
            TerminalSession.launchArguments(configuration: configuration),
            ["-ilc", #"exec "$FINE_CODEX" --dangerously-bypass-approvals-and-sandbox"#]
        )
        XCTAssertEqual(
            TerminalSession.launchArguments(launch: prompt, configuration: configuration),
            ["-ilc", #"exec "$FINE_CODEX" --dangerously-bypass-approvals-and-sandbox -- "$FINE_INITIAL_PROMPT""#]
        )
        XCTAssertEqual(
            TerminalSession.launchArguments(
                launch: .resume(sessionId: "66b557a0-8d77-4bb4-8816-913e80aac3ea"),
                configuration: configuration
            ),
            ["-ilc", #"exec "$FINE_CODEX" resume "$FINE_RESUME_SESSION_ID" --dangerously-bypass-approvals-and-sandbox"#]
        )
        XCTAssertEqual(
            TerminalSession.launchArguments(launch: .resumeLatest, configuration: configuration),
            ["-ilc", #"exec "$FINE_CODEX" resume --last --dangerously-bypass-approvals-and-sandbox"#]
        )
        let environment = QuickSessionPolicy.applyingEnvironment(
            ["ANTHROPIC_BASE_URL": "http://127.0.0.1:4141"],
            launch: prompt,
            configuration: configuration
        )
        XCTAssertNil(environment["ANTHROPIC_BASE_URL"])
        XCTAssertEqual(environment["FINE_CODEX"], QuickSessionPolicy.codexExecutablePath)
        XCTAssertEqual(environment["FINE_INITIAL_PROMPT"], "hello")
        XCTAssertFalse(environment.keys.contains { $0.hasPrefix("SM_") })

        let selected = QuickSessionConfiguration(
            harness: .codex,
            modelID: "gpt-6-astra",
            effort: .ultra,
            proxyEnabled: true
        )
        XCTAssertEqual(
            TerminalSession.launchArguments(configuration: selected),
            ["-ilc", #"exec "$FINE_CODEX" --dangerously-bypass-approvals-and-sandbox --model "$FINE_MODEL" -c "model_reasoning_effort=$FINE_EFFORT""#]
        )
        XCTAssertFalse(selected.usesProxy)
    }

    func testRestoredSessionUsesExactConversationAndSelection() throws {
        let stateFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("fine-restore-\(UUID().uuidString).json")
        let configurationFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("fine-restore-config-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: stateFile)
            try? FileManager.default.removeItem(at: configurationFile)
        }
        let storage = WindowStateStorage(stateFile: stateFile)
        let windowID = UUID()
        let selectedID = UUID()
        let conversationID = UUID().uuidString.lowercased()
        storage.update(WindowState(
            id: windowID,
            frame: nil,
            isZoomed: false,
            isFullscreen: false,
            sessions: [
                QuickSessionSnapshot(
                    id: UUID(),
                    name: "Claude thread",
                    conversationID: UUID().uuidString,
                    configuration: .default
                ),
                QuickSessionSnapshot(
                    id: selectedID,
                    name: "Codex thread",
                    conversationID: conversationID,
                    configuration: .defaultConfiguration(for: .codex)
                ),
            ],
            selectedSessionID: selectedID
        ))

        let restored = AppState(
            requestedWindowStateID: windowID,
            storage: storage,
            configurationStorage: QuickSessionConfigurationStorage(stateFile: configurationFile)
        )

        XCTAssertEqual(restored.sessions.count, 2)
        XCTAssertEqual(restored.selectedSession?.id, selectedID)
        XCTAssertEqual(restored.selectedSession?.resumableSessionID, conversationID)
        XCTAssertEqual(restored.selectedSession?.launch, .resume(sessionId: conversationID))
        XCTAssertEqual(restored.selectedSession?.configuration.harness, .codex)
    }

    func testExplicitClaudeModelStillPassesModelAndEffort() {
        let configuration = QuickSessionConfiguration(
            modelID: "claude-sonnet-5",
            effort: .high,
            proxyEnabled: false
        )
        XCTAssertEqual(
            TerminalSession.launchArguments(configuration: configuration),
            ["-ilc", #"exec "$FINE_CCV" -y --model "$FINE_MODEL" --effort "$FINE_EFFORT""#]
        )
        XCTAssertEqual(
            TerminalSession.launchArguments(launch: .initialPrompt("hi"), configuration: configuration),
            ["-ilc", #"exec "$FINE_CCV" -y --model "$FINE_MODEL" --effort "$FINE_EFFORT" "$FINE_INITIAL_PROMPT""#]
        )
        XCTAssertEqual(
            TerminalSession.launchArguments(
                launch: .resume(sessionId: UUID().uuidString),
                configuration: configuration
            ),
            ["-ilc", #"exec "$FINE_CCV" -ry "$FINE_RESUME_SESSION_ID" --model "$FINE_MODEL" --effort "$FINE_EFFORT""#]
        )
    }

    func testOpenCodeLaunchAutoApprovesPermissions() {
        let plain = QuickSessionConfiguration.defaultConfiguration(for: .opencode)
        XCTAssertEqual(
            TerminalSession.launchArguments(configuration: plain),
            ["-ilc", #"exec "$FINE_OPENCODE" --auto"#]
        )
        XCTAssertEqual(
            TerminalSession.launchArguments(launch: .initialPrompt("hi"), configuration: plain),
            ["-ilc", #"exec "$FINE_OPENCODE" --auto --prompt "$FINE_INITIAL_PROMPT""#]
        )
        let pinned = QuickSessionConfiguration(
            harness: .opencode,
            modelID: "alibaba-token-plan/deepseek-v4-flash",
            effort: .high,
            proxyEnabled: true
        )
        XCTAssertEqual(
            TerminalSession.launchArguments(
                launch: .resume(sessionId: "ses_123"),
                configuration: pinned
            ),
            ["-ilc", #"exec "$FINE_OPENCODE" --auto --model "$FINE_MODEL" --session "$FINE_RESUME_SESSION_ID""#]
        )
        let environment = QuickSessionPolicy.applyingEnvironment(
            ["PATH": "/usr/bin", "ANTHROPIC_BASE_URL": "http://stale.example", "CCV_PROXY": "1"],
            launch: .blank,
            configuration: pinned
        )
        XCTAssertFalse(pinned.usesProxy)
        XCTAssertNil(environment["CCV_PROXY"])
        XCTAssertNil(environment["ANTHROPIC_BASE_URL"])
        XCTAssertEqual(environment["FINE_MODEL"], "alibaba-token-plan/deepseek-v4-flash")
        XCTAssertEqual(environment["FINE_OPENCODE"], QuickSessionPolicy.opencodeExecutablePath)
        XCTAssertTrue(environment["PATH"]?.contains(NSHomeDirectory() + "/.opencode/bin") == true)
    }

    func testPermissionSkipFlagsArePresentExactlyOnceForEveryLaunchMode() {
        let launches: [QuickLaunch] = [.blank, .initialPrompt("hello"), .resume(sessionId: "test"), .resumeLatest]
        for harness in [QuickHarness.codex, .opencode] {
            for launch in launches {
                let flag = harness == .codex ? "--dangerously-bypass-approvals-and-sandbox" : "--auto"
                let command = QuickSessionPolicy.launchCommand(
                    for: launch, configuration: .defaultConfiguration(for: harness)
                )
                XCTAssertEqual(command.components(separatedBy: flag).count - 1, 1)
            }
        }
        XCTAssertFalse(QuickSessionPolicy.launchCommand(for: .blank).contains("--auto"))
    }

    func testDefaultModeNeverUsesTheRouterEvenWhenProxyWasRequested() {
        let configuration = QuickSessionConfiguration(
            modelID: QuickModelOption.defaultID,
            effort: .max,
            proxyEnabled: true
        )
        XCTAssertFalse(configuration.usesProxy)
        let environment = QuickSessionPolicy.applyingEnvironment(
            ["ANTHROPIC_BASE_URL": "http://stale.example"],
            launch: .blank,
            configuration: configuration
        )
        XCTAssertEqual(environment["CCV_PROXY"], "0")
        XCTAssertNil(environment["ANTHROPIC_BASE_URL"])
    }

    func testPromptUsesEnvironmentInsteadOfShellInterpolation() {
        let prompt = #"따옴표 "와" $(touch /tmp/nope); 한글"#
        let launch = QuickLaunch.initialPrompt(prompt)
        XCTAssertEqual(
            TerminalSession.launchArguments(launch: launch),
            ["-ilc", #"exec "$FINE_CCV" -y "$FINE_INITIAL_PROMPT""#]
        )
        XCTAssertEqual(QuickSessionPolicy.environment(for: launch)["FINE_INITIAL_PROMPT"], prompt)
        XCTAssertFalse(QuickSessionPolicy.launchCommand(for: launch).contains("touch"))
        XCTAssertTrue(QuickSessionPolicy.workingDirectory.hasSuffix("/cld"))
    }

    func testResumeUsesEnvironmentAndCcvResumeMode() {
        let sessionId = UUID().uuidString.lowercased()
        let launch = QuickLaunch.resume(sessionId: sessionId)
        XCTAssertEqual(
            TerminalSession.launchArguments(launch: launch),
            ["-ilc", #"exec "$FINE_CCV" -ry "$FINE_RESUME_SESSION_ID""#]
        )
        XCTAssertEqual(
            QuickSessionPolicy.environment(for: launch)["FINE_RESUME_SESSION_ID"],
            sessionId
        )
    }

    func testProxyEnvironmentIsOnlyInjectedForProxySessions() {
        let inherited = [
            "PATH": "/usr/bin",
            "ANTHROPIC_BASE_URL": "http://stale.example",
            "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
            "CLAUDE_CODE_CHILD_SESSION": "1",
        ]
        let direct = QuickSessionPolicy.applyingEnvironment(
            inherited,
            launch: .blank,
            configuration: .default
        )
        XCTAssertNil(direct["ANTHROPIC_BASE_URL"])
        XCTAssertNil(direct["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"])
        XCTAssertNil(direct["CLAUDE_CODE_CHILD_SESSION"])
        XCTAssertEqual(direct["CLAUDE_CODE_FORCE_SESSION_PERSISTENCE"], "1")
        XCTAssertEqual(direct["CCV_PROXY"], "0")
        XCTAssertEqual(direct["FINE_CCV"], QuickSessionPolicy.ccvExecutablePath)
        XCTAssertTrue(direct["PATH"]?.hasPrefix(NSHomeDirectory() + "/.local/bin:/opt/homebrew/bin:") == true)

        let proxy = QuickSessionPolicy.applyingEnvironment(
            inherited,
            launch: .blank,
            configuration: QuickSessionConfiguration(
                modelID: "claude-codex-gpt-5.6-terra",
                effort: .xhigh,
                proxyEnabled: false
            )
        )
        XCTAssertEqual(proxy["ANTHROPIC_BASE_URL"], "http://127.0.0.1:4141")
        XCTAssertEqual(proxy["CCV_PROXY"], "1")
        XCTAssertEqual(proxy["FINE_MODEL"], "claude-codex-gpt-5.6-terra")
        XCTAssertEqual(proxy["FINE_EFFORT"], "xhigh")
    }

    func testNewConversationShowsHomeWithoutClosingOpenSessions() {
        let state = AppState()
        let session = TerminalSession()
        state.sessions = [session]
        state.selectedSession = session

        state.showHome()

        XCTAssertNil(state.selectedSession)
        XCTAssertEqual(state.sessions.map(\.id), [session.id])
        session.cleanup()
    }

    func testResumeLaunchForcesTopLevelTranscriptPersistence() {
        let sessionId = UUID().uuidString.lowercased()
        let environment = QuickSessionPolicy.applyingEnvironment(
            ["CLAUDE_CODE_CHILD_SESSION": "1"],
            launch: .resume(sessionId: sessionId),
            configuration: .default
        )

        XCTAssertNil(environment["CLAUDE_CODE_CHILD_SESSION"])
        XCTAssertEqual(environment["CLAUDE_CODE_FORCE_SESSION_PERSISTENCE"], "1")
        XCTAssertEqual(environment["FINE_RESUME_SESSION_ID"], sessionId)
    }

    func testRecentConversationSelectsAlreadyOpenResumeSession() {
        let sessionId = UUID().uuidString.lowercased()
        let state = AppState()
        let other = TerminalSession()
        let resumed = TerminalSession(
            name: "Existing title",
            launch: .resume(sessionId: sessionId)
        )
        state.sessions = [other, resumed]
        state.selectedSession = other

        state.resumeConversation(sessionId: sessionId)

        XCTAssertIdentical(state.selectedSession, resumed)
        XCTAssertEqual(state.sessions.count, 2)
    }

    @MainActor
    func testNativeRecentConversationResumesCorrectHarnessAndReusesOpenTab() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configs = QuickSessionConfigurationStorage(stateFile: directory.appendingPathComponent("config.json"))
        let state = AppState(storage: WindowStateStorage(stateFile: directory.appendingPathComponent("windows.json")), configurationStorage: configs)
        defer { state.sessions.forEach { $0.cleanup() } }
        for harness in [QuickHarness.codex, .opencode] {
            let id = harness == .codex ? UUID().uuidString : "ses_MixedCase123"
            // A stale configuration must not route a native Codex item through Claude.
            let pinned = QuickSessionConfiguration(harness: .opencode, modelID: "provider/model", effort: .high, proxyEnabled: false)
            configs.save(harness == .opencode ? pinned : .default, for: id)
            let conversation = QuickConversation(id: id, title: "Saved title", aiTitle: nil, modifiedAt: Date(), transcriptURL: nil, harness: harness)
            state.resumeConversation(conversation, startImmediately: false)
            let session = try XCTUnwrap(state.selectedSession)
            XCTAssertEqual(session.launch, .resume(sessionId: id))
            XCTAssertEqual(session.configuration.harness, harness)
            if harness == .opencode { XCTAssertEqual(session.configuration, pinned) }
            XCTAssertEqual(session.name, "Saved title")
            let count = state.sessions.count
            state.resumeConversation(conversation, startImmediately: false)
            XCTAssertIdentical(state.selectedSession, session)
            XCTAssertEqual(state.sessions.count, count)
        }
    }

    func testUnresolvedBlankSessionDoesNotClaimConversationIdentity() {
        XCTAssertFalse(TerminalSession().matchesConversation(sessionId: UUID().uuidString))
    }
}
