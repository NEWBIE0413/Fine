import Foundation

/// `omp models`가 출력하는 제공사별 표를 읽는다.
///
/// ```
/// openai-codex (5)
/// ┌───────────────┬─────────┬─────────┬───────────────────────────┬────────┐
/// │ model         │ context │ max-out │ thinking                  │ images │
/// ├───────────────┼─────────┼─────────┼───────────────────────────┼────────┤
/// │ gpt-5.6-sol   │    272K │    128K │ low,medium,high,xhigh,max │ yes    │
/// ```
///
/// thinking 열이 모델마다 다르므로 그것을 그대로 supportedEfforts로 삼는다.
/// omp에만 있는 `off`/`auto`는 Fine의 축에 대응이 없어 버리고, 나머지를 쓴다.
/// 지원 목록이 비면(`-`) 하네스 기본값에 맡긴다.
enum OmpModelDiscovery {
    static var executablePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".bun/bin/omp").path,
            "/opt/homebrew/bin/omp",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "omp"
    }

    /// 터미널과 같은 대화형 로그인 셸로 실행한다. 제공사 키가 ~/.zshrc에 있기 때문이다.
    static func discover(
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        timeout: TimeInterval = 25
    ) -> [QuickModelOption] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", #"exec "$FINE_OMP" models"#]
        var environment = ProcessInfo.processInfo.environment
        environment["FINE_OMP"] = executablePath
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        // 표가 창 너비에 따라 접히지 않도록 넉넉히 잡는다.
        environment["COLUMNS"] = "200"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return [] }
        return filtered(parse(output), by: enabledModels())
    }

    /// `omp models`는 인증되지 않은 제공사까지 전부 나열한다 (지금 556개).
    /// 사용자가 config.yml에 화이트리스트를 두었다면 그것이 곧 피커의 범위다.
    /// 목록이 없으면 거르지 않는다 — 비어 보이는 피커보다 긴 피커가 낫다.
    static func filtered(_ models: [QuickModelOption], by enabled: Set<String>) -> [QuickModelOption] {
        guard !enabled.isEmpty else { return models }
        let kept = models.filter { enabled.contains($0.id) }
        return kept.isEmpty ? models : kept
    }

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".omp/agent/config.yml")
    }

    /// config.yml의 `enabledModels:` 목록만 읽는다.
    /// YAML 전체를 해석하지 않는다 — 이 한 키만 필요하고, 형식이 바뀌면
    /// 목록이 비어 거르지 않는 쪽으로 떨어지므로 조용히 틀릴 일이 없다.
    static func enabledModels(at url: URL? = nil) -> Set<String> {
        guard let text = try? String(contentsOf: url ?? configURL, encoding: .utf8) else { return [] }
        return parseEnabledModels(text)
    }

    static func parseEnabledModels(_ text: String) -> Set<String> {
        var result: Set<String> = []
        var inside = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("enabledModels:") { inside = true; continue }
            guard inside else { continue }
            // 들여쓰기 없는 줄이 나오면 다른 키로 넘어간 것이다.
            guard line.hasPrefix(" ") || line.hasPrefix("\t") else { break }
            guard trimmed.hasPrefix("- ") else { continue }
            let value = trimmed.dropFirst(2)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { result.insert(value) }
        }
        return result
    }

    static func parse(_ output: String) -> [QuickModelOption] {
        var models: [QuickModelOption] = []
        var seen: Set<String> = []
        var provider = ""

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // 표 바깥의 "provider (n)" 줄이 다음 표의 제공사를 정한다.
            if !line.hasPrefix("│"), !line.hasPrefix("┌"), !line.hasPrefix("├"), !line.hasPrefix("└"),
               let open = line.lastIndex(of: "("), line.hasSuffix(")") {
                let name = line[..<open].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, !name.contains(" ") { provider = name }
                continue
            }

            guard line.hasPrefix("│") else { continue }
            let cells = line
                .split(separator: "│", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard cells.count >= 4 else { continue }

            let name = cells[0]
            // 머리글 줄과 자리표시자는 건너뛴다.
            guard name != "model", name != "auto", !provider.isEmpty else { continue }

            let id = "\(provider)/\(name)"
            guard seen.insert(id).inserted else { continue }
            models.append(
                QuickModelOption(
                    id: id,
                    displayName: "\(provider) · \(name)",
                    supportedEfforts: efforts(from: cells[3]),
                    harness: .omp
                )
            )
        }
        return models
    }

    static func efforts(from column: String) -> [QuickEffort] {
        guard column != "-" else { return [] }
        // 표의 순서를 그대로 쓰면 모델마다 순서가 달라진다. 축의 순서로 고정한다 —
        // 옵션 순서가 흔들리면 사용자도 라우터도 매번 다른 목록을 보게 된다.
        let listed = Set(column.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        return QuickEffort.allCases.filter { listed.contains($0.rawValue) }
    }
}
