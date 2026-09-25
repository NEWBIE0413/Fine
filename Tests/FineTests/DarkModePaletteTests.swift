import AppKit
import SwiftUI
import XCTest
@testable import Fine

/// 공용 색은 뷰가 colorScheme을 읽지 않고 상수로 쓴다. 그 값이 외형을 따라 풀리지 않으면
/// 어두운 테마에서 검정 5%는 사라지고 흰 면은 혼자 튄다.
final class DarkModePaletteTests: XCTestCase {
    private static let dark = NSAppearance(named: .darkAqua)!
    private static let light = NSAppearance(named: .aqua)!

    private func components(_ color: Color, in appearance: NSAppearance) -> (white: CGFloat, alpha: CGFloat) {
        var result: (CGFloat, CGFloat) = (0, 0)
        appearance.performAsCurrentDrawingAppearance {
            let resolved = NSColor(color).usingColorSpace(.sRGB)!
            let white = (resolved.redComponent + resolved.greenComponent + resolved.blueComponent) / 3
            result = (white, resolved.alphaComponent)
        }
        return result
    }

    func testSharedFillsLightenInDarkAndDarkenInLight() {
        let fills: [(String, Color)] = [
            ("divider", FineTheme.divider), ("hoverFill", FineTheme.hoverFill),
            ("controlFill", FineTheme.controlFill), ("pickerRailFill", FineTheme.pickerRailFill),
            ("glassEdge", FineTheme.glassEdge),
        ]
        for (name, color) in fills {
            let dark = components(color, in: Self.dark)
            let light = components(color, in: Self.light)
            XCTAssertGreaterThan(dark.white, 0.9, "\(name) must be a white tint on a dark window")
            XCTAssertLessThan(light.white, 0.1, "\(name) must stay a black tint on a light window")
            XCTAssertGreaterThan(dark.alpha, 0.01, "\(name) must stay visible")
        }
    }

    /// "순정 Claude"를 고르면 레일의 선택 칸이 불 켠 흰 블록으로 떴다.
    func testPickerSelectionIsNotASolidWhiteBlockInDark() {
        let dark = components(FineTheme.pickerSelection, in: Self.dark)
        XCTAssertLessThan(dark.alpha, 0.2)
        XCTAssertEqual(components(FineTheme.pickerSelection, in: Self.light).alpha, 1, accuracy: 0.01)
    }

    /// 보내기 화살표는 버튼 면 위에서 읽혀야 하고(대비 3:1 이상, 비텍스트 UI 기준),
    /// 어두운 쪽에서 면이 흰색이면 안 된다 — 밤 장면 위에서 흰 사각형이 혼자 튄다.
    func testSendButtonKeepsContrastWithoutAWhiteFaceInDark() {
        func luminance(_ color: Color, _ appearance: NSAppearance) -> CGFloat {
            var result: CGFloat = 0
            appearance.performAsCurrentDrawingAppearance {
                let c = NSColor(color).usingColorSpace(.sRGB)!
                func linear(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
                result = 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
            }
            return result
        }
        for appearance in [Self.dark, Self.light] {
            let fill = luminance(FineTheme.sendFill, appearance)
            let ink = luminance(FineTheme.sendInk, appearance)
            let ratio = (max(fill, ink) + 0.05) / (min(fill, ink) + 0.05)
            XCTAssertGreaterThan(ratio, 3, "\(appearance.name.rawValue)")
        }
        XCTAssertLessThan(components(FineTheme.sendFill, in: Self.dark).white, 0.7)
    }

    /// 색을 풀어내는 곳은 결국 SwiftUI다. 실제로 그려서 레일 선택 칸이
    /// 어두운 패널 위에서 흰 띠를 만들지 않는지 본다.
    @MainActor
    func testRenderedPickerHasNoWhiteBandInDark() throws {
        let models = QuickModelCatalog.claudeFallbackModels + [
            QuickModelOption(id: "claude-codex-demo", displayName: "Codex · Example", supportedEfforts: [.high]),
        ]
        let view = NSHostingView(rootView: QuickModelPickerView(
            models: models, selectedModelID: .constant(models.first?.id ?? ""),
            isPresented: .constant(true), onRefresh: {}
        ).background(FineTheme.workspace))
        view.appearance = Self.dark
        view.frame = NSRect(x: 0, y: 0, width: 464, height: 410)
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/picker-review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: folder.appendingPathComponent("dark.png"))

        // 글자 획은 흰색이어도 짧게 끊긴다. 칸을 채운 면만 길게 이어진다.
        var longestRun = 0
        for y in 0..<bitmap.pixelsHigh {
            var run = 0
            for x in 0..<bitmap.pixelsWide {
                let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                let white = color.map { ($0.redComponent + $0.greenComponent + $0.blueComponent) / 3 } ?? 0
                run = white > 0.85 ? run + 1 : 0
                longestRun = max(longestRun, run)
            }
        }
        XCTAssertLessThan(longestRun, 40, "a near-white band \(longestRun)px wide is a lit block, not text")
    }
}
