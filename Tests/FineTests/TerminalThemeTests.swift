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

extension TerminalThemeTests {
    /// 상태줄은 xterm 밖에서 CSS가 그린다. 팔레트가 자기 밝기를 들고 있어야 같이 뒤집힌다.
    func testPaletteCarriesItsSchemeForChromeOutsideXterm() {
        XCTAssertFalse(TerminalPalette.forHarness(.claude, isDark: false).isDark)
        XCTAssertFalse(TerminalPalette.forHarness(.codex, isDark: false).isDark)
        XCTAssertTrue(TerminalPalette.forHarness(.claude, isDark: true).isDark)
        XCTAssertTrue(TerminalPalette.forHarness(.omp, isDark: true).isDark)
    }

    /// 터미널 바탕은 홈의 남색이 아니라 중립적인 짙은 회색이어야 한다.
    func testDarkTerminalBackgroundIsNeutralGrey() throws {
        let hex = try XCTUnwrap(TerminalPalette.forHarness(.codex, isDark: true).colors["background"])
        let value = try XCTUnwrap(Int(hex.dropFirst(), radix: 16))
        let r = (value >> 16) & 0xff, g = (value >> 8) & 0xff, b = value & 0xff
        // 채널이 서로 가까워야 중립이다. 남색이면 파랑이 빨강보다 한참 높다.
        XCTAssertLessThanOrEqual(abs(r - b), 6, "배경에 색이 돈다: \(hex)")
        XCTAssertLessThanOrEqual(abs(r - g), 6, "배경에 색이 돈다: \(hex)")
    }
}

extension TerminalThemeTests {
    /// 선택 색은 세 가지를 다 줘야 한다. 하나라도 비우면 그 상태에서 xterm의 기본값이
    /// 나오는데, 그 회색은 밝은 바탕에서 검게, 어두운 바탕에서 희게 보인다.
    func testSelectionIsFullySpecifiedInBothSchemes() throws {
        for isDark in [false, true] {
            let palette = TerminalPalette.forHarness(.claude, isDark: isDark)
            for key in ["selectionBackground", "selectionInactiveBackground", "selectionForeground"] {
                let value = try XCTUnwrap(palette.colors[key], "\(isDark ? "dark" : "light") \(key)")
                XCTAssertTrue(value.hasPrefix("#"), "\(key) = \(value)")
            }
            // 선택 위의 글자는 바탕이 아니라 선택면 위에서 읽힌다.
            XCTAssertNotEqual(palette.colors["selectionForeground"], palette.colors["selectionBackground"])
        }
    }
}
