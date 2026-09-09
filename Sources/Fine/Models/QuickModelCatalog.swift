import Foundation
import Combine

/// Which coding agent a conversation runs. Fine drives both through the same
/// PTY; only the launch command and the model catalog differ.
enum QuickHarness: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude
    case codex
    case opencode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }
}

enum QuickEffort: String, CaseIterable, Identifiable, Codable, Sendable {
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "낮음"
        case .medium: return "중간"
        case .high: return "높음"
        case .xhigh: return "매우 높음"
        case .max: return "최대"
        case .ultra: return "울트라"
        }
    }
}

struct QuickModelOption: Codable, Hashable, Identifiable, Sendable {
    /// Empty ID means "the harness default": launch without any model flag so
    /// the session behaves exactly like typing the command in a terminal.
    static let defaultID = ""

    let id: String
    let displayName: String
    let supportedEfforts: [QuickEffort]
    let harness: QuickHarness

    var isDefault: Bool { id == Self.defaultID }

    var isCodex: Bool {
        id.hasPrefix("claude-codex-")
    }

    var isKimi: Bool {
        id.hasPrefix("claude-kimi-")
    }

    var isGemini: Bool {
        id.hasPrefix("claude-gemini-")
    }

    var isOpenRouterFree: Bool {
        id.hasPrefix("claude-openrouter-")
    }

    var isNvidiaFree: Bool {
        id.hasPrefix("claude-nvidia-")
    }

    var isAlibabaPlan: Bool {
        id.hasPrefix("alibaba-plan-")
    }

    var isAlibabaFree: Bool {
        id.hasPrefix("alibaba-free-")
    }

    var isAlibaba: Bool {
        isAlibabaPlan || isAlibabaFree
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case supportedEfforts = "supported_efforts"
    }

    init(
        id: String,
        displayName: String,
        supportedEfforts: [QuickEffort] = [.low, .medium, .high, .xhigh, .max],
        harness: QuickHarness = .claude
    ) {
        self.id = id
        self.displayName = displayName
        self.supportedEfforts = supportedEfforts
        self.harness = harness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        supportedEfforts = try container.decodeIfPresent(
            [QuickEffort].self,
            forKey: .supportedEfforts
        ) ?? [.low, .medium, .high, .xhigh, .max]
        harness = .claude
    }

    static func defaultOption(for harness: QuickHarness) -> QuickModelOption {
        QuickModelOption(
            id: defaultID,
            displayName: "기본 (터미널과 동일)",
            supportedEfforts: [],
            harness: harness
        )
    }
}

struct QuickSessionConfiguration: Codable, Equatable, Sendable {
    let harness: QuickHarness
    let modelID: String
    let effort: QuickEffort
    let proxyEnabled: Bool

    /// Plain `ccv -y`: no model or effort flag, no router. Identical to the terminal.
    static let `default` = QuickSessionConfiguration(
        modelID: QuickModelOption.defaultID,
        effort: .high,
        proxyEnabled: false
    )

    init(
        harness: QuickHarness = .claude,
        modelID: String,
        effort: QuickEffort,
        proxyEnabled: Bool
    ) {
        self.harness = harness
        self.modelID = modelID
        self.effort = effort
        self.proxyEnabled = proxyEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case harness
        case modelID
        case effort
        case proxyEnabled
    }

