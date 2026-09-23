import Foundation

/// 프롬프트를 보고 모델과 effort를 고른다. 판정은 로컬 kev 서버(System One 모델)가 한다.
///
/// 왜 세션 시작 시점에만 고르는가: Fine의 탭은 `ccv --model … --effort …`로 띄운
/// 일회성 PTY다. 모델을 도중에 바꾸면 prompt cache가 통째로 날아가므로, 어차피
/// 세션 단위로 고정하는 이 구조가 캐시 측면에서 옳다. 턴마다 effort만 바꾸는 것은
/// 하네스가 per-turn 설정을 열어준 뒤의 이야기다.
///
/// 설계상 자른 corner:
///   - Claude 하네스만 라우팅한다. Codex/OpenCode는 effort 체계가 달라 따로 검증해야 한다.
///   - 응답이 늦으면 사용자가 마지막에 쓰던 설정으로 간다. 대화 시작을 라우터가 막는 일은 없다.
enum QuickAutoRouter {
    /// 모델 피커에서 이 항목을 고르면 라우팅이 켜진다. 구체 모델을 고르면 라우팅은 멈춘다.
    static let autoModelID = "fine-auto"

    static let endpoint = URL(string: "http://127.0.0.1:8009/v1/systemone")!
    /// 워엄 상태의 kev는 ~85ms다. 콜드 첫 요청은 3초가 넘으므로 기다리지 않고 포기한다.
    static let timeout: TimeInterval = 0.8
    /// kev 학습이 state 384토큰까지만 커버한다. 그 안에 들어가도록 자른다.
    static let maxStateChars = 1200

    static func autoOption(for harness: QuickHarness) -> QuickModelOption {
        QuickModelOption(
            id: autoModelID,
            displayName: "자동",
            supportedEfforts: [],
            harness: harness
        )
    }

    // MARK: - 판정

    struct Decision {
        var modelID: String
        var effort: QuickEffort
        /// 라우터가 실제로 판단했는지, 폴백인지.
        var routed: Bool
        var reason: String
    }

    /// 옵션 순서는 절대 바꾸지 말 것 — 순서가 답을 바꾼다.
    private static let effortCriteria: [(String, String)] = [
        ("minimal", "Mechanical step: renaming, formatting, applying an already-decided edit"),
        ("low", "Simple lookup or a small local change with an obvious fix"),
        ("medium", "Needs to read several places and reason about how they connect"),
        ("high", "A design or architecture decision, a hard bug, or work with no obvious answer"),
    ]

    /// 사용자가 "자동"을 고른 세션의 설정을 정한다.
    /// 실패하면 `fallback`을 그대로 돌려준다 — 대화 시작은 어떤 경우에도 막지 않는다.
    static func resolve(
        prompt: String,
        available: [QuickModelOption],
        fallback: QuickSessionConfiguration
    ) async -> QuickSessionConfiguration {
        guard fallback.harness == .claude else { return fallback }
        // 컴포저 목록은 몇 분 단위로만 갱신된다. 오늘 나온 모델을 바로 쓰려면 판정 순간에
        // Claude Code가 직접 받아 둔 카탈로그를 한 번 더 읽는다(로컬 파일이라 kev 대기에 묻힌다).
        async let fresh = Task.detached(priority: .userInitiated) { ClaudeModelCatalog.discover() }.value
        async let pending = ask(state: state(from: prompt))
        let tiers = ModelTiers(available: available + (await fresh))
        let decision: Decision
        if let answer = await pending {
            decision = map(answer, tiers: tiers)
        } else {
            decision = Decision(modelID: tiers.mid, effort: .high, routed: false, reason: "kev 응답 없음")
        }
        log(prompt: prompt, decision: decision)
        return QuickSessionConfiguration(
            harness: .claude,
            modelID: decision.modelID,
            effort: decision.effort,
            proxyEnabled: false
        )
    }

    /// top-1이 아니라 확률 분포 전체를 쓴다. 확신이 없을 때 분포가 납작해지는 것이
    /// 이 모델의 쓸모이므로, argmax만 읽으면 그 정보를 버리는 셈이다.
    static func map(_ answer: Answer, tiers: ModelTiers) -> Decision {
        // 기대 난이도 = Σ p(등급) × 등급번호. 0(minimal) … 3(high)
        var expected = 0.0
        for (index, entry) in effortCriteria.enumerated() {
            expected += (answer.effortProbabilities[entry.0] ?? 0) * Double(index)
        }
        // 막힘·복잡도는 위로만 민다. 내리는 판단은 프롬프트만으로 충분하다고 보지 않는다.
        if answer.stuck > 0.6 { expected += 0.5 }
        if answer.complexity > 1.5 { expected += 0.3 }

        let reason = String(
            format: "expected %.2f · conf %.2f · stuck %.2f · complexity %.2f · %.0fms",
            expected, answer.effortConfidence, answer.stuck, answer.complexity, answer.latencyMS
        )
        // 임시 임계값이다. 프롬프트만 보고 판정할 때 kev의 기대값이 실제로 쓰는 범위는
        // 0.8~3.0 부근이라, 0/3 양 끝을 기준으로 자르면 낮은 등급이 한 번도 안 걸린다
        // (첫 측정에서 "오타 하나 고쳐줘"조차 0.80이었다).
        // 지금 값은 실측 6건에 맞춘 것이므로 과적합이다. ledger가 쌓이면
        // 실제 결과(툴 호출 수·에러·소요)와 맞춰 다시 잘라야 한다.
        switch expected {
        case ..<1.2:
            return Decision(modelID: tiers.low, effort: .low, routed: true, reason: reason)
        case ..<1.8:
            return Decision(modelID: tiers.mid, effort: .medium, routed: true, reason: reason)
        case ..<2.3:
            return Decision(modelID: tiers.mid, effort: .high, routed: true, reason: reason)
        default:
            return Decision(modelID: tiers.high, effort: .high, routed: true, reason: reason)
        }
    }

