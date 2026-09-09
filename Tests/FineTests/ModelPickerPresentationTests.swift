import AppKit
import SwiftUI
import XCTest
@testable import Fine

final class ModelPickerPresentationTests: XCTestCase {
    @MainActor
    func testHarnessControlHasTheSameThirtyPointHeightAsModelControls() {
        let view = NSHostingView(rootView: HarnessSegmentedControl(selection: .constant(.codex)))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.fittingSize.height, FineTheme.compactControlHeight, accuracy: 0.5)
    }

    @MainActor
    func testPickerRendersEmptySingleProviderLongNamesAndLargeCatalogAtMinimumWidth() throws {
        let longModels = (0..<28).map { index in
            QuickModelOption(id: "provider/long-model-\(index)",
                displayName: "OpenCode · Example Reasoning Model With A Long Name \(index)",
                supportedEfforts: [.low, .high], harness: .opencode)
        }
        let cases: [(String, [QuickModelOption])] = [
            ("empty", []),
            ("single", [.defaultOption(for: .codex)]),
            ("providers", QuickModelCatalog.fallbackModels + [
                QuickModelOption(id: "claude-codex-demo", displayName: "Codex · Example", supportedEfforts: [.high]),
                QuickModelOption(id: "claude-kimi-demo", displayName: "Kimi · Example", supportedEfforts: [.high]),
                QuickModelOption(id: "alibaba-free-demo", displayName: "Alibaba Free · Example", supportedEfforts: [])
            ]),
            ("long-large", longModels),
        ]
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/picker-review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, models) in cases {
            let view = NSHostingView(rootView: QuickModelPickerView(models: models,
                selectedModelID: .constant(models.first?.id ?? ""), isPresented: .constant(true), onRefresh: {}))
            view.appearance = NSAppearance(named: .aqua)
            view.frame = NSRect(x: 0, y: 0, width: 464, height: 410)
            view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(view.fittingSize.width, 500)
            XCTAssertLessThanOrEqual(view.fittingSize.height, 410)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name + ".png"))
        }
    }
}
