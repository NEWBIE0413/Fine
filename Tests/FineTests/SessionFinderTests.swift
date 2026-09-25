import XCTest
@testable import Fine

final class SessionFinderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fine-finder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func line(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func user(_ text: String) -> String {
        line(["type": "user", "message": ["role": "user", "content": text]])
    }

    @discardableResult
    private func transcript(_ id: String, lines: [String], modified: Date) throws -> URL {
        let url = directory.appendingPathComponent("\(id).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    private func candidate(_ title: String, id: String = UUID().uuidString.lowercased(),
                           prompts: [String] = [], open: Bool = false) -> SessionFinder.Candidate {
        SessionFinder.Candidate(
            conversation: QuickConversation(id: id, title: title, aiTitle: nil,
                                            modifiedAt: Date(timeIntervalSince1970: 1_790_000_000), transcriptURL: nil),
            recentPrompts: prompts, isOpen: open
        )
    }

    // MARK: - 후보

    /// 제목은 첫 요청에서 나온다. 대화가 나중에 어디로 갔는지는 꼬리의 사용자 요청에만 있다.
    func testRecentPromptsComeFromTheTailAndSkipToolTraffic() throws {
        let url = try transcript(UUID().uuidString.lowercased(), lines: [
            user("이미지 분석해줘"),
            line(["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text": "네"]]]]),
            line(["type": "user", "message": ["role": "user", "content": [["type": "tool_result", "content": "ls output"]]]]),
            user("<command-name>/model</command-name>"),
            user("zeb 브라우저를\n아치에서 띄워봐"),
            user("다크모드 체크박스가 흰색이야"),
        ], modified: Date())

        let prompts = SessionFinder.recentPrompts(in: url, count: 2)
        XCTAssertEqual(prompts, ["zeb 브라우저를 아치에서 띄워봐", "다크모드 체크박스가 흰색이야"])
    }

    /// 거대한 transcript에서도 꼬리만 읽는다. 잘린 첫 줄은 버려진다.
    func testRecentPromptsReadOnlyTheTail() throws {
        let filler = line(["type": "assistant", "message": ["role": "assistant",
                           "content": [["type": "text", "text": String(repeating: "x", count: 4_000)]]]])
        let url = try transcript(UUID().uuidString.lowercased(),
                                 lines: [user("맨 처음 요청")] + Array(repeating: filler, count: 200) + [user("마지막 요청")],
                                 modified: Date())
        XCTAssertEqual(SessionFinder.recentPrompts(in: url, tailBytes: 20_000), ["마지막 요청"])
    }

    func testGatherMarksOpenTabsAndKeepsNewestFirst() throws {
        let older = "11111111-1111-4111-8111-111111111111"
        let newer = "22222222-2222-4222-8222-222222222222"
        try transcript(older, lines: [user("방콕 여행 계획")], modified: Date(timeIntervalSinceNow: -3_600))
        try transcript(newer, lines: [user("Mac 발열 문제"), user("팬 소리가 커")], modified: Date())

        let done = expectation(description: "gathered")
        var result: [SessionFinder.Candidate] = []
        SessionFinder.gather(openSessionIDs: [older], directory: directory, store: nil) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(result.map(\.conversation.id), [newer, older])
        XCTAssertEqual(result.map(\.isOpen), [false, true])
        XCTAssertEqual(result.first?.recentPrompts, ["Mac 발열 문제", "팬 소리가 커"])
    }

    // MARK: - 질문

    func testPromptNumbersCandidatesAndCarriesQueryOpenTabsAndRecentLines() {
        let text = SessionFinder.prompt(query: "zeb 브라우저 만든 세션", candidates: [
            candidate("Mac 발열 문제"),
            candidate("이미지 분석", prompts: ["zeb 브라우저 띄워봐"], open: true),
        ])
        XCTAssertTrue(text.contains("찾는 것: zeb 브라우저 만든 세션"))
        XCTAssertTrue(text.contains("[1] Mac 발열 문제 | Claude"))
        XCTAssertTrue(text.contains("[2] 이미지 분석 | Claude"))
        XCTAssertTrue(text.contains("| 열린 탭"))
        XCTAssertTrue(text.contains("최근: \"zeb 브라우저 띄워봐\""))
    }

    /// 찾기 질문은 도구도, 기록도, 라우터도 없이 순정 Claude로 한 번 묻고 끝나야 한다.
    func testInvocationIsToolFreeUnrecordedAndDirect() {
        let arguments = SessionFinder.arguments()
        XCTAssertEqual(Array(arguments.prefix(3)), ["-p", "--model", "haiku"])
        XCTAssertTrue(arguments.contains("--no-session-persistence"))
        XCTAssertEqual(Array(arguments.suffix(2)), ["--tools", ""], "--tools is variadic; it must come last")

        let environment = SessionFinder.environment(base: [
            "ANTHROPIC_BASE_URL": "http://127.0.0.1:4141", "CCV_PROXY": "1", "PATH": "/usr/bin",
        ])
        XCTAssertNil(environment["ANTHROPIC_BASE_URL"])
        XCTAssertNil(environment["CCV_PROXY"])
        XCTAssertNil(environment["CLAUDE_CODE_FORCE_SESSION_PERSISTENCE"])
        XCTAssertEqual(environment["MAX_THINKING_TOKENS"], "0")
    }

    // MARK: - 답

    private func output(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    func testParsePicksTheNumberedCandidate() {
        let list = [candidate("A"), candidate("B")]
        let outcome = SessionFinder.parse(output([
            "is_error": false, "structured_output": ["pick": 2, "reason": "B가 맞습니다"],
        ]), candidates: list)
        XCTAssertEqual(outcome, .found(list[1], reason: "B가 맞습니다"))
    }

    func testParseTreatsNullAndOutOfRangeAsNotFound() {
        let list = [candidate("A")]
        XCTAssertEqual(SessionFinder.parse(output([
            "structured_output": ["pick": NSNull(), "reason": "없음"],
        ]), candidates: list), .notFound(reason: "없음"))
        guard case .notFound = SessionFinder.parse(output([
            "structured_output": ["pick": 7, "reason": ""],
        ]), candidates: list) else { return XCTFail("a number outside the list must not open anything") }
    }

    func testParseSurfacesClaudeErrors() {
        guard case .failed(let message) = SessionFinder.parse(output([
            "is_error": true, "result": "Invalid API key · Please run /login",
        ]), candidates: [candidate("A")]) else { return XCTFail() }
        XCTAssertTrue(message.contains("/login"))
        guard case .failed = SessionFinder.parse(Data("not json".utf8), candidates: []) else { return XCTFail() }
    }

    func testEmptyListNeverCallsClaude() {
        let done = expectation(description: "answered")
        SessionFinder.ask(query: "아무거나", candidates: [], executable: "/nonexistent/claude") { outcome in
            guard case .notFound = outcome else { return XCTFail("\(outcome)") }
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    /// 실제 Claude Code로 한 번 묻는다. 돈과 네트워크가 드니 켰을 때만 돈다:
    /// `FINE_LIVE_FIND=1 swift test --filter SessionFinderTests/testLiveHaikuPicksTheMatchingConversation`
    func testLiveHaikuPicksTheMatchingConversation() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FINE_LIVE_FIND"] == "1", "live Claude call")
        let list = [
            candidate("Mac 발열 문제", prompts: ["팬 소리가 너무 커"]),
            candidate("이미지 분석", prompts: ["zeb 브라우저를 아치에 설치하고 띄워봐", "다크모드 색 정리"]),
            candidate("방콕 여행 계획", prompts: ["숙소는 아속 근처"]),
        ]
        let done = expectation(description: "answered")
        var result: SessionFinder.Outcome?
        SessionFinder.ask(query: "zeb 브라우저 만든 세션", candidates: list) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 90)
        guard case .found(let picked, let reason) = try XCTUnwrap(result) else {
            return XCTFail("\(String(describing: result))")
        }
        XCTAssertEqual(picked, list[1])
        print("LIVE reason:", reason)
    }
}
