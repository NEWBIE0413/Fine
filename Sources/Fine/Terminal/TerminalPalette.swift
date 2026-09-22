import Foundation

/// xterm.js에 전달하는 팔레트. 라이트는 흰 바탕에 검정, 다크는 그 반전이다.
struct TerminalPalette: Equatable {
    let colors: [String: String]
    var minimumContrastRatio: Double = 1

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

    /// Claude uses ANSI 100 (brightBlack) as the submitted prompt's background.
    /// Keep its monochrome foreground, but give that surface a separate light tone.
    /// Contrast correction also keeps ANSI 90 foreground text readable on white.
    static let claudeLight: TerminalPalette = {
        var colors = quickLight.colors
        colors["brightBlack"] = "#eeeeec"
        return TerminalPalette(colors: colors, minimumContrastRatio: 4.5)
    }()

    /// 다크 모드의 반전. 라이트가 ANSI를 전부 검정으로 고정하듯, 여기서는 전부 밝은 글자다.
    /// 색을 살리지 않는 이유는 라이트와 같다 — Claude의 전체 화면 재도장에서
    /// 글자색이 오가는 시각 회귀를 막는다.
    ///
    /// 바탕은 순검정이 아니라 홈 화면과 같은 푸른 기의 검정이다. 창 안에서 터미널만
    /// 다른 검정이면 두 면이 따로 논다.
    static let quickDark = TerminalPalette(colors: [
        "background": "#0a0d15",
        "foreground": "#e6eaf5",
        "cursor": "#e6eaf5",
        "cursorAccent": "#0a0d15",
        "selectionBackground": "#26406b",
        "black": "#e6eaf5",
        "red": "#e6eaf5",
        "green": "#e6eaf5",
        "yellow": "#e6eaf5",
        "blue": "#e6eaf5",
        "magenta": "#e6eaf5",
        "cyan": "#e6eaf5",
        "white": "#e6eaf5",
        "brightBlack": "#e6eaf5",
        "brightRed": "#e6eaf5",
        "brightGreen": "#e6eaf5",
        "brightYellow": "#e6eaf5",
        "brightBlue": "#e6eaf5",
        "brightMagenta": "#e6eaf5",
        "brightCyan": "#e6eaf5",
        "brightWhite": "#e6eaf5",
    ])

    /// 라이트에서 제출된 프롬프트 바탕이 흰 바탕보다 조금 어두운 면이듯,
    /// 다크에서는 검은 바탕보다 조금 밝은 면이어야 한다.
    static let claudeDark: TerminalPalette = {
        var colors = quickDark.colors
        colors["brightBlack"] = "#1b2130"
        return TerminalPalette(colors: colors, minimumContrastRatio: 4.5)
    }()

    static func forHarness(_ harness: QuickHarness, isDark: Bool = false) -> TerminalPalette {
        if isDark { return harness == .claude ? .claudeDark : .quickDark }
        return harness == .claude ? .claudeLight : .quickLight
    }

    var json: String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: colors,
            options: [.sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
