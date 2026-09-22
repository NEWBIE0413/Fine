import Foundation

/// xterm.js에 전달하는 팔레트. 라이트는 흰 바탕에 검정, 다크는 그 반전이다.
struct TerminalPalette: Equatable {
    let colors: [String: String]
    var minimumContrastRatio: Double = 1
    /// 상태줄처럼 xterm 밖에서 그리는 장식도 같이 뒤집어야 한다.
    var isDark: Bool = false

    /// Fine 라이트 모드에서는 ANSI 장식색도 모두 검정으로 고정한다.
    /// Claude의 전체 화면 재도장 순서에 따라 글자색이 오가는 시각 회귀를 막는다.
    static let quickLight = TerminalPalette(colors: [
        "background": "#ffffff",
        "foreground": "#000000",
        "cursor": "#000000",
        "cursorAccent": "#ffffff",
        // 셋을 다 지정해야 한다. 활성 선택만 주면 포커스가 빠진 순간 xterm의 기본
        // 회색이 나오고, 그것이 흰 바탕에서는 검은 덩어리로 보인다.
        "selectionBackground": "#c2dbff",
        "selectionInactiveBackground": "#dde7f4",
        "selectionForeground": "#000000",
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
    /// 바탕은 작업부와 같은 짙은 회색이다. 홈 화면의 남색을 여기까지 끌고 오면
    /// 글을 읽는 면에 색이 돌아 눈이 피로하다 — 배경은 배경답게 중립이어야 한다.
    static let quickDark = TerminalPalette(colors: [
        "background": "#1e1e1e",
        "foreground": "#e8e8e8",
        "cursor": "#e8e8e8",
        "cursorAccent": "#1e1e1e",
        "selectionBackground": "#2f4a72",
        "selectionInactiveBackground": "#2b3442",
        "selectionForeground": "#f2f2f2",
        "black": "#e8e8e8",
        "red": "#e8e8e8",
        "green": "#e8e8e8",
        "yellow": "#e8e8e8",
        "blue": "#e8e8e8",
        "magenta": "#e8e8e8",
        "cyan": "#e8e8e8",
        "white": "#e8e8e8",
        "brightBlack": "#e8e8e8",
        "brightRed": "#e8e8e8",
        "brightGreen": "#e8e8e8",
        "brightYellow": "#e8e8e8",
        "brightBlue": "#e8e8e8",
        "brightMagenta": "#e8e8e8",
        "brightCyan": "#e8e8e8",
        "brightWhite": "#e8e8e8",
    ], isDark: true)

    /// 라이트에서 제출된 프롬프트 바탕이 흰 바탕보다 조금 어두운 면이듯,
    /// 다크에서는 검은 바탕보다 조금 밝은 면이어야 한다.
    static let claudeDark: TerminalPalette = {
        var colors = quickDark.colors
        colors["brightBlack"] = "#2c2c2e"
        return TerminalPalette(colors: colors, minimumContrastRatio: 4.5, isDark: true)
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
