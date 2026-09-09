import Foundation

enum QuickModelTier: String, CaseIterable, Identifiable {
    case connected
    case free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connected: "연결"
        case .free: "무료"
        }
    }
}

enum QuickModelProvider: String, CaseIterable, Identifiable {
    case claude
    case codex
    case kimi
    case gemini
    case alibabaPlan
    case alibabaFree
    case openRouterFree
    case nvidiaFree
    case opencode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .kimi: "Kimi"
        case .gemini: "Gemini"
        case .alibabaPlan: "Alibaba Plan"
        case .alibabaFree: "Alibaba Free"
        case .openRouterFree: "OpenRouter"
        case .nvidiaFree: "NVIDIA"
        case .opencode: "OpenCode"
        }
    }

    var tier: QuickModelTier {
        switch self {
        case .alibabaFree, .openRouterFree, .nvidiaFree: .free
        default: .connected
        }
    }
}

extension QuickModelOption {
    var provider: QuickModelProvider {
        if harness == .codex { return .codex }
        if harness == .opencode { return .opencode }
        if isCodex { return .codex }
        if isKimi { return .kimi }
        if isGemini { return .gemini }
        if isAlibabaPlan { return .alibabaPlan }
        if isAlibabaFree { return .alibabaFree }
        if isOpenRouterFree { return .openRouterFree }
        if isNvidiaFree { return .nvidiaFree }
        return .claude
    }

    /// Only Claude Code alias models need the local router. The default option
    /// and OpenCode models run exactly as the terminal would.
    var requiresProxy: Bool {
        harness == .claude && !isDefault && provider != .claude
    }

    var conciseDisplayName: String {
        let prefix = "\(provider.title) · "
        return displayName.hasPrefix(prefix)
            ? String(displayName.dropFirst(prefix.count))
            : displayName
    }
}