    /// Configurations saved before the harness field existed are Claude sessions.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        harness = try container.decodeIfPresent(QuickHarness.self, forKey: .harness) ?? .claude
        modelID = try container.decode(String.self, forKey: .modelID)
        effort = try container.decode(QuickEffort.self, forKey: .effort)
        proxyEnabled = try container.decode(Bool.self, forKey: .proxyEnabled)
    }

    static func defaultConfiguration(for harness: QuickHarness) -> QuickSessionConfiguration {
        QuickSessionConfiguration(
            harness: harness,
            modelID: QuickModelOption.defaultID,
            effort: .high,
            proxyEnabled: false
        )
    }

    var isDefaultModel: Bool { modelID == QuickModelOption.defaultID }

    /// The router only ever sits in front of Claude Code, and never in default
    /// mode: "기본" means the user asked for the terminal's plain `ccv`.
    var usesProxy: Bool {
        guard harness == .claude, !isDefaultModel else { return false }
        return proxyEnabled
            || modelID.hasPrefix("claude-codex-")
            || modelID.hasPrefix("claude-kimi-")
            || modelID.hasPrefix("claude-gemini-")
            || modelID.hasPrefix("claude-openrouter-")
            || modelID.hasPrefix("claude-nvidia-")
            || modelID.hasPrefix("alibaba-plan-")
            || modelID.hasPrefix("alibaba-free-")
    }

    var terminalStatus: String {
        if harness == .codex {
            return isDefaultModel
                ? "Codex · 기본 앱 설정"
                : "Codex · \(modelID)  /  effort \(effort.rawValue)"
        }
        if harness == .opencode {
            return isDefaultModel ? "OpenCode · 기본" : "OpenCode · \(modelID)"
        }
        if isDefaultModel {
            return "Claude · 기본 (터미널과 동일)"
        }
        let provider: String
        let model: String
        if modelID.hasPrefix("claude-codex-") {
            provider = "Codex"
            model = String(modelID.dropFirst("claude-codex-".count))
        } else if modelID.hasPrefix("claude-kimi-") {
            provider = "Kimi"
            model = String(modelID.dropFirst("claude-kimi-".count))
        } else if modelID.hasPrefix("claude-gemini-") {
            provider = "Gemini"
            model = String(modelID.dropFirst("claude-gemini-".count))
        } else if modelID.hasPrefix("claude-openrouter-") {
            provider = "OpenRouter Free"
            let encoded = String(modelID
                .dropFirst("claude-openrouter-".count)
                .dropLast(modelID.hasSuffix("[1m]") ? 4 : 0))
            model = Self.decodeBase64URL(encoded) ?? "free model"
        } else if modelID.hasPrefix("claude-nvidia-") {
            provider = "NVIDIA Free"
            let encoded = String(modelID
                .dropFirst("claude-nvidia-".count)
                .dropLast(modelID.hasSuffix("[1m]") ? 4 : 0))
            model = Self.decodeBase64URL(encoded) ?? "free model"
        } else if modelID.hasPrefix("alibaba-plan-") {
            provider = "Alibaba Plan"
            model = String(modelID.dropFirst("alibaba-plan-".count))
        } else if modelID.hasPrefix("alibaba-free-") {
            provider = "Alibaba Free"
            model = String(modelID.dropFirst("alibaba-free-".count))
        } else {
            provider = "Claude"
            model = modelID.hasPrefix("claude-")
                ? String(modelID.dropFirst("claude-".count))
                : modelID
        }
        let conciseModel = model.hasSuffix("[1m]") ? String(model.dropLast(4)) : model
        return "\(provider) · \(conciseModel)  /  effort \(effort.rawValue)"
    }

    private static func decodeBase64URL(_ value: String) -> String? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

}

enum QuickComposerPreferences {
    private static let harnessKey = "quickComposer.harness"
    private static let modelKey = "quickComposer.modelID"
    private static let effortKey = "quickComposer.effort"
    private static let proxyKey = "quickComposer.proxyEnabled"

    static func load(from defaults: UserDefaults = .standard) -> QuickSessionConfiguration {
        guard let modelID = defaults.string(forKey: modelKey),
              let effortRaw = defaults.string(forKey: effortKey),
              let effort = QuickEffort(rawValue: effortRaw) else {
            return .default
        }
        let harness = defaults.string(forKey: harnessKey)
            .flatMap(QuickHarness.init(rawValue:)) ?? .claude
        return QuickSessionConfiguration(
            harness: harness,
            modelID: modelID,
            effort: effort,
            proxyEnabled: defaults.bool(forKey: proxyKey)
        )
    }

    static func save(
        _ configuration: QuickSessionConfiguration,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(configuration.harness.rawValue, forKey: harnessKey)
        defaults.set(configuration.modelID, forKey: modelKey)
        defaults.set(configuration.effort.rawValue, forKey: effortKey)
        defaults.set(configuration.proxyEnabled, forKey: proxyKey)
    }

    /// A stored model that the current catalog no longer lists falls back to the
    /// same harness's default rather than silently switching harness.
    static func resolved(
        _ configuration: QuickSessionConfiguration,
        availableModels: [QuickModelOption]
    ) -> QuickSessionConfiguration {
        if configuration.isDefaultModel {
            return QuickSessionConfiguration(
                harness: configuration.harness,
                modelID: QuickModelOption.defaultID,
                effort: configuration.effort,
                proxyEnabled: false
            )
        }
        guard let model = availableModels.first(where: {
            $0.id == configuration.modelID && $0.harness == configuration.harness
        }) else {
            return .defaultConfiguration(for: configuration.harness)
        }
        let effort = model.supportedEfforts.contains(configuration.effort)
            ? configuration.effort
            : (model.supportedEfforts.contains(.high) ? .high : model.supportedEfforts.first ?? .high)
        return QuickSessionConfiguration(
            harness: configuration.harness,
            modelID: model.id,
            effort: effort,
            proxyEnabled: configuration.proxyEnabled
        )
    }
}