    /// 계열마다 버전이 가장 높은 모델을 짚는다. 목록 순서는 출처(라우터·CLI 카탈로그)마다
    /// 다르므로 믿지 않는다. 계열이 목록에 없으면 "기본"으로 두어 Claude Code가 고르게 한다 —
    /// 여기에 모델 ID를 적어 두면 새 모델이 나올 때마다 낡는다.
    struct ModelTiers {
        var low: String
        var mid: String
        var high: String

        init(available: [QuickModelOption]) {
            let claude = available.filter { $0.harness == .claude && $0.provider == .claude }
            func newest(_ family: String) -> String {
                claude
                    .compactMap { option in Self.version(of: option.id, family: family).map { (option.id, $0) } }
                    .max { $0.1.lexicographicallyPrecedes($1.1) }?
                    .0 ?? QuickModelOption.defaultID
            }
            low = newest("haiku")
            mid = newest("sonnet")
            high = newest("opus")
        }

        /// `claude-opus-5-5` → [5, 5], `claude-haiku-4-5-20251001` → [4, 5].
        /// 8자리 날짜는 스냅샷 표시일 뿐 버전이 아니다. `[1m]` 같은 변형은 버전으로 읽히지 않아 빠진다.
        static func version(of id: String, family: String) -> [Int]? {
            let prefix = "claude-\(family)-"
            guard id.hasPrefix(prefix) else { return nil }
            var numbers: [Int] = []
            for part in id.dropFirst(prefix.count).split(separator: "-") {
                guard let number = Int(part) else { return nil }
                if part.count < 8 { numbers.append(number) }
            }
            return numbers.isEmpty ? nil : numbers
        }
    }

    // MARK: - kev 호출

    struct Answer {
        var effortProbabilities: [String: Double]
        var effortConfidence: Double
        var stuck: Double
        var complexity: Double
        var latencyMS: Double
    }

    static func state(from prompt: String) -> String {
        let flat = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "A coding agent received this request: \"\(String(flat.prefix(maxStateChars - 120)))\""
    }

    static func ask(state: String) async -> Answer? {
        var criteria: [String: String] = [:]
        for entry in effortCriteria { criteria[entry.0] = entry.1 }
        let body: [String: Any] = [
            "model": "kev-latest",
            "state": state,
            "questions": [
                "effort": [
                    "type": "choice",
                    "instructions": "How much reasoning effort should the coding model spend on this task?",
                    "criteria": criteria,
                ],
                "stuck": [
                    "type": "noul",
                    "instructions": "Does this request describe something already failing or already attempted?",
                ],
                "complexity": [
                    "type": "score",
                    "instructions": "How complex is this request?",
                    "criteria": ["Trivial", "Moderate", "Hard"],
                ],
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = timeout

        let started = Date()
        guard let (responseData, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let answers = json["answers"] as? [String: Any],
              let effort = answers["effort"] as? [String: Any],
              let probabilities = effort["probabilities"] as? [String: Double] else {
            return nil
        }
        return Answer(
            effortProbabilities: probabilities,
            effortConfidence: effort["confidence"] as? Double ?? 0,
            stuck: (answers["stuck"] as? [String: Any])?["noul"] as? Double ?? 0,
            complexity: (answers["complexity"] as? [String: Any])?["score"] as? Double ?? 0,
            latencyMS: Date().timeIntervalSince(started) * 1000
        )
    }

    // MARK: - 기록

    static var ledgerURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("cld/jev/router/ledger.jsonl")
    }

    /// shadow 훅과 같은 ledger에 붙인다. 적용된 판단과 관찰만 한 판단을 한 파일에서 비교하려는 것.
    private static func log(prompt: String, decision: Decision) {
        let row: [String: Any] = [
            "ts": Date().timeIntervalSince1970,
            "source": "fine-autoroute",
            "prompt_head": String(prompt.prefix(120)),
            "routed": decision.routed,
            "model": decision.modelID,
            "effort": decision.effort.rawValue,
            "reason": decision.reason,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: row),
              let json = String(data: data, encoding: .utf8) else { return }
        let line = Data((json + "\n").utf8)
        let url = ledgerURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }
}
