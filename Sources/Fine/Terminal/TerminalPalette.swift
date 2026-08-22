import Foundation

/// xterm.js에 전달하는 라이트 팔레트.
struct TerminalPalette: Equatable {
    let colors: [String: String]

    /// Fine 라이트 모드에서는 ANSI 장식색도 모두 검정으로 고정한다.
    /// Claude의 전체 화면 재도장 순서에 따라 글자색이 오가는 시각 회귀를 막는다.
    static let quickLight = TerminalPalette(colors: [
        "background": "#ffffff",
        "foreground": "#000000",
        "cursor": "#000000",
        "cursorAccent": "#ffffff",
        "selectionBackground": "#c2dbff",
        "black": "#000000",
        "red": "#000000",
        "green": "#000000",
        "yellow": "#000000",
        "blue": "#000000",
        "magenta": "#000000",
        "cyan": "#000000",
        "white": "#000000",
        "brightBlack": "#000000",
        "brightRed": "#000000",
        "brightGreen": "#000000",
        "brightYellow": "#000000",
        "brightBlue": "#000000",
        "brightMagenta": "#000000",
        "brightCyan": "#000000",
        "brightWhite": "#000000",
    ])

    var json: String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: colors,
            options: [.sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
