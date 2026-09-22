import Foundation

/// UUIDs are case-insensitive; OpenCode's native IDs are case-sensitive.
enum QuickSessionIdentifier {
    static func storageKey(_ value: String) -> String? {
        if UUID(uuidString: value) != nil { return value.lowercased() }
        guard value.hasPrefix("ses_"), value.count > 4, value.count <= 128,
              value.dropFirst(4).utf8.allSatisfy({
                  (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
              }) else { return nil }
        return value
    }

    static func isValid(_ value: String, for harness: QuickHarness) -> Bool {
        if harness == .opencode { return value.hasPrefix("ses_") && storageKey(value) != nil }
        // omp: 아직 세션이 생성된 적이 없어 실제 ID 형식을 확인하지 못했다.
        // `omp -r`은 ID 접두사·경로·피커를 모두 받으므로, 확인 전까지는 기본 규칙을 따른다.
        return UUID(uuidString: value) != nil
    }
}
