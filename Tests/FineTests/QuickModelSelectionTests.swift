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
            [QuickModelOption.defaultID, QuickAutoRouter.autoModelID]
        )
        XCTAssertTrue(catalog.models[0].isDefault)
        XCTAssertFalse(catalog.models[0].requiresProxy)
        XCTAssertEqual(catalog.models[0].provider, .claude)
        // "자동"은 실제 모델이 아니다. 프록시를 요구하지 않고, 세션을 띄우기 전에
        // 반드시 구체 모델로 해소되어야 한다.
        XCTAssertTrue(catalog.models[1].isAuto)
        XCTAssertFalse(catalog.models[1].requiresProxy)
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

    /// Codex CLI owns this cache and refreshes it itself. Fine reads exactly what
    /// it lists — no patched-in model IDs that could go stale.
    func testCodexDiscoveryReportsExactlyWhatTheCacheLists() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("fine-codex-models-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"{"models":[{"slug":"gpt-6-astra","display_name":"GPT-6-Astra","visibility":"list","supported_reasoning_levels":[{"effort":"high"}]}]}"#.utf8).write(to: file)

        let models = CodexModelDiscovery.discover(cacheFile: file)
        XCTAssertEqual(models.map(\.id), ["gpt-6-astra"])
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

    /// 설치된 CLI가 받아둔 카탈로그를 실제로 읽는지. 예전에는 바이너리를 긁었고,
    /// 2.1.278에서 문자열 배치가 바뀌면서 이 검사가 깨져 있었다.
    func testInstalledClaudeCatalogContainsOpus5() throws {
        let models = ClaudeCLIModelDiscovery.discover()
        try XCTSkipIf(models.isEmpty, "이 기기에 Claude Code 카탈로그 캐시가 없습니다")
        let opus = try XCTUnwrap(models.first { $0.id == "claude-opus-5" })
        XCTAssertEqual(opus.displayName, "Opus 5")
        XCTAssertEqual(opus.harness, .claude)
        XCTAssertTrue(opus.supportedEfforts.contains(.high))
    }
}

final class OmpModelDiscoveryTests: XCTestCase {
    private let sample = """
    alibaba-token-plan (3)
    ┌────────────────────────┬─────────┬─────────┬─────────────────────────────┬────────┐
    │ model                  │ context │ max-out │ thinking                    │ images │
    ├────────────────────────┼─────────┼─────────┼─────────────────────────────┼────────┤
    │ auto                   │       - │       - │ -                           │ no     │
    │ glm-5.2                │      1M │    131K │ minimal,low,medium,high,max │ no     │
    │ glm-5.3                │       - │       - │ -                           │ no     │
    └────────────────────────┴─────────┴─────────┴─────────────────────────────┴────────┘

    openai-codex (2)
    ┌───────────────┬─────────┬─────────┬───────────────────────────┬────────┐
    │ model         │ context │ max-out │ thinking                  │ images │
    ├───────────────┼─────────┼─────────┼───────────────────────────┼────────┤
    │ gpt-5.6-sol   │    272K │    128K │ low,medium,high,xhigh,max │ yes    │
    │ gpt-5.5       │    272K │    128K │ low,medium,high,xhigh     │ yes    │
    └───────────────┴─────────┴─────────┴───────────────────────────┴────────┘
    """

    func testParsesProviderQualifiedModels() {
        let models = OmpModelDiscovery.parse(sample)
        XCTAssertEqual(
            models.map(\.id),
            ["alibaba-token-plan/glm-5.2", "alibaba-token-plan/glm-5.3",
             "openai-codex/gpt-5.6-sol", "openai-codex/gpt-5.5"]
        )
        // "auto"는 모델이 아니라 자리표시자다.
        XCTAssertFalse(models.contains { $0.id.hasSuffix("/auto") })
        XCTAssertTrue(models.allSatisfy { $0.harness == .omp })
    }

    func testThinkingColumnBecomesSupportedEfforts() {
        let models = OmpModelDiscovery.parse(sample)
        let glm = try? XCTUnwrap(models.first { $0.id.hasSuffix("glm-5.2") })
        XCTAssertEqual(glm?.supportedEfforts, [.minimal, .low, .medium, .high, .max])
        let sol = models.first { $0.id.hasSuffix("gpt-5.6-sol") }
        XCTAssertEqual(sol?.supportedEfforts, [.low, .medium, .high, .xhigh, .max])
        // 지원 목록이 "-"면 하네스 기본값에 맡긴다.
        XCTAssertEqual(models.first { $0.id.hasSuffix("glm-5.3") }?.supportedEfforts, [])
    }

