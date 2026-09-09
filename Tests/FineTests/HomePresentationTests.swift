import AppKit
import SwiftUI
import XCTest
@testable import Fine

final class HomePresentationTests: XCTestCase {
    @MainActor
    func testHomeFitsMinimumStandardAndWideWindows() throws {
        for (name, size) in [
            ("minimum", CGSize(width: 512, height: 520)),
            ("standard", CGSize(width: 1000, height: 800)),
            ("wide", CGSize(width: 1400, height: 900)),
        ] {
            try renderAndCheck(name: name, size: size)
        }
    }

    @MainActor
    func testLongModelAndMultilinePromptRemainInsideMinimumWindow() throws {
        try renderAndCheck(
            name: "long-prompt", size: CGSize(width: 512, height: 520),
            prompt: Array(repeating: "아이디어를 정리하고 다음 단계를 함께 생각해 주세요.", count: 12).joined(separator: "\n"),
            modelName: "Qwen 3.8 397B A17B Thinking"
        )
    }

    @MainActor
    func testModelPickerFitsTheMinimumWorkspace() throws {
        let root = QuickModelPickerView(
            models: QuickModelCatalog.fallbackModels,
            selectedModelID: .constant(QuickModelOption.defaultID),
            isPresented: .constant(true)
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 464, height: 320)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(hosting.fittingSize.width, 500)
        XCTAssertEqual(hosting.frame.width, 464)
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/home-design-review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent("model-picker.png"))
    }

    @MainActor
    private func renderAndCheck(
        name: String, size: CGSize, prompt: String = "", modelName: String = "GPT-6-Astra"
    ) throws {
        let geometry = HomeGeometry()
        let root = QuickHomePresentation {
            VStack(spacing: 14) {
                QuickHomeComposer(prompt: .constant(prompt), onSubmit: {}) {
                    QuickHomeControls {
                        HarnessSegmentedControl(selection: .constant(.codex))
                        .recordFrame("harness")
                    } options: {
                        HStack(spacing: 6) {
                            Label(modelName, systemImage: "sparkle")
                                .font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text("매우 높음").font(.system(size: 12)).fixedSize()
                        }
                        .padding(9)
                        .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                        .recordFrame("options")
                    } send: {
                        Image(systemName: "arrow.up")
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
                            .recordFrame("send")
                    }
                }
                .recordFrame("composer")
                Text("Codex로 시작합니다").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .coordinateSpace(name: "homeTest")
        .onPreferenceChange(HomeFrames.self) { geometry.frames = $0 }
        .preferredColorScheme(.light)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        for _ in 0..<6 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        }
        for key in ["harness", "options", "send", "composer"] {
            let frame = try XCTUnwrap(geometry.frames[key], "missing \(key) in \(name)")
            XCTAssertGreaterThanOrEqual(frame.minX, 0, "\(name): \(key)")
            XCTAssertLessThanOrEqual(frame.maxX, size.width, "\(name): \(key)")
            XCTAssertGreaterThan(frame.width, 20, "\(name): \(key) collapsed")
            if prompt.isEmpty {
                XCTAssertGreaterThanOrEqual(frame.minY, 0, "\(name): \(key)")
                XCTAssertLessThanOrEqual(frame.maxY, size.height, "\(name): \(key)")
            }
        }
        let send = try XCTUnwrap(geometry.frames["send"])
        let options = try XCTUnwrap(geometry.frames["options"])
        XCTAssertFalse(send.intersects(options), "\(name): options overlap send")
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/home-design-review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("\(name).png"))
        print("Home render \(name): \(geometry.frames)")
    }
}

private final class HomeGeometry {
    var frames: [String: CGRect] = [:]
}

private struct HomeFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private extension View {
    func recordFrame(_ name: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: HomeFrames.self, value: [name: geometry.frame(in: .named("homeTest"))])
        })
    }
}
