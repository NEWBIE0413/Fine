import Foundation

/// 라우터의 순수한 부분 — AppKit 없이 테스트할 수 있도록 대상 해석과 인자 해석을 분리했다.
/// CLI의 `<win>`은 index / id 접두사 / front, `<tab>`은 index / 이름 / session-id / id 접두사.
enum ControlTargetResolver {
    struct WindowDescriptor: Equatable {
        let id: UUID
        let isKey: Bool
    }

    struct TabDescriptor: Equatable {
        let id: UUID
        let name: String
        let conversationID: String?
    }

    /// nil 질의는 front(키 창, 없으면 첫 창). 못 찾으면 nil.
    static func windowIndex(query: String?, in windows: [WindowDescriptor]) -> Int? {
        guard !windows.isEmpty else { return nil }
        let trimmed = query?.trimmingCharacters(in: .whitespaces) ?? ""
        if trimmed.isEmpty || trimmed == "front" || trimmed == "key" {
            return windows.firstIndex { $0.isKey } ?? 0
        }
        if let index = Int(trimmed) { return windows.indices.contains(index) ? index : nil }
        let lower = trimmed.lowercased()
        return windows.firstIndex { $0.id.uuidString.lowercased().hasPrefix(lower) }
    }

    /// 정확한 일치를 먼저, 접두사 일치를 나중에 본다 — "3"이라는 이름의 탭보다 인덱스 3이
    /// 먼저 잡히지 않도록 이름은 인덱스보다 앞에 둔다(UUID를 이름으로 쓰는 일은 없다).
    static func tabIndex(query: String, in tabs: [TabDescriptor]) -> Int? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        let lower = q.lowercased()
        return tabs.firstIndex { $0.id.uuidString.lowercased() == lower }
            ?? tabs.firstIndex { $0.conversationID == q }
            ?? tabs.firstIndex { $0.conversationID?.lowercased() == lower }
            ?? tabs.firstIndex { $0.name == q }
            ?? Int(q).flatMap { tabs.indices.contains($0) ? $0 : nil }
            ?? tabs.firstIndex { $0.name.lowercased() == lower }
            ?? (q.count >= 4 ? tabs.firstIndex { $0.id.uuidString.lowercased().hasPrefix(lower) } : nil)
    }

    /// `tab move` 목적지: 절대 인덱스("2") 또는 상대 이동("+1", "-1"). 범위를 벗어나면 nil.
    static func moveDestination(spec: String, current: Int, count: Int) -> Int? {
        let s = spec.trimmingCharacters(in: .whitespaces)
        guard let value = Int(s) else { return nil }
        let destination = (s.hasPrefix("+") || s.hasPrefix("-")) ? current + value : value
        return (0..<count).contains(destination) ? destination : nil
    }
}

enum ControlArgumentError: Error, Equatable {
    case invalidHarness(String)
    case invalidEffort(String)

    var message: String {
        switch self {
        case .invalidHarness(let raw):
            return "harness must be one of \(QuickHarness.allCases.map(\.rawValue).joined(separator: "|")) (got \(raw))"
        case .invalidEffort(let raw):
            return "effort must be one of \(QuickEffort.allCases.map(\.rawValue).joined(separator: "|")) (got \(raw))"
        }
    }
}

enum ControlArguments {
    static func harness(_ raw: String?) throws -> QuickHarness? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let parsed = QuickHarness(rawValue: raw.lowercased()) else { throw ControlArgumentError.invalidHarness(raw) }
        return parsed
    }

    static func effort(_ raw: String?) throws -> QuickEffort? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let parsed = QuickEffort(rawValue: raw.lowercased()) else { throw ControlArgumentError.invalidEffort(raw) }
        return parsed
    }

    /// `fine new`의 구성 조합. 지정하지 않은 값은 컴포저의 현재 기본값(`base`)을 따르되,
    /// 하네스가 다르면 그 하네스의 기본 구성에서 출발한다 — Claude 모델 ID를 Codex에
    /// 그대로 넘기지 않기 위해서다. 모델 ID는 카탈로그와 대조하지 않는다: 카탈로그는
    /// 비동기(라우터·CLI 스캔)라 매 명령마다 기다리면 CLI가 느려지고, 잘못된 ID는 어차피
    /// 터미널에서 하네스가 거부한다. `fine models`로 미리 확인할 수 있다.
    static func configuration(
        base: QuickSessionConfiguration,
        harness harnessRaw: String?,
        model: String?,
        effort effortRaw: String?,
        proxy: Bool?
    ) throws -> QuickSessionConfiguration {
        let harness = try self.harness(harnessRaw) ?? base.harness
        let start = harness == base.harness ? base : .defaultConfiguration(for: harness)
        let modelID = model.map { $0 == "default" ? QuickModelOption.defaultID : $0 } ?? start.modelID
        return QuickSessionConfiguration(
            harness: harness,
            modelID: modelID,
            effort: try self.effort(effortRaw) ?? start.effort,
            proxyEnabled: proxy ?? start.proxyEnabled
        )
    }
}
