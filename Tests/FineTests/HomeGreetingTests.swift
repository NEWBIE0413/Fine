import XCTest
@testable import Fine

final class HomeGreetingTests: XCTestCase {
    /// 한국어 조사는 앞말의 받침에 따라 달라진다. 템플릿에 고정하면 절반이 틀린다.
    func testParticleFollowsTheFinalConsonant() {
        XCTAssertTrue(HomeGreeting.hasFinalConsonant("방콕 여행 계획"))   // 획 → ㄱ
        XCTAssertTrue(HomeGreeting.hasFinalConsonant("이미지 분석"))      // 석 → ㄱ
        XCTAssertFalse(HomeGreeting.hasFinalConsonant("냉장 한돈 구우기")) // 기 → 없음
        XCTAssertFalse(HomeGreeting.hasFinalConsonant("방콕 여행 계획하기"))
    }

    func testRenderedLineUsesTheRightParticle() {
        let finished = HomeGreeting.finished
        XCTAssertEqual(finished.rendered(title: "이미지 분석"), "「이미지 분석」은 잘 마무리됐나요?")
        XCTAssertEqual(finished.rendered(title: "냉장 한돈 구우기"), "「냉장 한돈 구우기」는 잘 마무리됐나요?")

        let stuck = HomeGreeting.stuck
        XCTAssertEqual(stuck.rendered(title: "방콕 여행 계획"), "「방콕 여행 계획」이 아직 안 풀렸군요.")
    }

    /// 제목이 없거나 너무 길면 문장이 아니라 목록이 된다. 빈칸 없는 문장으로 물러난다.
    func testFallsBackWhenThereIsNoUsableTitle() {
        let withSlot = HomeGreeting.ongoing
        XCTAssertEqual(withSlot.rendered(title: nil), HomeGreeting.titleless.template)
        XCTAssertEqual(withSlot.rendered(title: ""), HomeGreeting.titleless.template)

        let plain = HomeGreeting.startFresh
        XCTAssertFalse(plain.needsTitle)
        XCTAssertEqual(plain.rendered(title: "무엇이든"), "빈 페이지부터.")
    }

    /// 며칠 전인지, 몇 개인지는 모델에게 물을 값이 아니다. 사실로 고른다.
    func testFactsChooseTheLineWithoutAskingTheModel() {
        let now = Date()
        func conversation(_ title: String, hoursAgo: Double) -> QuickConversation {
            QuickConversation(
                id: UUID().uuidString, title: title, aiTitle: nil,
                modifiedAt: now.addingTimeInterval(-hoursAgo * 3600),
                transcriptURL: nil, harness: .claude
            )
        }
        XCTAssertEqual(HomeGreeting.byFacts([], now: now), HomeGreeting.startFresh)
        XCTAssertEqual(
            HomeGreeting.byFacts([conversation("어제 하던 것", hoursAgo: 2)], now: now), HomeGreeting.ongoing
        )
        XCTAssertEqual(
            HomeGreeting.byFacts([conversation("묵은 것", hoursAgo: 24 * 5)], now: now), HomeGreeting.finished
        )
        XCTAssertEqual(
            HomeGreeting.byFacts((0..<4).map { conversation("일 \($0)", hoursAgo: 1) }, now: now),
            HomeGreeting.scattered
        )
    }
}
