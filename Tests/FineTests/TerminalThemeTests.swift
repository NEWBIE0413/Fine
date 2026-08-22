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
}
