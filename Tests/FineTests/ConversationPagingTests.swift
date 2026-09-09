import Combine
import XCTest
@testable import Fine

final class ConversationPagingTests: XCTestCase {
    @MainActor
    func testLoadsThirtyAtATimeAndDoesNotRereadUnchangedTranscripts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var sizes: [Int] = []
        var ids: [String] = []
        for i in 0..<65 {
            let id = UUID().uuidString
            ids.append(id)
            let file = directory.appendingPathComponent(id + ".jsonl")
            let data = Data((#"{"type":"ai-title","aiTitle":"대화 \#(i)"}"# + "\n").utf8)
            sizes.append(data.count)
            try data.write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(i))], ofItemAtPath: file.path)
        }
        let scanner = QuickConversationScanner(transcriptsDirectory: directory, sessionStore: nil)
        await refresh(scanner) { scanner.rescan() }
        XCTAssertEqual(scanner.conversations.count, 30)
        XCTAssertEqual(scanner.conversations.first?.title, "대화 64")
        XCTAssertTrue(scanner.hasMore)
        XCTAssertEqual(scanner.metadataBytesRead, sizes.suffix(31).reduce(0, +))
        let coldBytes = scanner.metadataBytesRead
        await refresh(scanner) { scanner.rescan() }
        XCTAssertEqual(scanner.metadataBytesRead, coldBytes)

        let owner = UUID()
        await refresh(scanner) { scanner.track(sessionID: ids[0], owner: owner) }
        XCTAssertEqual(scanner.aiTitlesBySessionId[ids[0]], "대화 0")
        XCTAssertEqual(scanner.conversations.count, 30, "An open older session must not expand the sidebar page")
        XCTAssertEqual(scanner.metadataBytesRead, coldBytes + sizes[0])
        scanner.untrack(owner: owner)
        await refresh(scanner) { scanner.loadNextPage() }
        XCTAssertEqual(scanner.conversations.count, 60)
        XCTAssertTrue(scanner.hasMore)
        await refresh(scanner) { scanner.loadNextPage() }
        XCTAssertEqual(scanner.conversations.count, 65)
        XCTAssertFalse(scanner.hasMore)
        XCTAssertEqual(Set(scanner.conversations.map(\.id)).count, 65)
        let allBytes = scanner.metadataBytesRead
        await refresh(scanner) { for _ in 0..<10 { scanner.rescan() } }
        // Allow the one coalesced follow-up to complete as well.
        while scanner.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(scanner.metadataBytesRead, allBytes)
        print("Paging fixture: 65 files; first page \(coldBytes) bytes; unchanged refresh 0 bytes")
    }

    @MainActor
    private func refresh(_ scanner: QuickConversationScanner, action: () -> Void) async {
        let done = expectation(description: "scan completed")
        let subscription = scanner.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
        action()
        await fulfillment(of: [done], timeout: 5)
        withExtendedLifetime(subscription) {}
    }
}
