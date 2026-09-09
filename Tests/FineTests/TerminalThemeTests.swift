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