@MainActor
final class QuickModelCatalog: ObservableObject {
    static let claudeFallbackModels: [QuickModelOption] = [
        .defaultOption(for: .claude),
        QuickModelOption(id: "claude-opus-5", displayName: "Opus 5"),
        QuickModelOption(id: "claude-sonnet-5", displayName: "Sonnet 5"),
        QuickModelOption(id: "claude-haiku-4-5", displayName: "Haiku 4.5"),
    ]
    static var fallbackModels: [QuickModelOption] { claudeFallbackModels }

    @Published private(set) var models: [QuickModelOption]
    @Published private(set) var routerAvailable = false
    @Published private(set) var isLoading = false
    @Published private(set) var harness: QuickHarness = .claude

    private let endpoint: URL
    private var refreshTask: Task<Void, Never>?

    init(endpoint: URL = URL(string: "http://127.0.0.1:4141/v1/models?limit=1000")!) {
        self.endpoint = endpoint
        models = Self.claudeFallbackModels
    }

    deinit {
        refreshTask?.cancel()
    }

    func refresh(harness: QuickHarness = .claude) {
        refreshTask?.cancel()
        self.harness = harness
        isLoading = true
        switch harness {
        case .claude:
            refreshClaude()
        case .codex:
            routerAvailable = false
            refreshTask = Task { [weak self] in
                let discovered = await Task.detached(priority: .utility) {
                    CodexModelDiscovery.discover()
                }.value
                guard !Task.isCancelled else { return }
                self?.models = [.defaultOption(for: .codex)] + discovered
                self?.isLoading = false
            }
        case .opencode:
            refreshOpenCode()
        }
    }

    private func refreshOpenCode() {
        models = [.defaultOption(for: .opencode)]
        routerAvailable = false
        refreshTask = Task { [weak self] in
            let discovered = await Task.detached(priority: .utility) {
                OpenCodeModelDiscovery.discover()
            }.value
            guard !Task.isCancelled else { return }
            self?.models = [.defaultOption(for: .opencode)] + discovered
            self?.isLoading = false
        }
    }

    private func refreshClaude() {
        let endpoint = endpoint
        refreshTask = Task { [weak self] in
            do {
                let secret = await Task.detached(priority: .utility) {
                    RouterSecretReader.read()
                }.value
                var request = URLRequest(url: endpoint)
                if let secret {
                    request.setValue(secret, forHTTPHeaderField: "x-claude-codex-router-secret")
                }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let discovered = try Self.decodeModels(data)
                guard !discovered.isEmpty else {
                    throw URLError(.cannotParseResponse)
                }
                guard !Task.isCancelled else { return }
                self?.models = [.defaultOption(for: .claude)] + discovered
                self?.routerAvailable = true
            } catch {
                guard !Task.isCancelled else { return }
                let cliModels = await Task.detached(priority: .utility) {
                    ClaudeCLIModelDiscovery.discover()
                }.value
                guard !Task.isCancelled else { return }
                self?.models = cliModels.isEmpty
                    ? Self.claudeFallbackModels
                    : [.defaultOption(for: .claude)] + cliModels
                self?.routerAvailable = false
            }
            self?.isLoading = false
        }
    }

    nonisolated static func decodeModels(_ data: Data) throws -> [QuickModelOption] {
        struct Response: Decodable {
            let data: [QuickModelOption]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var seen: Set<String> = []
        return decoded.data.filter { option in
            (option.id.hasPrefix("claude-") || option.id.hasPrefix("alibaba-"))
                && seen.insert(option.id).inserted
        }
    }
}

enum CodexModelDiscovery {
    private struct Cache: Decodable {
        let models: [Model]
    }

    private struct Model: Decodable {
        struct ReasoningLevel: Decodable { let effort: String }

        let slug: String
        let displayName: String
        let visibility: String?
        let supportedReasoningLevels: [ReasoningLevel]

        private enum CodingKeys: String, CodingKey {
            case slug
            case displayName = "display_name"
            case visibility
            case supportedReasoningLevels = "supported_reasoning_levels"
        }
    }

    static var cacheFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/models_cache.json")
    }

