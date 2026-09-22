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

    static func parse(_ data: Data) -> [QuickModelOption] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let catalog = root["catalog"] as? [String: Any],
              let config = catalog["config"] as? [String: Any],
              let models = config["models"] as? [[String: Any]] else { return [] }
        var seen: Set<String> = []
        return models.compactMap { model in
            guard let id = model["id"] as? String, id.hasPrefix("claude-"),
                  let name = model["name"] as? String, !name.isEmpty,
                  seen.insert(id).inserted else { return nil }
            return QuickModelOption(
                id: id,
                displayName: name,
                supportedEfforts: efforts(model["thinking"]),
                harness: .claude
            )
        }
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
