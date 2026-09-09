import XCTest
@testable import Fine

final class QuickComposerPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "QuickComposerPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRoundTripsLastComposerSelection() {
        let configuration = QuickSessionConfiguration(
            modelID: "claude-codex-gpt-5.6-sol[1m]",
            effort: .ultra,
            proxyEnabled: true
        )

        QuickComposerPreferences.save(configuration, to: defaults)

        XCTAssertEqual(QuickComposerPreferences.load(from: defaults), configuration)

        let opencode = QuickSessionConfiguration(
            harness: .opencode,
            modelID: "alibaba-token-plan/qwen3.8-max",
            effort: .high,
            proxyEnabled: false
        )
        QuickComposerPreferences.save(opencode, to: defaults)
        XCTAssertEqual(QuickComposerPreferences.load(from: defaults), opencode)
    }

    func testUnavailableOpenCodeModelFallsBackToOpenCodeDefaultNotClaude() {
        let stored = QuickSessionConfiguration(
            harness: .opencode,
            modelID: "openrouter/removed",
            effort: .high,
            proxyEnabled: false
        )
        let available = [
            QuickModelOption.defaultOption(for: .opencode),
            QuickModelOption(
                id: "openai/gpt-5.6-sol",
                displayName: "Codex · gpt-5.6-sol",
                supportedEfforts: [],
                harness: .opencode
            ),
        ]

        XCTAssertEqual(
            QuickComposerPreferences.resolved(stored, availableModels: available),
            .defaultConfiguration(for: .opencode)
        )
        XCTAssertEqual(
            QuickComposerPreferences.resolved(
                QuickSessionConfiguration(
                    harness: .opencode,
                    modelID: "openai/gpt-5.6-sol",
                    effort: .ultra,
                    proxyEnabled: true
                ),
                availableModels: available
            ),
            QuickSessionConfiguration(
                harness: .opencode,
                modelID: "openai/gpt-5.6-sol",
                effort: .high,
                proxyEnabled: true
            )
        )
    }

    @MainActor
    func testUnavailableStoredModelFallsBackToDefault() {
        let stored = QuickSessionConfiguration(
            modelID: "claude-codex-removed[1m]",
            effort: .ultra,
            proxyEnabled: true
        )
        let availableModels = QuickModelCatalog.fallbackModels

        XCTAssertEqual(
            QuickComposerPreferences.resolved(
                stored,
                availableModels: availableModels
            ),
            .default
        )
    }

    func testUnsupportedStoredEffortUsesAvailableHigh() {
        let stored = QuickSessionConfiguration(
            modelID: "claude-codex-gpt-test[1m]",
            effort: .ultra,
            proxyEnabled: false
        )
        let available = [
            QuickModelOption(
                id: stored.modelID,
                displayName: "Codex Test",
                supportedEfforts: [.low, .high]
            ),
        ]

        XCTAssertEqual(
            QuickComposerPreferences.resolved(stored, availableModels: available),
            QuickSessionConfiguration(
                modelID: stored.modelID,
                effort: .high,
                proxyEnabled: false
            )
        )
    }
}
