import AppKit
import SwiftUI

/// 밝기를 바꾸면 화면이 한 프레임에 갈아엎어진다. 그 순간이 어디서 시작됐는지
/// 보이지 않으면 사용자는 자기가 누른 것과 결과를 잇지 못한다.
///
/// 그래서 누른 자리에서 파문이 퍼져나간다. 색면이 아니라 글자다 — Fine의 홈 배경이
/// 이미 ASCII 풍경이라 같은 말투를 쓴다.
enum ThemeTransition {
    /// 파문의 시작점과, 바뀌기 직전 화면을 싣는다.
    static let begin = Notification.Name("FineThemeTransitionBegin")
    static let originKey = "origin"
    static let snapshotKey = "snapshot"

    static let duration: TimeInterval = 0.58

    /// 창 외형은 한 번에 통째로 바뀐다. 중간 상태가 없으므로 색을 서서히 섞을 수 없다.
    ///
    /// 그래서 바꾸기 직전의 화면을 한 장 찍어 위에 덮어두고, 밑에서 실제 외형을 바꾼 뒤,
    /// 덮어둔 장면에 구멍을 내어 넓혀간다. 파문이 지나간 자리부터 새 테마가 드러난다.
    @MainActor
    static func ripple(from origin: CGPoint, applying change: () -> Void) {
        guard let window = NSApp.keyWindow, let content = window.contentView else {
            change()
            return
        }
        let snapshot = snapshot(of: content)
        change()
        var payload: [String: Any] = [originKey: NSValue(point: origin)]
        if let snapshot { payload[snapshotKey] = snapshot }
        NotificationCenter.default.post(name: begin, object: window, userInfo: payload)
    }

    @MainActor
    private static func snapshot(of view: NSView) -> NSImage? {
        guard view.bounds.width > 1, view.bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

/// 창 전체를 덮는 한 겹. 평소에는 아무것도 그리지 않는다.
struct ThemeTransitionOverlay: View {
    let windowStateID: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var origin: CGPoint?
    @State private var startedAt: Date?
    /// 바뀌기 직전의 화면. 이것을 걷어내면서 새 테마가 드러난다.
    @State private var snapshot: NSImage?

    /// 안쪽에서 바깥으로 갈수록 옅어지는 글자들. 굵은 블록은 쓰지 않는다 —
    /// 화면을 덮는 것이 아니라 스쳐 지나가는 파문이라야 한다.
    private static let ramp: [String] = ["╬", "╫", "┼", "╋", "┿", "─", "·", "˙"]
    private static let cell = CGSize(width: 13, height: 19)
    /// 파문이 한 번에 걸치는 두께. 좁으면 선처럼, 넓으면 안개처럼 보인다.
    static let bandWidth: CGFloat = 82

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let origin, let startedAt, !reduceMotion {
                    TimelineView(.animation) { timeline in
                        let elapsed = timeline.date.timeIntervalSince(startedAt)
                        let progress = min(max(elapsed / ThemeTransition.duration, 0), 1)
                        let reach = farthestCorner(from: origin, in: geometry.size)
                        // 파문의 앞머리가 곧 구멍의 가장자리다. 둘이 어긋나면
                        // 색이 먼저 바뀌거나 늦게 따라와 두 사건으로 보인다.
                        let radius = ThemeTransitionOverlay.radius(progress: progress, reach: reach)

                        ZStack {
                            if let snapshot {
                                Image(nsImage: snapshot)
                                    .resizable()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .mask(
                                        // A narrow feather makes the old frame recede without
                                        // blurring or re-rendering the entire window.
                                        RadialGradient(
                                            colors: [.clear, .white],
                                            center: UnitPoint(
                                                x: origin.x / geometry.size.width,
                                                y: origin.y / geometry.size.height
                                            ),
                                            startRadius: max(0, radius - 14),
                                            endRadius: radius + 22
                                        )
                                    )
                            }
                            Canvas { context, size in
                                draw(&context, size: size, origin: origin,
                                     progress: progress, radius: radius)
                            }
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
                  let window = note.object as? NSWindow,
                  window.identifier == WindowIdentity.identifier(for: windowStateID),
                  let value = note.userInfo?[ThemeTransition.originKey] as? NSValue else { return }
            origin = value.pointValue
            snapshot = note.userInfo?[ThemeTransition.snapshotKey] as? NSImage
            startedAt = Date()
        }
    }

    private func clear() {
        origin = nil
        startedAt = nil
        snapshot = nil
    }

    private func farthestCorner(from origin: CGPoint, in size: CGSize) -> CGFloat {
        [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
         CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
            .map { hypot($0.x - origin.x, $0.y - origin.y) }
            .max() ?? size.width
    }

    /// 끝에서 급히 멈추면 파문이 벽에 부딪힌 것처럼 보인다. 감속해서 빠져나간다.
    static func radius(progress: Double, reach: CGFloat) -> CGFloat {
        // Cover the nearby home content in the first moments, then slow gently
        // as the edge leaves the window.
        let eased = 1 - pow(1 - progress, 3.1)
        return eased * (reach + bandWidth)
    }

    private func draw(
        _ context: inout GraphicsContext, size: CGSize, origin: CGPoint,
        progress: Double, radius: CGFloat
    ) {
        // 파문 자체도 지나가며 옅어진다.
        let fade = 1 - pow(progress, 2.4)
        guard fade > 0.01 else { return }

        let ink = colorScheme == .dark ? Color.white : Color.black
        // Resolve the eight glyphs once per frame. Creating and shaping a Text
        // for every visible cell made the transition compete with the home scene.
        let glyphs = Self.ramp.map {
            context.resolve(Text($0)
                .font(.system(size: 12, weight: .light, design: .monospaced))
                .foregroundColor(ink))
        }
        let firstRow = max(0, Int(floor((origin.y - radius) / Self.cell.height)))
        let lastRow = min(Int(ceil(size.height / Self.cell.height)),
                          Int(ceil((origin.y + radius) / Self.cell.height)))
        let firstColumn = max(0, Int(floor((origin.x - radius) / Self.cell.width)))
        let lastColumn = min(Int(ceil(size.width / Self.cell.width)),
                             Int(ceil((origin.x + radius) / Self.cell.width)))
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return }

        for row in firstRow...lastRow {
            let y = CGFloat(row) * Self.cell.height
            for column in firstColumn...lastColumn where (row + column).isMultiple(of: 2) {
                let x = CGFloat(column) * Self.cell.width
                let distance = hypot(x - origin.x, y - origin.y)
                let offset = radius - distance
                // 파문 띠 안에 있는 칸만 그린다.
                guard offset >= 0, offset <= Self.bandWidth else { continue }
                let depth = offset / Self.bandWidth
                let index = min(Self.ramp.count - 1, Int(depth * Double(Self.ramp.count)))
                // 앞머리가 가장 진하고 뒤로 갈수록 사라진다.
                let alpha = (1 - depth) * fade * 0.58
                guard alpha > 0.015 else { continue }
                var glyphContext = context
                glyphContext.opacity = alpha
                glyphContext.draw(glyphs[index], at: CGPoint(x: x, y: y))
            }
        }
    }
}
