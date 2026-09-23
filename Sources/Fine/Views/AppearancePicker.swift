import SwiftUI
import AppKit

/// 앱이 따를 외형.
enum FineAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "시스템 설정"
        case .light: "밝게"
        case .dark: "어둡게"
        }
    }

    /// nil이면 시스템 설정을 그대로 따른다.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// SwiftUI의 preferredColorScheme만으로는 AppKit이 그리는 창 테두리와 재질까지
    /// 따라오지 않는다. 앱 외형을 직접 지정해야 전체가 한 번에 바뀐다.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static var stored: FineAppearance {
        FineAppearance(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    static let storageKey = "fineAppearance"

    /// 외형이 바뀌었다는 알림. 터미널처럼 SwiftUI 밖에서 그리는 면들이 이것을 듣는다.
    static let didChange = Notification.Name("FineAppearanceDidChange")

    /// "시스템"일 때는 OS가 정한 값을 따라야 하므로 실제 해석된 외형을 본다.
    @MainActor
    static var isDarkNow: Bool {
        switch stored {
        case .dark: return true
        case .light: return false
        case .system:
            return NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    /// 실행 직후와 값이 바뀔 때마다 호출한다.
    ///
    /// 앱 외형만 바꾸면 이미 떠 있는 창은 따라오지 않는다. SwiftUI의
    /// `preferredColorScheme`이 창에 외형을 직접 박아두기 때문에, 그 창은 자기 값을
    /// 계속 쓴다. 그래서 창들까지 명시적으로 지운다/맞춘다.
    @MainActor
    static func apply(_ appearance: FineAppearance) {
        NSApplication.shared.appearance = appearance.nsAppearance
        for window in NSApplication.shared.windows {
            window.appearance = appearance.nsAppearance
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

/// "새 대화" 줄 오른쪽에 앉는 토글. 지금 무엇인지가 아니라 누르면 무엇이 되는지를 보여준다 —
/// 상태가 이미 화면 전체로 드러나 있으므로 아이콘까지 그것을 되풀이할 이유가 없다.
struct AppearanceToggle: View {
    @AppStorage(FineAppearance.storageKey) private var stored = FineAppearance.system.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    /// 파문이 시작될 자리. 누른 버튼에서 퍼져야 원인과 결과가 이어진다.
    @State private var center: CGPoint = .zero

    private var isDark: Bool {
        switch FineAppearance(rawValue: stored) ?? .system {
        case .dark: true
        case .light: false
        case .system: colorScheme == .dark
        }
    }

    var body: some View {
        Button {
            let next: FineAppearance = isDark ? .light : .dark
            guard !reduceMotion else {
                stored = next.rawValue
                FineAppearance.apply(next)
                return
            }
            // 바꾸는 일 자체를 파문에 맡긴다. 파문이 이전 화면을 붙잡아 두고,
            // 지나간 자리부터 새 테마가 드러난다.
            ThemeTransition.ripple(from: center) {
                stored = next.rawValue
                FineAppearance.apply(next)
            }
        } label: {
            Image(systemName: isDark ? "sun.max" : "moon.stars")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? FineTheme.hoverFill : .clear)
                )
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .background {
            // 창 좌표로 자기 가운데를 기록해 둔다.
            GeometryReader { geometry in
                Color.clear.onAppear {
                    let frame = geometry.frame(in: .global)
                    center = CGPoint(x: frame.midX, y: frame.midY)
                }
                .onChange(of: geometry.frame(in: .global)) { _, frame in
                    center = CGPoint(x: frame.midX, y: frame.midY)
                }
            }
        }
        .buttonStyle(.finePress)
        // 옆의 "새 대화" 버튼은 라벨 안에 Spacer가 있어 줄 전체를 가져간다.
        // 고정 크기를 주지 않으면 이 토글의 폭이 0이 되어 아예 그려지지 않는다.
        .fixedSize()
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
        .help(isDark ? "밝게" : "어둡게")
        .accessibilityLabel(isDark ? "밝게 전환" : "어둡게 전환")
    }
}
