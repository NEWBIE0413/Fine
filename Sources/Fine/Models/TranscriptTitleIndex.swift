import Foundation

/// Compact, append-aware metadata. Never retain the transcript or terminal output.
/// Truncation, replacement and same-size rewrites restart the index. Growing
/// files are treated as append-only JSONL; a future in-place editor would need
/// a version marker or explicit invalidation. Oversized tool records are skipped at a bounded line size.
struct TranscriptTitleIndex {
    struct Metadata: Equatable {
        var aiTitle: String?
        var firstUserTitle: String?
        var title: String? { aiTitle ?? firstUserTitle }
    }
    private struct Entry {
        var offset: UInt64 = 0
        var modified: Date = .distantPast
        var inode: UInt64 = 0
        var partial = Data()
        var skippingLine = false
        var metadata = Metadata()
    }
    static let chunkSize = 65_536
    static let maximumLineBytes = 262_144
    private static let titleMarker = Data("\"ai-title\"".utf8)
    private static let userMarker = Data("\"user\"".utf8)
    private var entries: [String: Entry] = [:]
    private(set) var bytesRead = 0
    var cachedFileCount: Int { entries.count }

    mutating func metadata(for url: URL) -> Metadata? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        let length = size.uint64Value
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        var entry = entries[url.path] ?? Entry()
        if entry.inode != inode || length < entry.offset || (length == entry.offset && modified != entry.modified) {
            entry = Entry()
        }
        if length != entry.offset {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return entry.metadata }
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: entry.offset)
                while entry.offset < length {
                    let count = min(Self.chunkSize, Int(length - entry.offset))
                    guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
                    bytesRead += chunk.count
                    entry.offset += UInt64(chunk.count)
                    consume(chunk, into: &entry)
                }
            } catch { return entry.metadata }
        }
        entry.modified = modified
        entry.inode = inode
        entries[url.path] = entry
        // Accept a complete final record without a newline, retaining its bytes
        // so a later append can still complete or extend the record correctly.
        var result = entry.metadata
        if !entry.skippingLine { parse(entry.partial, into: &result) }
        return result
    }

    mutating func retain(paths: Set<String>) { entries = entries.filter { paths.contains($0.key) } }

    private func consume(_ chunk: Data, into entry: inout Entry) {
        var start = chunk.startIndex
        while start < chunk.endIndex {
            let end = chunk[start...].firstIndex(of: 10) ?? chunk.endIndex
            if !entry.skippingLine {
                if entry.partial.count + end - start <= Self.maximumLineBytes {
                    entry.partial.append(chunk[start..<end])
                } else {
                    entry.partial.removeAll(keepingCapacity: false)
                    entry.skippingLine = true
                }
            }
            if end < chunk.endIndex {
                if !entry.skippingLine { parse(entry.partial, into: &entry.metadata) }
                entry.partial.removeAll(keepingCapacity: entry.partial.count <= 4096)
                entry.skippingLine = false
                start = end + 1
            } else { break }
        }
    }

    private func parse(_ line: Data, into metadata: inout Metadata) {
        guard !line.isEmpty,
              line.range(of: Self.titleMarker) != nil ||
                (metadata.firstUserTitle == nil && line.range(of: Self.userMarker) != nil),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if object["type"] as? String == "ai-title", let raw = object["aiTitle"] as? String {
            let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { metadata.aiTitle = String(title.prefix(240)) }
        } else if metadata.firstUserTitle == nil, object["type"] as? String == "user",
                  let message = object["message"] as? [String: Any], let raw = message["content"] as? String {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !text.hasPrefix("<"), !text.hasPrefix("Caveat:"),
                  !text.hasPrefix("[Request interrupted") else { return }
            metadata.firstUserTitle = String(text.replacingOccurrences(of: "\n", with: " ").prefix(240))
        }
    }
}
