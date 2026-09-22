import Foundation

/// 홈 화면 맨 위의 한 줄.
///
/// kev(System One)는 글을 쓰지 못한다 — 토큰을 만드는 장치가 아예 없고, 주어진 후보
/// 중에서 고를 뿐이다. 그래서 문장은 여기 미리 적어두고, 최근 대화 목록을 보여준 뒤
/// "지금 이 사람의 작업에 무엇이 맞는가"만 묻는다. 고르는 일은 85ms에 끝나고 공짜다.
///
/// kev가 없거나 늦으면 날짜로 하나를 집는다. 인사말 때문에 홈 화면이 기다리는 일은 없다.
struct HomeGreeting: Equatable {
    /// `{title}` 자리에 최근 대화 제목이 들어간다. kev는 말을 만들지 못하므로
    /// 빈칸을 채우는 것은 생성이 아니라 이미 있는 제목을 가져다 놓는 일이다.
    let template: String
    var needsTitle: Bool { template.contains("{title}") }

    /// 제목을 넣고 조사를 맞춘다. 한국어는 앞말의 받침에 따라 조사가 달라지므로,
    /// 템플릿에 고정해두면 절반은 틀린 문장이 된다.
    func rendered(title: String?) -> String {
        guard needsTitle else { return template }
        guard let title, !title.isEmpty else { return HomeGreeting.titleless.template }
        var line = template.replacingOccurrences(of: "{title}", with: "「\(title)」")
        for (pair, withFinal, without) in HomeGreeting.particles {
            // 제목이 「」로 감싸이므로 조사 앞 글자는 닫는 괄호다. 실제 마지막 글자로 판단한다.
            line = line.replacingOccurrences(
                of: "「\(title)」\(pair)",
                with: "「\(title)」" + (HomeGreeting.hasFinalConsonant(title) ? withFinal : without)
            )
        }
        return line
    }

    /// 템플릿에는 대표형만 적고 여기서 고른다.
    private static let particles: [(String, String, String)] = [
        ("은/는", "은", "는"),
        ("이/가", "이", "가"),
        ("을/를", "을", "를"),
        ("과/와", "과", "와"),
    ]

    /// 마지막 글자에 받침이 있는지. 한글 음절은 0xAC00부터 28개 종성 단위로 배열된다.
    static func hasFinalConsonant(_ text: String) -> Bool {
        guard let last = text.unicodeScalars.reversed().first(where: {
            CharacterSet.alphanumerics.contains($0)
        }) else { return false }
        let value = last.value
        guard (0xAC00...0xD7A3).contains(value) else {
            // 한글이 아니면 받침을 알 수 없다. 숫자·영문은 흔한 쪽으로 둔다.
            return false
        }
        return (value - 0xAC00) % 28 != 0
    }

    static let titleless = HomeGreeting(
        template: "이어서 해볼까요?")

    static let finished = HomeGreeting(template: "{title}은/는 잘 마무리됐나요?")
    static let ongoing = HomeGreeting(template: "{title}, 이어서 해볼까요?")
    static let stuck = HomeGreeting(template: "{title}이/가 아직 안 풀렸군요.")
    static let shipping = HomeGreeting(template: "{title}, 오늘 끝내볼까요?")
    static let writing = HomeGreeting(template: "{title}, 이어서 써볼까요?")
    /// 개인적인 일은 끝난 뒤에 묻는 말과 진행 중에 묻는 말이 다르다.
    static let personalPast = HomeGreeting(template: "{title}은/는 잘 다녀오셨어요?")
    static let personalNow = HomeGreeting(template: "{title}은/는 어떻게 돼가요?")
    static let scattered = HomeGreeting(template: "오늘은 어디부터 볼까요?")
    static let startFresh = HomeGreeting(template: "빈 페이지부터.")

    static let candidates: [HomeGreeting] = [
        finished, ongoing, stuck, shipping, writing, personalPast, personalNow, scattered, startFresh,
    ]

    /// 사실만으로 고른다. 제목의 뜻은 보지 않는다 — 그건 kev의 몫이다.
    static func byFacts(_ conversations: [QuickConversation], now: Date = Date()) -> HomeGreeting {
        guard let newest = conversations.first else { return .startFresh }
        let days = now.timeIntervalSince(newest.modifiedAt) / 86_400
        if conversations.count >= 4 { return .scattered }
        if days >= 3 { return .finished }
        return .ongoing
    }

