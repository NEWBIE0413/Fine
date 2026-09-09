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
        return UUID(uuidString: value) != nil
    }
}
