import XCTest
@testable import Fine

final class QuickModelSelectionTests: XCTestCase {
    @MainActor
    func testCatalogStartsWithClaudeFallbackAndCodexDisabled() {
        let catalog = QuickModelCatalog(
            endpoint: URL(string: "http://127.0.0.1:1/v1/models")!
        )

        XCTAssertFalse(catalog.routerAvailable)
        XCTAssertEqual(
            catalog.models.map(\.id),
            [QuickModelOption.defaultID, "claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"]
        )
        XCTAssertTrue(catalog.models[0].isDefault)
        XCTAssertFalse(catalog.models[0].requiresProxy)
        XCTAssertEqual(catalog.models[0].provider, .claude)
        XCTAssertFalse(catalog.models.contains(where: \.isCodex))
    }

    func testConfigurationsSavedBeforeHarnessExistedDecodeAsClaude() throws {
        let legacy = Data(#"{"modelID":"claude-sonnet-5","effort":"high","proxyEnabled":false}"#.utf8)
        let decoded = try JSONDecoder().decode(QuickSessionConfiguration.self, from: legacy)
        XCTAssertEqual(decoded.harness, .claude)
        XCTAssertEqual(decoded.modelID, "claude-sonnet-5")

        let opencode = QuickSessionConfiguration(
            harness: .opencode,
            modelID: "openrouter/z-ai/glm-5.3-flash",
            effort: .high,
            proxyEnabled: false
        )
        let roundTrip = try JSONDecoder().decode(
            QuickSessionConfiguration.self,
            from: JSONEncoder().encode(opencode)
        )
        XCTAssertEqual(roundTrip, opencode)
    }

    func testOpenCodeModelListParsesProviderSlashModelLinesOnly() {
        let models = OpenCodeModelDiscovery.parse("""
        Fetching models...
        alibaba-token-plan/deepseek-v4-flash
        openai/gpt-5.6-sol
        openrouter/z-ai/glm-5.3-flash
        openrouter/z-ai/glm-5.3-flash
        not a model line
        /leading-slash
        trailing/
        """)

        XCTAssertEqual(models.map(\.id), [
            "alibaba-token-plan/deepseek-v4-flash",
            "openai/gpt-5.6-sol",
            "openrouter/z-ai/glm-5.3-flash",
        ])
        XCTAssertEqual(models[0].displayName, "Alibaba Plan · deepseek-v4-flash")
        XCTAssertEqual(models[1].displayName, "Codex · gpt-5.6-sol")
        XCTAssertEqual(models[2].displayName, "OpenRouter · z-ai/glm-5.3-flash")
        XCTAssertTrue(models.allSatisfy { $0.harness == .opencode && $0.provider == .opencode })
        XCTAssertTrue(models.allSatisfy { !$0.requiresProxy && $0.supportedEfforts.isEmpty })
        XCTAssertEqual(OpenCodeModelDiscovery.parse(""), [])
    }

    func testCodexModelCacheIncludesVisibleModelsAndReasoningEfforts() {
        let data = Data(#"""
        {"models":[
          {"slug":"gpt-6-astra","display_name":"GPT-6-Astra","visibility":"list","supported_reasoning_levels":[{"effort":"low"},{"effort":"ultra"}]},
          {"slug":"hidden","display_name":"Hidden","visibility":"hide","supported_reasoning_levels":[]},
          {"slug":"gpt-6-astra","display_name":"Duplicate","visibility":"list","supported_reasoning_levels":[]}
        ]}
        """#.utf8)

        let models = CodexModelDiscovery.parse(data)

        XCTAssertEqual(models.map(\.id), ["gpt-6-astra"])
        XCTAssertEqual(models[0].displayName, "GPT-6-Astra")
        XCTAssertEqual(models[0].supportedEfforts, [.low, .ultra])
        XCTAssertEqual(models[0].harness, .codex)
        XCTAssertEqual(models[0].provider, .codex)
        XCTAssertFalse(models[0].requiresProxy)
    }

    func testGatewayResponseDecodesClaudeCodexKimiGeminiAndAlibabaModelsOnlyOnce() throws {
        let data = Data(#"""
        {
          "data": [
            {"id":"claude-sonnet-5","display_name":"Claude Sonnet 5","supported_efforts":["low","high","max"]},
            {"id":"claude-codex-gpt-5.6-terra","display_name":"Codex · GPT-5.6-Terra","supported_efforts":["low","ultra"]},
            {"id":"claude-kimi-k3[1m]","display_name":"Kimi · K3","supported_efforts":["low","high","max"]},
            {"id":"claude-gemini-gemini-3-flash[1m]","display_name":"Gemini · Gemini 3 Flash","supported_efforts":["low","medium","high"]},
            {"id":"alibaba-plan-deepseek-v4-flash-0731","display_name":"Alibaba Plan · DeepSeek V4 Flash"},
            {"id":"alibaba-free-deepseek-v4-flash-0731","display_name":"Alibaba Free · DeepSeek V4 Flash"},
            {"id":"claude-sonnet-5","display_name":"Duplicate"},
            {"id":"other-model","display_name":"Ignored"}
          ]
        }
        """#.utf8)

        let models = try QuickModelCatalog.decodeModels(data)

        XCTAssertEqual(models.map(\.id), [
            "claude-sonnet-5",
            "claude-codex-gpt-5.6-terra",
            "claude-kimi-k3[1m]",
            "claude-gemini-gemini-3-flash[1m]",
            "alibaba-plan-deepseek-v4-flash-0731",
            "alibaba-free-deepseek-v4-flash-0731",
        ])
        XCTAssertFalse(models[0].isCodex)
        XCTAssertTrue(models[1].isCodex)
        XCTAssertTrue(models[2].isKimi)
        XCTAssertTrue(models[3].isGemini)
        XCTAssertTrue(models[4].isAlibabaPlan)
        XCTAssertFalse(models[4].isAlibabaFree)
        XCTAssertTrue(models[5].isAlibabaFree)
        XCTAssertTrue(models[5].isAlibaba)
        XCTAssertEqual(models[0].supportedEfforts, [.low, .high, .max])
        XCTAssertEqual(models[1].supportedEfforts, [.low, .ultra])
        XCTAssertEqual(models[2].supportedEfforts, [.low, .high, .max])
        XCTAssertEqual(models[3].supportedEfforts, [.low, .medium, .high])
    }

    func testCodexSelectionAlwaysUsesProxyWhileClaudeCanStayDirect() {
        XCTAssertFalse(QuickSessionConfiguration.default.usesProxy)
        XCTAssertTrue(
            QuickSessionConfiguration(
                modelID: "claude-sonnet-5",
                effort: .medium,
                proxyEnabled: true
            ).usesProxy
        )
        XCTAssertTrue(
            QuickSessionConfiguration(
                modelID: "claude-codex-gpt-5.4-mini",
                effort: .low,
                proxyEnabled: false
            ).usesProxy
        )
        XCTAssertTrue(
            QuickSessionConfiguration(
                modelID: "claude-kimi-k3[1m]",
                effort: .high,
                proxyEnabled: false
            ).usesProxy
        )
        XCTAssertTrue(
            QuickSessionConfiguration(
                modelID: "claude-gemini-gemini-3-flash[1m]",
                effort: .high,
                proxyEnabled: false
            ).usesProxy
        )
        XCTAssertTrue(
            QuickSessionConfiguration(
                modelID: "alibaba-plan-deepseek-v4-flash-0731",
                effort: .medium,
                proxyEnabled: false
            ).usesProxy
        )
        XCTAssertTrue(
            QuickSessionConfiguration(
                modelID: "alibaba-free-deepseek-v4-flash-0731",
                effort: .medium,
                proxyEnabled: false
            ).usesProxy
        )
    }

    func testTerminalStatusShowsProviderModelAndEffort() {
        XCTAssertEqual(
            QuickSessionConfiguration(
                modelID: "claude-kimi-k3[1m]",
                effort: .high,
                proxyEnabled: false
            ).terminalStatus,
            "Kimi · k3  /  effort high"
        )
        XCTAssertEqual(
            QuickSessionConfiguration(
                modelID: "alibaba-plan-deepseek-v4-flash-0731",
                effort: .medium,
                proxyEnabled: false
            ).terminalStatus,
            "Alibaba Plan · deepseek-v4-flash-0731  /  effort medium"
        )
        XCTAssertEqual(
            QuickSessionConfiguration(
                modelID: "alibaba-free-deepseek-v4-flash-0731",
                effort: .low,
                proxyEnabled: false
            ).terminalStatus,
            "Alibaba Free · deepseek-v4-flash-0731  /  effort low"
        )
        XCTAssertEqual(
            QuickSessionConfiguration(
                modelID: "claude-sonnet-5",
                effort: .low,
                proxyEnabled: false
            ).terminalStatus,
            "Claude · sonnet-5  /  effort low"
        )
        XCTAssertEqual(
            QuickSessionConfiguration(
                modelID: "claude-openrouter-bnZpZGlhL25lbW90cm9uLTMuNS1saWdodG5pbmc6ZnJlZQ[1m]",
                effort: .high,
                proxyEnabled: false
            ).terminalStatus,
            "OpenRouter Free · nvidia/nemotron-3.5-lightning:free  /  effort high"
        )
        XCTAssertEqual(
            QuickSessionConfiguration(
                modelID: "claude-nvidia-bnZpZGlhL25lbW90cm9uLTMtc3VwZXItMTIwYi1hMTJi",
                effort: .medium,
                proxyEnabled: false
            ).terminalStatus,
            "NVIDIA Free · nvidia/nemotron-3-super-120b-a12b  /  effort medium"
        )
        XCTAssertEqual(
            QuickSessionConfiguration.default.terminalStatus,
            "Claude · 기본 (터미널과 동일)"
        )
        XCTAssertEqual(
            QuickSessionConfiguration.defaultConfiguration(for: .opencode).terminalStatus,
            "OpenCode · 기본"
        )
        XCTAssertEqual(
            QuickSessionConfiguration(
                harness: .opencode,
                modelID: "openai/gpt-5.6-sol",
                effort: .high,
                proxyEnabled: false
            ).terminalStatus,
            "OpenCode · openai/gpt-5.6-sol"
        )
    }

    func testProvidersSeparateFreeModelsFromConnectedModels() {
        let models = [
            QuickModelOption(id: "claude-sonnet-5", displayName: "Claude Sonnet 5"),
            QuickModelOption(id: "alibaba-plan-qwen3.8-max", displayName: "Alibaba Plan · Qwen3.8 Max"),
            QuickModelOption(id: "alibaba-free-qwen3.8-max", displayName: "Alibaba Free · Qwen3.8 Max"),
            QuickModelOption(
                id: "claude-openrouter-ZnJlZS9tb2RlbA",
                displayName: "OpenRouter Free · Free Model"
            ),
            QuickModelOption(
                id: "claude-nvidia-bnZpZGlhL21vZGVs",
                displayName: "NVIDIA Free · Model"
            ),
        ]

        XCTAssertEqual(models.map(\.provider), [
            .claude,
            .alibabaPlan,
            .alibabaFree,
            .openRouterFree,
            .nvidiaFree,
        ])
        XCTAssertEqual(
            models.filter { $0.provider.tier == .free }.map(\.provider),
            [.alibabaFree, .openRouterFree, .nvidiaFree]
        )
        XCTAssertTrue(models.dropFirst().allSatisfy(\.requiresProxy))
        XCTAssertEqual(models[2].conciseDisplayName, "Qwen3.8 Max")
    }

    func testClaudeCLIStringTableRejectsLegacyNoiseAndFindsOpus5() {
        let models = ClaudeCLIModelDiscovery.parseStringTable("""
        claude-opus-4-7
        unrelated text
        claude-fable-5
        Claude Fable 5
        claude-opus-5
        Claude Opus 5
        claude-sonnet-5
        Claude Sonnet 5
        claude-opus-5
        Claude Opus 5
        """)

        XCTAssertEqual(models.map(\.id), [
            "claude-fable-5",
            "claude-opus-5",
            "claude-sonnet-5",
        ])
        XCTAssertEqual(models[1].displayName, "Claude Opus 5")
        XCTAssertEqual(models[1].supportedEfforts, [.low, .medium, .high, .xhigh, .max])
    }

    /// Claude Code 2.1.25x lists "Opus 5" right after "claude-opus-5" with no
    /// "Claude " prefix; the parser must accept that and must not trap on an
    /// empty string table.
    func testClaudeCLIStringTableAcceptsBareDisplayNamesAndEmptyInput() {
        let models = ClaudeCLIModelDiscovery.parseStringTable("""
        claude-opus-5
        Opus 5
        claude-haiku-4-5
        Haiku 4.5
        claude-fable-5-1
        fable-5
        """)

        XCTAssertEqual(models.map(\.id), ["claude-opus-5", "claude-haiku-4-5"])
        XCTAssertEqual(models.map(\.displayName), ["Claude Opus 5", "Claude Haiku 4.5"])
        XCTAssertEqual(ClaudeCLIModelDiscovery.parseStringTable(""), [])
        XCTAssertEqual(ClaudeCLIModelDiscovery.parseStringTable("claude-opus-5"), [])
    }

    func testInstalledClaudeCatalogContainsOpus5() {
        let models = ClaudeCLIModelDiscovery.discover()
        XCTAssertTrue(models.contains {
            $0.id == "claude-opus-5" && $0.displayName == "Claude Opus 5"
        })
    }
}