    static func discover(cacheFile: URL = cacheFile) -> [QuickModelOption] {
        guard let data = try? Data(contentsOf: cacheFile) else { return [] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [QuickModelOption] {
        guard let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return [] }
        var seen: Set<String> = []
        return cache.models.compactMap { model in
            guard model.visibility == nil || model.visibility == "list",
                  seen.insert(model.slug).inserted else { return nil }
            return QuickModelOption(
                id: model.slug,
                displayName: model.displayName,
                supportedEfforts: model.supportedReasoningLevels.compactMap {
                    QuickEffort(rawValue: $0.effort)
                },
                harness: .codex
            )
        }
    }
}

private enum RouterSecretReader {
    static func read() -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-w",
            "-s",
            "claude-codex-router",
            "-a",
            "local-router",
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let secret = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !secret.isEmpty else {
            return nil
        }
        return secret
    }
}

/// `opencode models` through the same interactive login shell the terminal uses,
/// so provider keys exported from ~/.zshrc reach discovery exactly as they reach
/// a terminal session. The list is whatever the user's opencode.json whitelists.
enum OpenCodeModelDiscovery {
    static func discover(
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        timeout: TimeInterval = 20
    ) -> [QuickModelOption] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", #"exec "$FINE_OPENCODE" models"#]
        var environment = ProcessInfo.processInfo.environment
        environment["FINE_OPENCODE"] = QuickSessionPolicy.opencodeExecutablePath
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return [] }
        return parse(output)
    }

    static func parse(_ output: String) -> [QuickModelOption] {
        var seen: Set<String> = []
        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard let slash = line.firstIndex(of: "/"),
                      slash > line.startIndex,
                      line.index(after: slash) < line.endIndex,
                      !line.contains(" ") else { return false }
                return seen.insert(line).inserted
            }
            .map { id in
                let slash = id.firstIndex(of: "/")!
                let provider = String(id[..<slash])
                let model = String(id[id.index(after: slash)...])
                return QuickModelOption(
                    id: id,
                    displayName: "\(providerTitle(provider)) · \(model)",
                    supportedEfforts: [],
                    harness: .opencode
                )
            }
    }

    static func providerTitle(_ provider: String) -> String {
        switch provider {
        case "alibaba-token-plan": return "Alibaba Plan"
        case "alibaba-token-plan-cn": return "Alibaba Plan CN"
        case "openrouter": return "OpenRouter"
        case "openai": return "Codex"
        case "anthropic": return "Claude"
        case "google": return "Gemini"
        case "nvidia": return "NVIDIA"
        case "opencode": return "Zen"
        default: return provider
        }
    }
}

enum ClaudeCLIModelDiscovery {
    static func discover(
        executablePath: String? = nil,
        stringsPath: String = "/usr/bin/strings"
    ) -> [QuickModelOption] {
        let candidate = executablePath ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/claude")
            .path
        let executable = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
        guard FileManager.default.isReadableFile(atPath: executable),
              FileManager.default.isExecutableFile(atPath: stringsPath) else { return [] }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: stringsPath)
        process.arguments = ["-a", executable]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else { return [] }
            return parseStringTable(output)
        } catch {
            return []
        }
    }

    static func parseStringTable(_ output: String) -> [QuickModelOption] {
        let lines = output.split(whereSeparator: \.isNewline).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard lines.count > 1 else { return [] }
        var models: [QuickModelOption] = []
        var seen: Set<String> = []
        for index in 1..<lines.count {
            guard let model = parsePair(idLine: lines[index - 1], displayLine: lines[index]),
                  seen.insert(model.id).inserted else { continue }
            models.append(model)
        }
        return models
    }

    /// Recent Claude CLI builds list the display name without the "Claude "
    /// prefix ("Opus 5" right after "claude-opus-5"); older builds included it.
    /// Both are accepted and normalized to the prefixed form.
    private static func parsePair(idLine: String, displayLine: String) -> QuickModelOption? {
        let pieces = idLine.split(separator: "-").map(String.init)
        let families: Set<String> = ["fable", "mythos", "opus", "sonnet", "haiku"]
        guard pieces.count >= 3,
              pieces[0] == "claude",
              families.contains(pieces[1]),
              pieces.dropFirst(2).allSatisfy({ Int($0) != nil }) else { return nil }
        let bareDisplay = "\(pieces[1].capitalized) " + pieces.dropFirst(2).joined(separator: ".")
        let expectedDisplay = "Claude " + bareDisplay
        guard displayLine == expectedDisplay || displayLine == bareDisplay else { return nil }
        return QuickModelOption(id: idLine, displayName: expectedDisplay)
    }
}
