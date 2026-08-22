import XCTest
@testable import Fine

final class QuickSessionTests: XCTestCase {
    func testSessionUsesFriendlyInitialNameAndDirectClaudePTY() {
        XCTAssertEqual(QuickSessionPolicy.initialSessionName, "새 대화 세션")
        XCTAssertEqual(
            TerminalSession.launchArguments(),
            ["-lc", #"exec "$SM_CCV" -y --model "$SM_MODEL" --effort "$SM_EFFORT""#]
        )
    }

    func testPromptUsesEnvironmentInsteadOfShellInterpolation() {
        let prompt = #"따옴표 "와" $(touch /tmp/nope); 한글"#
        let launch = QuickLaunch.initialPrompt(prompt)
        XCTAssertEqual(
            TerminalSession.launchArguments(launch: launch),
            ["-lc", #"exec "$SM_CCV" -y --model "$SM_MODEL" --effort "$SM_EFFORT" "$SM_INITIAL_PROMPT""#]
        )
        XCTAssertEqual(QuickSessionPolicy.environment(for: launch)["SM_INITIAL_PROMPT"], prompt)
        XCTAssertFalse(QuickSessionPolicy.launchCommand(for: launch).contains("touch"))
        XCTAssertTrue(QuickSessionPolicy.workingDirectory.hasSuffix("/cld"))
    }

    func testResumeUsesEnvironmentAndCcvResumeMode() {
        let sessionId = UUID().uuidString.lowercased()
        let launch = QuickLaunch.resume(sessionId: sessionId)
        XCTAssertEqual(
            TerminalSession.launchArguments(launch: launch),
            ["-lc", #"exec "$SM_CCV" -ry "$SM_RESUME_SESSION_ID" --model "$SM_MODEL" --effort "$SM_EFFORT""#]
        )
        XCTAssertEqual(
            QuickSessionPolicy.environment(for: launch)["SM_RESUME_SESSION_ID"],
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
        XCTAssertEqual(direct["SM_CCV"], QuickSessionPolicy.ccvExecutablePath)
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
        XCTAssertEqual(proxy["SM_MODEL"], "claude-codex-gpt-5.6-terra")
        XCTAssertEqual(proxy["SM_EFFORT"], "xhigh")
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
        XCTAssertEqual(environment["SM_RESUME_SESSION_ID"], sessionId)
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

    func testUnresolvedBlankSessionDoesNotClaimConversationIdentity() {
        XCTAssertFalse(TerminalSession().matchesConversation(sessionId: UUID().uuidString))
    }
}
