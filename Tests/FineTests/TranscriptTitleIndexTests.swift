import XCTest
@testable import Fine

final class TranscriptTitleIndexTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testUnchangedFilesReadZeroBytesAndAppendReadsOnlyNewBytes() throws {
        let url = directory.appendingPathComponent("session.jsonl")
        let initial = Data((#"{"type":"user","message":{"content":"처음 질문"}}"# + "\n").utf8)
        try initial.write(to: url)
        var index = TranscriptTitleIndex()
        XCTAssertEqual(index.metadata(for: url)?.title, "처음 질문")
        XCTAssertEqual(index.bytesRead, initial.count)
        for _ in 0..<10 { XCTAssertEqual(index.metadata(for: url)?.title, "처음 질문") }
        XCTAssertEqual(index.bytesRead, initial.count)
        let appended = Data((#"{"type":"ai-title","aiTitle":"새 요약"}"# + "\n").utf8)
        try append(appended, to: url)
        XCTAssertEqual(index.metadata(for: url)?.title, "새 요약")
        XCTAssertEqual(index.bytesRead, initial.count + appended.count)
    }

    func testPartialUTF8AndFinalRecordWithoutNewlineSurviveAppends() throws {
        let url = directory.appendingPathComponent("partial.jsonl")
        let record = Data(#"{"type":"ai-title","aiTitle":"풍경을 보며"}"#.utf8)
        let split = try XCTUnwrap(record.firstIndex(of: 0xED)) + 1
        try record.prefix(split).write(to: url)
        var index = TranscriptTitleIndex()
        XCTAssertNil(index.metadata(for: url)?.title)
        try append(record.suffix(from: split), to: url)
        XCTAssertEqual(index.metadata(for: url)?.title, "풍경을 보며")
        XCTAssertEqual(index.metadata(for: url)?.title, "풍경을 보며")
        try append(Data(("\n" + #"{"type":"ai-title","aiTitle":"다음 요약"}"# + "\n").utf8), to: url)
        XCTAssertEqual(index.metadata(for: url)?.title, "다음 요약")
    }

    func testOversizedToolRecordIsSkippedAndFollowingTitleStillResolves() throws {
        let url = directory.appendingPathComponent("large.jsonl")
        var content = Data(#"{"type":"assistant","message":""#.utf8)
        content.append(Data(repeating: 120, count: TranscriptTitleIndex.maximumLineBytes * 3))
        content.append(Data(("\"}\n" + #"{"type":"ai-title","aiTitle":"작업 요약"}"# + "\n").utf8))
        try content.write(to: url)
        var index = TranscriptTitleIndex()
        XCTAssertEqual(index.metadata(for: url)?.title, "작업 요약")
        XCTAssertEqual(index.bytesRead, content.count)
        XCTAssertEqual(index.cachedFileCount, 1)
        index.retain(paths: [])
        XCTAssertEqual(index.cachedFileCount, 0)
    }

    func testTruncationSameSizeRewriteAndReplacementInvalidateOldTitle() throws {
        let url = directory.appendingPathComponent("rewrite.jsonl")
        var index = TranscriptTitleIndex()
        for title in ["long old title", "a", "b", "a completely new replacement"] {
            let data = Data((#"{"type":"ai-title","aiTitle":"\#(title)"}"# + "\n").utf8)
            if title == "a completely new replacement" { try data.write(to: url, options: .atomic) }
            else { try data.write(to: url) }
            // Force a distinct mtime even on coarse timestamp filesystems.
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(index.bytesRead))], ofItemAtPath: url.path)
            XCTAssertEqual(index.metadata(for: url)?.title, title)
        }
    }

    private func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