    static let fallback = HomeGreeting(
        template: "빈 페이지부터.")

    /// 대화 제목을 kev의 학습 범위(384토큰) 안에 들어가게 줄인다.
    static func state(from conversations: [QuickConversation], now: Date = Date()) -> String {
        guard !conversations.isEmpty else {
            return "A coding workspace with no past conversations."
        }
        let recent = conversations.prefix(8)
        let titles = recent
            .map { $0.aiTitle ?? $0.title }
            .map { String($0.prefix(60)).replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "; ")
        let hours = Int(now.timeIntervalSince(conversations[0].modifiedAt) / 3600)
        let age = hours < 1 ? "minutes ago" : hours < 48 ? "\(hours) hours ago" : "\(hours / 24) days ago"
        // 결정적인 사실(언제·몇 개)을 앞에 둔다. 제목 더미 뒤에 묻히면 읽히지 않는다.
        return "The newest conversation was last touched \(age). "
            + "There are \(conversations.count) recent conversations. "
            + "Newest first, their titles are: \(titles)"
    }

    /// 날짜로 하나를 집는다. 매번 같은 문장이 뜨지 않으면서도, 같은 날에는 바뀌지 않는다.
    static func deterministic(for date: Date = Date()) -> HomeGreeting {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return candidates[abs(day) % candidates.count]
    }
}

/// 인사말을 고르는 일은 대부분 정확한 사실이다 — 며칠 전인지, 몇 개인지는
/// 모델에게 물을 값이 아니라 이미 손에 있는 값이다. 그래서 Swift가 고른다.
///
/// 흐릿한 것은 하나뿐이다: "이 제목들이 안 풀린 일인가". 6지선다를 시키면
/// kev-0.6B는 확신도 0.5를 못 넘기지만(실측), 이 예/아니오 하나는 0.9 대 0.02로 가른다.
/// 한국어 제목에서도 그렇다. 모델에게는 모델이 할 수 있는 결정만 준다.
@MainActor
final class HomeGreetingPicker: ObservableObject {
    static let shared = HomeGreetingPicker()

    /// 화면에 그대로 나가는 완성된 한 줄.
    @Published private(set) var line: String = HomeGreeting.deterministic().template
    @Published private(set) var note: String = ""

    private var title: String?
    /// kev에게 보여줄 제목 묶음. 열린 탭이 있으면 그쪽을 먼저 쓴다.
    private var titles = ""

    /// 한 번 고르면 세션 내내 유지한다. 홈으로 돌아올 때마다 문장이 바뀌면
    /// 읽는 자리가 아니라 깜빡이는 자리가 된다.
    private var resolved = false

    func refreshIfNeeded(conversations: [QuickConversation], openTabs: [String] = []) {
        // 스캐너는 주기적으로 발행한다. 같은 값을 다시 쓰면 홈 화면이 통째로 다시 그려진다.
        let freshNote = Self.note(for: conversations)
        if freshNote != note { note = freshNote }
        title = Self.mentionableTitle(from: conversations, openTabs: openTabs)
        titles = Self.titles(conversations: conversations, openTabs: openTabs)
        guard !resolved else { return }
        // 대화 목록은 뒤늦게 도착한다. 비어 있는 첫 호출에서 잠가버리면
        // 목록이 실제로 비었을 때의 문장("빈 페이지부터")이 영영 굳는다.
        // 목록이 끝내 비어 있으면 그 문장이 맞으므로, 그대로 두고 잠그지만 않는다.
        guard !conversations.isEmpty else {
            line = HomeGreeting.startFresh.template
            return
        }
        resolved = true
        line = HomeGreeting.byFacts(conversations).rendered(title: title)
        Task { await resolveReading(conversations: conversations) }
    }


    /// 제목의 성격을 읽어 문장을 고른다. 사실(언제·몇 개)은 이미 반영돼 있고,
    /// 여기서는 kev만 답할 수 있는 것 — 그 일이 어떤 종류인가 — 을 얹는다.
    private func resolveReading(conversations: [QuickConversation]) async {
        guard !titles.isEmpty else { return }
        guard let reading = await Self.askReading(titles: titles) else { return }
        guard let bucket = reading.strongest() else { return }
        let stale = Self.isStale(conversations)
        let greeting: HomeGreeting
        switch bucket {
        case "stuck": greeting = .stuck
        case "shipping": greeting = .shipping
        case "writing": greeting = .writing
        // 개인적인 일은 끝난 뒤와 진행 중에 묻는 말이 다르다. 그 구분은 날짜가 안다.
        case "personal": greeting = stale ? .personalPast : .personalNow
        default: return
        }
        line = greeting.rendered(title: title)
    }

