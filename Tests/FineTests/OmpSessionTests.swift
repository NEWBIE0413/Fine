import XCTest
@testable import Fine

final class OmpSessionTests: XCTestCase {
    /// 실제 omp가 쓴 파일의 머리 부분. 레코드 종류와 키 이름을 그대로 옮겼다.
    private let sample = """
    {"type": "title", "v": 1, "title": "", "updatedAt": "2026-09-22T14:24:31.398Z", "pad": "   "}
    {"type": "session", "version": 3, "id": "01a0c981-06a6-7465-ba1a-38a68343a47a", "timestamp": "2026-09-22T14:24:31.398Z", "cwd": "/Users/tmdgus/cld"}
    {"type": "model_change", "id": "x", "parentId": null, "model": "openrouter/z-ai/glm-5.3-flash", "timestamp": "2026-09-22T14:24:32.000Z"}
    {"type": "title", "v": 1, "title": "omp 첫 대화", "updatedAt": "2026-09-22T14:25:00.000Z", "pad": "   "}
    {"type": "message", "id": "m1", "parentId": null, "timestamp": "2026-09-22T14:24:31.567Z", "message": {"role": "user", "content": [{"type": "text", "text": "hi"}], "attribution": "user", "timestamp": 1790087071567}}
    """

    private var url: URL { URL(fileURLWithPath: "/tmp/2026-09-22T14-24-31-398Z_01a0c981.jsonl") }

    /// 디렉터리 슬러그를 역산하지 않는다 — session 레코드의 cwd가 정답을 들고 있다.
    func testSessionRecordCarriesIdentityAndDirectory() throws {
        let session = try XCTUnwrap(OmpSessionResolver.parse(sample, url: url))
        XCTAssertEqual(session.id, "01a0c981-06a6-7465-ba1a-38a68343a47a")
        XCTAssertEqual(session.cwd, "/Users/tmdgus/cld")
        // UUIDv7도 UUID다. Fine의 기존 세션 ID 검증이 그대로 통한다.
        XCTAssertNotNil(UUID(uuidString: session.id))
        XCTAssertTrue(QuickSessionIdentifier.isValid(session.id, for: .omp))
    }

    /// 제목은 같은 파일 안에서 여러 번 덮어써진다. 마지막 것이 지금 제목이다.
    func testLastTitleWinsAndBlankTitlesAreIgnored() throws {
        let session = try XCTUnwrap(OmpSessionResolver.parse(sample, url: url))
        XCTAssertEqual(session.title, "omp 첫 대화")
    }

    func testFileWithoutASessionRecordIsNotASession() {
        XCTAssertNil(OmpSessionResolver.parse("""
        {"type": "title", "v": 1, "title": "고아", "updatedAt": "2026-09-22T14:24:31.398Z"}
        """, url: url))
    }

    /// omp는 ISO 문자열과 epoch 밀리초를 섞어 쓴다.
    func testBothTimestampShapesParse() {
        XCTAssertNotNil(OmpSessionResolver.date("2026-09-22T14:24:31.398Z"))
        XCTAssertEqual(
            OmpSessionResolver.date(1_790_087_071_567.0)?.timeIntervalSince1970 ?? 0,
            1_790_087_071.567, accuracy: 0.01
        )
        XCTAssertNil(OmpSessionResolver.date(nil))
    }
}

extension OmpSessionTests {
    /// 대화만 남긴다. thinking 블록은 과정이지 대화가 아니고, 도구 호출도 아니다.
    func testTranscriptKeepsConversationTextOnly() throws {
        let jsonl = """
        {"type": "session", "version": 3, "id": "01a0c981-06a6-7465-ba1a-38a68343a47a", "timestamp": "2026-09-22T14:24:31.398Z", "cwd": "/tmp"}
        {"type": "message", "timestamp": "2026-09-22T14:24:31.567Z", "message": {"role": "user", "content": [{"type": "text", "text": "안녕"}]}}
        {"type": "message", "timestamp": "2026-09-22T14:24:33.000Z", "message": {"role": "assistant", "content": [{"type": "thinking", "thinking": "간단한 인사다"}, {"type": "text", "text": "네, 말씀하세요"}]}}
        {"type": "model_change", "model": "openrouter/z-ai/glm-5.3-flash", "timestamp": "2026-09-22T14:24:32.000Z"}
        {"type": "message", "timestamp": "2026-09-22T14:24:34.000Z", "message": {"role": "assistant", "content": [{"type": "thinking", "thinking": "생각만 하고 말은 안 한 턴"}]}}
        """
        let messages = HarnessTranscript.parseOmp(Data(jsonl.utf8))
        XCTAssertEqual(messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(messages.map(\.text), ["안녕", "네, 말씀하세요"])
        XCTAssertNotNil(messages.first?.timestamp)
    }
}