    /// 표에 적힌 순서가 아니라 축의 순서로 고정해야 한다 —
    /// 옵션 순서가 흔들리면 사용자도 라우터도 매번 다른 목록을 본다.
    func testEffortOrderFollowsTheAxisNotTheTable() {
        XCTAssertEqual(
            OmpModelDiscovery.efforts(from: "max,low,high"),
            [.low, .high, .max]
        )
    }
}

extension OmpModelDiscoveryTests {
    func testEnabledModelsNarrowThePicker() {
        let config = """
        modelRoles:
          default: openai-codex/gpt-5.6-sol
        enabledModels:
          - alibaba-token-plan/glm-5.2
          - openrouter/z-ai/glm-5.3-flash
        tools:
          approvalMode: yolo
        """
        let enabled = OmpModelDiscovery.parseEnabledModels(config)
        XCTAssertEqual(enabled, ["alibaba-token-plan/glm-5.2", "openrouter/z-ai/glm-5.3-flash"])

        let models = OmpModelDiscovery.parse(sample)
        let kept = OmpModelDiscovery.filtered(models, by: enabled)
        XCTAssertEqual(kept.map(\.id), ["alibaba-token-plan/glm-5.2"])
    }

    /// 화이트리스트가 없거나 하나도 안 맞으면 거르지 않는다 — 빈 피커가 더 나쁘다.
    func testMissingOrUnmatchedWhitelistKeepsEverything() {
        let models = OmpModelDiscovery.parse(sample)
        XCTAssertEqual(OmpModelDiscovery.filtered(models, by: []).count, models.count)
        XCTAssertEqual(OmpModelDiscovery.filtered(models, by: ["nope/nothing"]).count, models.count)
        XCTAssertTrue(OmpModelDiscovery.parseEnabledModels("modelRoles:\n  default: x\n").isEmpty)
    }
}

final class ClaudeModelCatalogTests: XCTestCase {
    /// 실제 캐시 파일의 모양을 그대로 옮긴 것. 모델마다 effort가 다르다는 점이 핵심이다.
    private let sample = """
    {"version":2,"fetchedAt":1790086993251,"catalog":{"surface":"cc","config":{"id":"cc","models":[
      {"id":"claude-opus-5","name":"Opus 5","section":"main",
       "thinking":{"type":"effort","effort_options":[{"id":"low"},{"id":"medium"},{"id":"high"},{"id":"xhigh"},{"id":"max"}]}},
      {"id":"claude-haiku-4-5-20251001","name":"Haiku 4.5","section":"main",
       "thinking":{"type":"none"}},
      {"id":"claude-sonnet-4-6","name":"Sonnet 4.6","section":"overflow",
       "thinking":{"type":"effort","effort_options":[{"id":"max"},{"id":"low"},{"id":"medium"},{"id":"high"}]}}
    ]}}}
    """

    func testCatalogGivesIdNameAndPerModelEfforts() throws {
        let models = ClaudeModelCatalog.parse(Data(sample.utf8))
        XCTAssertEqual(models.map(\.id),
                       ["claude-opus-5", "claude-haiku-4-5-20251001", "claude-sonnet-4-6"])
        XCTAssertEqual(models.map(\.displayName), ["Opus 5", "Haiku 4.5", "Sonnet 4.6"])
        XCTAssertTrue(models.allSatisfy { $0.harness == .claude })
    }

    /// 깊이가 없는 모델은 빈 목록이어야 컴포저가 깊이 칸을 숨긴다.
    /// 긁는 방식으로는 이것을 알 수 없어 전부 같은 기본값을 붙이고 있었다.
    func testModelWithoutThinkingHasNoEfforts() throws {
        let models = ClaudeModelCatalog.parse(Data(sample.utf8))
        let haiku = try XCTUnwrap(models.first { $0.id.hasPrefix("claude-haiku") })
        XCTAssertTrue(haiku.supportedEfforts.isEmpty)

        let opus = try XCTUnwrap(models.first { $0.id == "claude-opus-5" })
        XCTAssertEqual(opus.supportedEfforts, [.low, .medium, .high, .xhigh, .max])
        // 4.6 계열에는 xhigh가 없다. 표의 순서가 아니라 축의 순서로 고정된다.
        let sonnet = try XCTUnwrap(models.first { $0.id == "claude-sonnet-4-6" })
        XCTAssertEqual(sonnet.supportedEfforts, [.low, .medium, .high, .max])
    }

