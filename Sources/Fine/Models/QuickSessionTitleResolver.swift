import Foundation

/// 실행 중인 Claude의 ephemeral session registry를 Quick transcript UUID로 연결한다.
/// registry의 derived `name`은 의도적으로 디코딩하지 않는다 — 탭 표시명은 오직
/// transcript의 ai-title만 사용한다.
enum QuickSessionTitleResolver {
    private struct ClaudeSessionRecord: Decodable {
        let pid: Int32
        let sessionId: String
        let cwd: String
    }

    static var sessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions", isDirectory: true)
    }

    static func sessionId(
        processIdentifier: pid_t,
        sessionsDirectory: URL = QuickSessionTitleResolver.sessionsDirectory,
        expectedWorkingDirectory: String = QuickSessionPolicy.workingDirectory
    ) -> String? {
        let recordURL = sessionsDirectory
            .appendingPathComponent("\(processIdentifier)")
            .appendingPathExtension("json")
        guard let data = try? Data(contentsOf: recordURL),
              let record = try? JSONDecoder().decode(ClaudeSessionRecord.self, from: data),
              record.pid == processIdentifier,
              UUID(uuidString: record.sessionId) != nil,
              standardized(record.cwd) == standardized(expectedWorkingDirectory) else {
            return nil
        }
        return record.sessionId
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

enum CodexSessionResolver {
    static func sessionId(processIdentifier: pid_t) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-Fn", "-p", String(processIdentifier)]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let data: Data
        do {
            try process.run()
            data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return sessionId(fromLsofOutput: value)
    }

    static func sessionId(fromLsofOutput output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.first == "n" else { continue }
            let path = String(line.dropFirst())
            guard path.contains("/.codex/sessions/"),
                  path.hasSuffix(".jsonl"),
                  let marker = path.range(of: "rollout-", options: .backwards)
            else { continue }
            let value = String(path[marker.upperBound...].dropLast(".jsonl".count))
            let candidate = String(value.suffix(36))
            if UUID(uuidString: candidate) != nil { return candidate.lowercased() }
        }
        return nil
    }
}