    static func isStale(_ conversations: [QuickConversation], now: Date = Date()) -> Bool {
        guard let newest = conversations.first else { return false }
        return now.timeIntervalSince(newest.modifiedAt) / 86_400 >= 1
    }

    /// 지금 열어둔 탭이 있으면 그 이름을 쓴다. 최근 목록은 과거고, 열린 탭은 현재다.
    static func titles(conversations: [QuickConversation], openTabs: [String]) -> String {
        let names = openTabs.isEmpty
            ? conversations.prefix(6).map { $0.aiTitle ?? $0.title }
            : Array(openTabs.prefix(6))
        guard let first = names.first else { return "" }
        let rest = names.dropFirst().joined(separator: "; ")
        return rest.isEmpty
            ? "The active conversation is titled: \(first)."
            : "The active conversation is titled: \(first). Other open ones: \(rest)"
    }

    /// 문장에 넣어도 읽히는 제목만 쓴다. 너무 길면 한 줄이 문장이 아니라 목록이 된다.
    static func mentionableTitle(from conversations: [QuickConversation], openTabs: [String] = []) -> String? {
        let candidate = openTabs.first ?? conversations.first.map { $0.aiTitle ?? $0.title }
        guard let candidate else { return nil }
        let raw = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.count <= 24 else { return nil }
        return raw
    }

    static func note(for conversations: [QuickConversation]) -> String {
        guard let newest = conversations.first else { return "새로 시작하는 자리" }
        let hours = Int(Date().timeIntervalSince(newest.modifiedAt) / 3600)
        let age = hours < 1 ? "방금 전" : hours < 48 ? "\(hours)시간 전" : "\(hours / 24)일 전"
        return "최근 대화 \(conversations.count)개 · \(age)"
    }

    /// 제목이 어떤 성격인지. 전부 예/아니오다 — 6지선다는 이 모델이 못 한다(실측).
    struct Reading {
        var stuck = 0.0
        var personal = 0.0
        var writing = 0.0
        var shipping = 0.0

        /// 가장 센 신호 하나만 쓴다. 둘 다 애매하면 아무것도 고르지 않는다.
        func strongest(threshold: Double = 0.6) -> String? {
            let scored = [("stuck", stuck), ("shipping", shipping),
                          ("personal", personal), ("writing", writing)]
            guard let top = scored.max(by: { $0.1 < $1.1 }), top.1 >= threshold else { return nil }
            return top.0
        }
    }

    /// QuickAutoRouter와 같은 서버·같은 요청 모양이다. 질문 넷이 forward pass 하나를
    /// 나눠 쓰므로, 하나만 물을 때와 비용이 사실상 같다 (실측 64ms).
    static func askReading(titles: String) async -> Reading? {
        let body: [String: Any] = [
            "model": "kev-latest",
            "state": titles,
            "questions": [
                "stuck": ["type": "noul", "instructions":
                    "Do these titles describe something broken, failing, or not yet working?"],
                "personal": ["type": "noul", "instructions":
                    "Are these titles about travel, food, errands or personal life "
                        + "rather than software work?"],
                "writing": ["type": "noul", "instructions":
                    "Are these titles about writing, reading, research or documents "
                        + "rather than building software?"],
                "shipping": ["type": "noul", "instructions":
                    "Do these titles describe finishing, releasing or shipping something?"],
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: QuickAutoRouter.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 인사말 때문에 홈 화면이 기다리게 두지 않는다.
        request.timeoutInterval = 1.5
        request.httpBody = data
        guard let (responseData, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let answers = json["answers"] as? [String: Any] else { return nil }
        func value(_ key: String) -> Double {
            (answers[key] as? [String: Any])?["noul"] as? Double ?? 0
        }
        return Reading(
            stuck: value("stuck"), personal: value("personal"),
            writing: value("writing"), shipping: value("shipping")
        )
    }
}
