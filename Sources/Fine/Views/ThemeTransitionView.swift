import SwiftUI

/// 밝기를 바꾸면 화면이 한 프레임에 갈아엎어진다. 그 순간이 어디서 시작됐는지
/// 보이지 않으면 사용자는 자기가 누른 것과 결과를 잇지 못한다.
///
/// 그래서 누른 자리에서 파문이 퍼져나간다. 색면이 아니라 글자다 — Fine의 홈 배경이
/// 이미 ASCII 풍경이라 같은 말투를 쓴다.
enum ThemeTransition {
    /// 파문의 시작점을 창 좌표로 싣는다.
    static let begin = Notification.Name("FineThemeTransitionBegin")
    static let originKey = "origin"

    static let duration: TimeInterval = 0.62

    @MainActor
    static func ripple(from origin: CGPoint) {
        NotificationCenter.default.post(
            name: begin, object: nil,
            userInfo: [originKey: NSValue(point: origin)]
        )
    }
}

/// 창 전체를 덮는 한 겹. 평소에는 아무것도 그리지 않는다.
struct ThemeTransitionOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var origin: CGPoint?
    @State private var startedAt: Date?

    /// 안쪽에서 바깥으로 갈수록 옅어지는 글자들. 굵은 블록은 쓰지 않는다 —
    /// 화면을 덮는 것이 아니라 스쳐 지나가는 파문이라야 한다.
    private static let ramp: [String] = ["╬", "╫", "┼", "╋", "┿", "─", "·", "˙"]
    private static let cell = CGSize(width: 11, height: 17)
    /// 파문이 한 번에 걸치는 두께. 좁으면 선처럼, 넓으면 안개처럼 보인다.
    private static let bandWidth: CGFloat = 96

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let origin, let startedAt, !reduceMotion {
                    TimelineView(.animation) { timeline in
                        let elapsed = timeline.date.timeIntervalSince(startedAt)
                        let progress = min(max(elapsed / ThemeTransition.duration, 0), 1)
                        Canvas { context, size in
                            draw(&context, size: size, origin: origin, progress: progress)
                        }
                        .onChange(of: progress >= 1) { _, done in
                            if done { clear() }
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: ThemeTransition.begin)) { note in
            guard !reduceMotion,
                  let value = note.userInfo?[ThemeTransition.originKey] as? NSValue else { return }
            origin = value.pointValue
            startedAt = Date()
        }
    }

    private func clear() {
        origin = nil
        startedAt = nil
    }

    private func draw(
        _ context: inout GraphicsContext, size: CGSize, origin: CGPoint, progress: Double
    ) {
        // 시작점에서 가장 먼 모서리까지 닿아야 화면 전체를 지나간다.
        let corners = [
            CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height),
        ]
        let reach = corners.map { hypot($0.x - origin.x, $0.y - origin.y) }.max() ?? size.width
        // 끝에서 급히 멈추면 파문이 벽에 부딪힌 것처럼 보인다. 감속해서 빠져나간다.
        let eased = 1 - pow(1 - progress, 2.2)
        let radius = eased * (reach + Self.bandWidth)
        // 파문 자체도 지나가며 옅어진다.
        let fade = 1 - pow(progress, 2.4)
        guard fade > 0.01 else { return }

        let ink = colorScheme == .dark ? Color.white : Color.black
        let columns = Int(ceil(size.width / Self.cell.width))
        let rows = Int(ceil(size.height / Self.cell.height))

        for row in 0...rows {
            let y = CGFloat(row) * Self.cell.height
            for column in 0...columns {
                let x = CGFloat(column) * Self.cell.width
                let distance = hypot(x - origin.x, y - origin.y)
                let offset = radius - distance
                // 파문 띠 안에 있는 칸만 그린다.
                guard offset >= 0, offset <= Self.bandWidth else { continue }
                let depth = offset / Self.bandWidth
                let index = min(Self.ramp.count - 1, Int(depth * Double(Self.ramp.count)))
                // 앞머리가 가장 진하고 뒤로 갈수록 사라진다.
                let alpha = (1 - depth) * fade * 0.75
                guard alpha > 0.015 else { continue }
                context.draw(
                    Text(Self.ramp[index])
                        .font(.system(size: 12, weight: .light, design: .monospaced))
                        .foregroundStyle(ink.opacity(alpha)),
                    at: CGPoint(x: x, y: y)
                )
            }
        }
    }
}
