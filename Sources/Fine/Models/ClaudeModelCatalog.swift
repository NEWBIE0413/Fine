import Foundation

/// Claude Code가 받아 캐시해 둔 모델 카탈로그를 읽는다.
///
/// 예전에는 `strings`로 CLI 바이너리를 긁어 "id 다음 줄이 표시 이름"이라는 배치를
/// 가정했다. 2.1.278에서 그 배치가 깨지면서 모델이 하나도 안 잡혔다 —
/// 바이너리의 문자열 순서는 애초에 우리에게 약속된 것이 아니다.
///
/// CLI는 서명된 카탈로그를 받아 `~/.claude/cache/model-catalog`에 둔다. 그쪽은
/// id와 이름뿐 아니라 모델별 effort 목록까지 들고 있다. Haiku는 effort가 아예 없고
/// 4.6 계열에는 `xhigh`가 없는데, 그런 것은 긁어서는 알 수 없다.
enum ClaudeModelCatalog {
    static var cacheDirectory: URL {
        FinePaths.home.appendingPathComponent(".claude/cache/model-catalog", isDirectory: true)
    }

    static func discover(in directory: URL = cacheDirectory) -> [QuickModelOption] {
        guard let url = newestFile(in: directory),
              let data = try? Data(contentsOf: url) else { return [] }
        return parse(data)
    }

    /// 캐시는 표면(surface)마다 한 파일이다. 가장 최근 것을 쓴다.
    private static func newestFile(in directory: URL) -> URL? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return nil }
        return files
            .filter { $0.pathExtension == "json" }
            .max { left, right in
                let leftDate = (try? left.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                let rightDate = (try? right.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                return leftDate < rightDate
            }
    }

    /// 카탈로그는 설치된 CLI보다 먼저 새 모델을 싣는다(`min_claude_code_version`).
    /// 아직 업데이트되지 않은 CLI에 그 모델을 넘기면 세션이 시작부터 실패하므로 걸러 낸다.
    /// 설치 버전을 모르면 거르지 않는다 — 막는 쪽보다 보여 주는 쪽이 덜 해롭다.
    static func parse(_ data: Data, installedVersion: [Int]? = installedCLIVersion()) -> [QuickModelOption] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let catalog = root["catalog"] as? [String: Any],
              let config = catalog["config"] as? [String: Any],
              let models = config["models"] as? [[String: Any]] else { return [] }
        var seen: Set<String> = []
        return models.compactMap { model in
            guard let id = model["id"] as? String, id.hasPrefix("claude-"),
                  let name = model["name"] as? String, !name.isEmpty,
                  runs(on: installedVersion, minimum: model["min_claude_code_version"] as? String),
                  seen.insert(id).inserted else { return nil }
            return QuickModelOption(
                id: id,
                displayName: name,
                supportedEfforts: efforts(model["thinking"]),
                harness: .claude
            )
        }
    }

    /// 설치 관리자는 `~/.local/bin/claude`를 `…/versions/2.1.280`으로 잇는다. 프로세스를 띄우지 않고 읽는다.
    static func installedCLIVersion(
        executable: URL = FinePaths.home.appendingPathComponent(".local/bin/claude")
    ) -> [Int]? {
        version(executable.resolvingSymlinksInPath().lastPathComponent)
    }

    static func runs(on installed: [Int]?, minimum: String?) -> Bool {
        guard let installed, let minimum, let required = version(minimum) else { return true }
        return !installed.lexicographicallyPrecedes(required)
    }

    static func version(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".").map { Int($0) }
        guard parts.count >= 2, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }

    /// `thinking.type`이 `none`이면 고를 깊이가 없다는 뜻이고, 그때는 빈 목록이어야
    /// 컴포저가 깊이 칸을 숨긴다.
    static func efforts(_ thinking: Any?) -> [QuickEffort] {
        guard let thinking = thinking as? [String: Any],
              let options = thinking["effort_options"] as? [[String: Any]] else { return [] }
        let listed = Set(options.compactMap { $0["id"] as? String })
        // 표에 적힌 순서가 아니라 축의 순서로 고정한다.
        return QuickEffort.allCases.filter { listed.contains($0.rawValue) }
    }
}
