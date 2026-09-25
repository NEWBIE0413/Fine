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
                           prompts: [String] = [], passages: [String] = [], open: Bool = false) -> SessionFinder.Candidate {
        SessionFinder.Candidate(
            conversation: QuickConversation(id: id, title: title, aiTitle: nil,
                                            modifiedAt: Date(timeIntervalSince1970: 1_790_000_000), transcriptURL: nil),
            prompts: prompts, passages: passages, isOpen: open
        )
    }

    // MARK: - 후보

    /// 제목은 첫 요청에서 나온다. 대화가 흘러간 곳은 뒤의 요청과 본문에만 있다.
    func testDigestKeepsEveryRequestAndTheConversationTextButNotToolTraffic() throws {
        let huge = line(["type": "user", "message": ["role": "user",
                         "content": [["type": "tool_result", "content": String(repeating: "zeb ", count: 80_000)]]]])
        let url = try transcript(UUID().uuidString.lowercased(), lines: [
            user("이미지 분석해줘"),
            line(["type": "assistant", "message": ["role": "assistant",
                  "content": [["type": "text", "text": "아치의 ZEB는 두 브라우저를 흉내 낸 것입니다"]]]]),
            huge,
            user("<command-name>/model</command-name>"),
            user("스킬 동기화\n해줘"),
        ], modified: Date())

        let digest = SessionFinder.digest(claudeTranscript: url)
        XCTAssertEqual(digest.prompts, ["이미지 분석해줘", "스킬 동기화 해줘"])
        let text = String(decoding: digest.corpus, as: UTF8.self)
        XCTAssertTrue(text.contains("아치의 zeb는"), "assistant text is searchable, lowercased")
        XCTAssertFalse(text.contains("zeb zeb"), "tool output is not conversation")
    }

    func testKeywordsDropFillerWordsAndParticles() {
        XCTAssertEqual(SessionFinder.keywords(in: "zeb 브라우저 만든 세션 찾아줘"), ["zeb", "브라우저"])
        XCTAssertEqual(SessionFinder.keywords(in: "방콕 숙소를 정하던 대화"), ["방콕", "숙소", "정하던"])
    }

    /// 긴 대화는 처음부터 끝까지 고르게, 찾는 말이 든 요청은 빠짐없이.
    func testSampleSpansTheWholeConversationAndKeepsMatchingRequests() {
        let prompts = (0..<40).map { "요청 \($0)" } + ["zeb 설치해줘"] + (41..<60).map { "요청 \($0)" }
        let picked = SessionFinder.sample(prompts, terms: ["zeb"], count: 6)
        XCTAssertEqual(picked.first, "요청 0")
        XCTAssertEqual(picked.last, "요청 59")
        XCTAssertTrue(picked.contains("zeb 설치해줘"))
        XCTAssertLessThanOrEqual(picked.count, 6)
    }

    func testPassagesQuoteAroundTheTermWithoutBreakingCharacters() {
        let corpus = Data(("앞부분 " + String(repeating: "가", count: 300) + " 아치의 zeb는 두 브라우저를 흉내 냈다 "
                           + String(repeating: "나", count: 900) + " zeb 스킬 동기화").utf8)
        let found = SessionFinder.passages(in: corpus, terms: ["zeb"], limit: 3, radius: 40)
        XCTAssertEqual(found.count, 2, "two distant mentions, two passages")
        XCTAssertTrue(found[0].contains("아치의 zeb는"))
        XCTAssertFalse(found.joined().contains("\u{FFFD}"))
        XCTAssertEqual(SessionFinder.passages(in: corpus, terms: ["없는말"], limit: 3), [])
    }

    func testGatherMarksOpenTabsAndKeepsNewestFirst() throws {
        let older = "11111111-1111-4111-8111-111111111111"
        let newer = "22222222-2222-4222-8222-222222222222"
        try transcript(older, lines: [user("방콕 여행 계획")], modified: Date(timeIntervalSinceNow: -3_600))
        try transcript(newer, lines: [user("Mac 발열 문제"), user("팬 소리가 커")], modified: Date())

        let done = expectation(description: "gathered")
        var result: [SessionFinder.Candidate] = []
        var fractions: [Double] = []
        SessionFinder.gather(query: "팬 소리", openSessionIDs: [older], directory: directory, store: nil,
                             progress: { fractions.append($0) }) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(result.map(\.conversation.id), [newer, older])
        XCTAssertEqual(result.map(\.isOpen), [false, true])
        XCTAssertEqual(result.first?.prompts, ["Mac 발열 문제", "팬 소리가 커"])
        XCTAssertEqual(result.first?.passages.count, 1)
        XCTAssertEqual(fractions.last, 1, "reading reports its real share up to the end")
    }

    // MARK: - 질문

    func testPromptNumbersCandidatesAndCarriesQueryOpenTabsAndRecentLines() {
        let text = SessionFinder.prompt(query: "zeb 브라우저 만든 세션", candidates: [
            candidate("Mac 발열 문제"),
            candidate("이미지 분석", prompts: ["zeb 브라우저 띄워봐"], passages: ["…아치의 zeb는…"], open: true),
        ])
        XCTAssertTrue(text.contains("찾는 것: zeb 브라우저 만든 세션"))
        XCTAssertTrue(text.contains("[1] Mac 발열 문제 | Claude"))
        XCTAssertTrue(text.contains("[2] 이미지 분석 | Claude"))
        XCTAssertTrue(text.contains("| 열린 탭"))
        XCTAssertTrue(text.contains("요청: \"zeb 브라우저 띄워봐\""))
        XCTAssertTrue(text.contains("본문: …아치의 zeb는…"))
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
            candidate("오늘 추가한 옵시디언 문서 두 개", prompts: ["옵시디언 문서 정리", "스킬 동기화"],
                      passages: ["…아치의 zeb는 내가 이 두 브라우저를 야매로 구현한 결과야…"]),
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

    /// 이 기기의 실제 최근 대화로: 첫 읽기와 캐시된 두 번째 읽기가 얼마나 걸리는지, 그리고
    /// zeb를 다룬 대화가 본문 조각을 달고 후보에 오르는지. 켰을 때만 돈다.
    func testLiveGatherOnThisMachine() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FINE_LIVE_FIND"] == "1", "reads real transcripts")
        for round in 1...2 {
            let started = Date()
            let done = expectation(description: "gathered \(round)")
            var result: [SessionFinder.Candidate] = []
            SessionFinder.gather(query: "zeb 브라우저 만든 세션", openSessionIDs: []) {
                result = $0
                done.fulfill()
            }
            wait(for: [done], timeout: 120)
            let prompt = SessionFinder.prompt(query: "zeb 브라우저 만든 세션", candidates: result)
            let withPassages = result.filter { !$0.passages.isEmpty }
            print("LIVE gather round \(round): \(Int(Date().timeIntervalSince(started) * 1000))ms,",
                  "\(result.count) candidates, prompt \(prompt.count) chars, \(withPassages.count) with passages")
            guard round == 2 else { continue }
            let asked = Date()
            let answered = expectation(description: "answered")
            SessionFinder.ask(query: "zeb 브라우저 만든 세션", candidates: result) { outcome in
                print("LIVE ask: \(Int(Date().timeIntervalSince(asked) * 1000))ms →", outcome)
                answered.fulfill()
            }
            wait(for: [answered], timeout: 120)
        }
    }
}
