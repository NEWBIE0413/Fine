import XCTest
@testable import Fine

final class TerminalThemeTests: XCTestCase {
    func testLightPaletteRendersEveryANSIColorAsBlack() throws {
        let colors = TerminalPalette.quickLight.colors
        let ansi16 = [
            "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
            "brightBlack", "brightRed", "brightGreen", "brightYellow",
            "brightBlue", "brightMagenta", "brightCyan", "brightWhite",
        ]
        XCTAssertEqual(colors["background"], "#ffffff")
        XCTAssertEqual(colors["foreground"], "#000000")
        XCTAssertEqual(Set(ansi16.compactMap { colors[$0] }), ["#000000"])
        XCTAssertNotNil(TerminalPalette.quickLight.json)
    }
    func testClaudePromptBackgroundHasContrastWithoutChangingCodexOrOpenCode() {
        let claude = TerminalPalette.forHarness(.claude)
        // Real Claude capture: ESC[100m background with ESC[97m prompt text.
        XCTAssertEqual(claude.colors["brightBlack"], "#eeeeec")
        XCTAssertEqual(claude.colors["brightWhite"], "#000000")
        XCTAssertEqual(claude.minimumContrastRatio, 4.5)
        let changedColors = claude.colors.keys.filter { claude.colors[$0] != TerminalPalette.quickLight.colors[$0] }
        XCTAssertEqual(changedColors, ["brightBlack"])
        XCTAssertEqual(TerminalPalette.forHarness(.codex), .quickLight)
        XCTAssertEqual(TerminalPalette.forHarness(.opencode), .quickLight)
        XCTAssertEqual(TerminalPalette.quickLight.minimumContrastRatio, 1)
    }

}

extension TerminalThemeTests {
    /// 다크는 라이트의 반전이다 — 바탕과 글자가 뒤집히고, 장식색은 여전히 한 색으로 고정된다.
    func testDarkPaletteInvertsLightAndStaysMonochrome() {
        let light = TerminalPalette.forHarness(.codex, isDark: false)
        let dark = TerminalPalette.forHarness(.codex, isDark: true)

        XCTAssertEqual(light.colors["background"], "#ffffff")
        XCTAssertEqual(light.colors["foreground"], "#000000")
        // 바탕은 검정보다 어둡지 않되 홈 화면과 같은 푸른 기의 검정이다.
        XCTAssertNotEqual(dark.colors["background"], "#ffffff")
        XCTAssertNotEqual(dark.colors["foreground"], dark.colors["background"])

        let ansi = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
                    "brightRed", "brightGreen", "brightYellow", "brightBlue",
                    "brightMagenta", "brightCyan", "brightWhite"]
        // 라이트가 ANSI를 전부 한 색으로 고정하듯 다크도 그래야 한다.
        for key in ansi {
            XCTAssertEqual(light.colors[key], light.colors["foreground"], "light \(key)")
            XCTAssertEqual(dark.colors[key], dark.colors["foreground"], "dark \(key)")
        }
    }

    /// 제출된 프롬프트 바탕은 라이트에서 바탕보다 어둡고, 다크에서는 바탕보다 밝아야 한다.
    func testClaudePromptSurfaceFlipsWithTheScheme() throws {
        func luminance(_ hex: String) throws -> Double {
            let value = try XCTUnwrap(Int(hex.dropFirst(), radix: 16))
            let r = Double((value >> 16) & 0xff), g = Double((value >> 8) & 0xff), b = Double(value & 0xff)
            return (0.299 * r + 0.587 * g + 0.114 * b) / 255
        }
        let light = TerminalPalette.forHarness(.claude, isDark: false)
        let dark = TerminalPalette.forHarness(.claude, isDark: true)
        try XCTAssertLessThan(luminance(XCTUnwrap(light.colors["brightBlack"])),
                              luminance(XCTUnwrap(light.colors["background"])))
        try XCTAssertGreaterThan(luminance(XCTUnwrap(dark.colors["brightBlack"])),
                                 luminance(XCTUnwrap(dark.colors["background"])))
        XCTAssertEqual(dark.minimumContrastRatio, 4.5)
    }
}
