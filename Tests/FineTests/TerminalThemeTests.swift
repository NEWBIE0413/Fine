import XCTest
@testable import Fine

final class TerminalThemeTests: XCTestCase {
    func testLightPaletteDefinesAllANSIColors() throws {
        let colors = TerminalPalette.quickLight.colors
        let ansi16 = [
            "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
            "brightBlack", "brightRed", "brightGreen", "brightYellow",
            "brightBlue", "brightMagenta", "brightCyan", "brightWhite",
        ]
        XCTAssertEqual(colors["background"], "#ffffff")
        XCTAssertEqual(colors["foreground"], "#202124")
        XCTAssertEqual(Set(ansi16).subtracting(colors.keys), [])
        XCTAssertNotNil(TerminalPalette.quickLight.json)
    }
}