    func testModelsNeedingANewerCLIAreHiddenUntilItUpdates() {
        let catalog = """
        {"catalog":{"config":{"models":[
          {"id":"claude-opus-5-5","name":"Opus 5.5","min_claude_code_version":"2.1.280"},
          {"id":"claude-opus-5","name":"Opus 5"}
        ]}}}
        """
        let data = Data(catalog.utf8)
        XCTAssertEqual(ClaudeModelCatalog.parse(data, installedVersion: [2, 1, 279]).map(\.id), ["claude-opus-5"])
        XCTAssertEqual(ClaudeModelCatalog.parse(data, installedVersion: [2, 1, 280]).map(\.id),
                       ["claude-opus-5-5", "claude-opus-5"])
        XCTAssertEqual(ClaudeModelCatalog.parse(data, installedVersion: nil).count, 2)
    }

    func testMalformedOrEmptyCatalogYieldsNothing() {
        XCTAssertTrue(ClaudeModelCatalog.parse(Data("{}".utf8)).isEmpty)
        XCTAssertTrue(ClaudeModelCatalog.parse(Data("not json".utf8)).isEmpty)
    }
}

extension ClaudeModelCatalogTests {
    /// 모델 이름은 출처에 따라 "Claude Opus 5"로도 "Opus 5"로도 온다.
    /// 컴포저는 하네스를 따로 보여주므로 어느 쪽이든 짧은 쪽으로 읽혀야 한다.
    func testNamesReadTheSameWhicheverSourceTheyCameFrom() {
        let fromGateway = QuickModelOption(id: "claude-opus-5", displayName: "Claude Opus 5")
        let fromCatalog = QuickModelOption(id: "claude-opus-5", displayName: "Opus 5")
        XCTAssertEqual(fromGateway.conciseDisplayName, "Opus 5")
        XCTAssertEqual(fromCatalog.conciseDisplayName, "Opus 5")

        // 제공사 이름이 접두사로 붙는 기존 형태도 그대로 벗겨져야 한다.
        let kimi = QuickModelOption(id: "claude-kimi-k2", displayName: "Kimi · k2")
        XCTAssertEqual(kimi.conciseDisplayName, "k2")
    }
}

final class QuickAutoRouterTierTests: XCTestCase {
    /// 라우터는 새 모델을 맨 위에, CLI 카탈로그는 섹션 순으로 준다. 어느 순서로 와도 최신을 골라야 한다.
    func testTiersPickTheNewestOfEachFamilyWhateverTheOrder() {
        let models = [
            QuickModelOption(id: "claude-opus-4-8", displayName: "Opus 4.8"),
            QuickModelOption(id: "claude-opus-5", displayName: "Opus 5"),
            QuickModelOption(id: "claude-haiku-4-5-20251001", displayName: "Haiku 4.5"),
            QuickModelOption(id: "claude-sonnet-4-6", displayName: "Sonnet 4.6"),
            QuickModelOption(id: "claude-opus-5-5", displayName: "Opus 5.5"),
            QuickModelOption(id: "claude-sonnet-5", displayName: "Sonnet 5"),
            QuickModelOption(id: "claude-codex-gpt-opus-9[1m]", displayName: "Codex · decoy"),
        ]
        for list in [models, models.reversed()] {
            let tiers = QuickAutoRouter.ModelTiers(available: list)
            XCTAssertEqual(tiers.high, "claude-opus-5-5")
            XCTAssertEqual(tiers.mid, "claude-sonnet-5")
            XCTAssertEqual(tiers.low, "claude-haiku-4-5-20251001")
        }
    }

    /// 목록에 계열이 없으면 모델 ID를 지어내지 않고 Claude Code의 기본값에 맡긴다.
    func testMissingFamilyFallsBackToTheCLIDefault() {
        let tiers = QuickAutoRouter.ModelTiers(available: [QuickModelOption(id: "claude-opus-5-5", displayName: "Opus 5.5")])
        XCTAssertEqual(tiers.high, "claude-opus-5-5")
        XCTAssertEqual(tiers.mid, QuickModelOption.defaultID)
        XCTAssertEqual(tiers.low, QuickModelOption.defaultID)
    }
}
