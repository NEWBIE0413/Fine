import Foundation

/// omp 세션 파일을 찾아 ID와 제목을 읽는다.
///
/// 파일은 `~/.omp/agent/sessions/<cwd 슬러그>/<시각>_<UUID>.jsonl`에 쌓인다.
/// 슬러그 규칙은 역산하지 않는다 — 파일 첫머리의 `session` 레코드가 `cwd`를 그대로
/// 들고 있으므로 그것으로 맞춘다. 규칙이 바뀌어도 이 코드는 따라갈 필요가 없다.
enum OmpSessionResolver {
    static var sessionsDirectory: URL {
        FinePaths.home
            .appendingPathComponent(".omp/agent/sessions", isDirectory: true)
    }

    struct Session {
        let id: String
        let cwd: String
        let startedAt: Date
        let url: URL
        var title: String?
    }

    /// 이 디렉터리에서 시작된 세션 중 `after` 이후에 만들어진 가장 최근 것.
    /// Fine이 탭을 띄운 뒤 그 탭이 만든 세션을 집어내는 용도다.
    static func newestSession(
        workingDirectory: String,
        after: Date,
        in directory: URL = sessionsDirectory
    ) -> Session? {
        sessions(in: directory)
            .filter { $0.cwd == workingDirectory && $0.startedAt >= after.addingTimeInterval(-2) }
            .max { $0.startedAt < $1.startedAt }
    }

    static func session(id: String, in directory: URL = sessionsDirectory) -> Session? {
        sessions(in: directory).first { $0.id == id }
    }

    static func sessions(in directory: URL = sessionsDirectory) -> [Session] {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return folders.flatMap { folder -> [Session] in
            let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "jsonl" }.compactMap { read($0) }
        }
    }

    /// 앞부분만 읽는다. `session`과 `title`은 파일 머리에 있고, 전체를 읽으면
    /// 대화가 길어질수록 목록 한 번 만드는 데 몇 MB씩 읽게 된다.
    static func read(_ url: URL, headBytes: Int = 64_000) -> Session? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headBytes),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text, url: url)
    }

    static func parse(_ text: String, url: URL) -> Session? {
        var session: Session?
        var title: String?
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = row["type"] as? String else { continue }
            switch type {
            case "session":
                guard let id = row["id"] as? String,
                      let cwd = row["cwd"] as? String,
                      UUID(uuidString: id) != nil else { continue }
                session = Session(
                    id: id, cwd: cwd,
                    startedAt: date(row["timestamp"]) ?? .distantPast,
                    url: url
                )
            case "title":
                // 제목은 나중에 덮어써진다. 마지막 것이 지금 제목이다.
                if let value = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    title = value
                }
            default:
                continue
            }
        }
        guard var session else { return nil }
        session.title = title
        return session
    }

    /// omp는 ISO 문자열과 epoch 밀리초를 섞어 쓴다.
    static func date(_ value: Any?) -> Date? {
        if let text = value as? String {
            return ISO8601DateFormatter.ompFormatter.date(from: text)
        }
        if let milliseconds = value as? Double {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        return nil
    }
}

extension ISO8601DateFormatter {
    static let ompFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
