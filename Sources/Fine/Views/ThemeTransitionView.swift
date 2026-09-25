import AppKit
import CoreText
import QuartzCore

/// 밝기를 바꾸면 화면이 한 프레임에 갈아엎어진다. 그 순간이 어디서 시작됐는지
/// 보이지 않으면 사용자는 자기가 누른 것과 결과를 잇지 못한다.
///
/// 그래서 누른 자리에서 파문이 퍼져나간다. 색면이 아니라 글자다 — Fine의 홈 배경이
/// 이미 ASCII 풍경이라 같은 말투를 쓴다.
///
/// 파문은 전부 Core Animation 레이어로 그린다. 예전에는 SwiftUI가 매 프레임 메인
/// 스레드에서 글자 수백 개와 창 크기 스냅샷을 다시 그렸고, 새 테마의 첫 레이아웃이
/// 메인 스레드를 붙잡는 동안 벽시계만 흘러가 파문이 절반쯤 지난 채로 나타났다.
/// 레이어 애니메이션은 렌더 서버가 돌리고, 시계도 커밋된 뒤에야 출발한다.
@MainActor
enum ThemeTransition {
    nonisolated static let duration: CFTimeInterval = 0.72
    /// 파문이 한 번에 걸치는 두께. 좁으면 선처럼, 넓으면 안개처럼 보인다.
    nonisolated static let bandWidth: CGFloat = 96

    /// 한 번의 전환에서 잰 값. `fine appearance toggle`이 그대로 돌려준다.
    struct Timing {
        /// 바뀌기 전 화면을 한 장 찍는 데 든 시간. 누른 뒤 멈칫하는 시간의 대부분이다.
        var snapshotMs: Double
        /// 외형을 바꾸고 새 레이아웃을 끝내는 데 든 시간.
        var applyMs: Double
        /// 누른 순간부터 파문이 실제로 출발하기까지.
        var startDelayMs: Double?
        /// 출발부터 끝까지. 렌더 서버가 돌리므로 `duration`과 거의 같아야 한다.
        var ranMs: Double?

        var dictionary: [String: Any] {
            var result: [String: Any] = ["snapshotMs": Int(snapshotMs), "applyMs": Int(applyMs)]
            if let startDelayMs { result["startDelayMs"] = Int(startDelayMs) }
            if let ranMs { result["ranMs"] = Int(ranMs) }
            return result
        }
    }

    /// 토글이 자기 가운데(창 내용 좌표, 위가 0)를 적어 둔다. CLI도 같은 자리에서 파문을 일으킨다.
    static var toggleCenter: CGPoint?

    /// 창 외형은 한 번에 통째로 바뀐다. 중간 상태가 없으므로 색을 서서히 섞을 수 없다.
    ///
    /// 그래서 바꾸기 직전의 화면을 한 장 찍어 위에 덮어두고, 밑에서 실제 외형을 바꾼 뒤,
    /// 덮어둔 장면에 구멍을 내어 넓혀간다. 파문이 지나간 자리부터 새 테마가 드러난다.
    ///
    /// - Parameter origin: 창 내용 좌표(SwiftUI `.global`, 위가 0).
    /// - Returns: 파문이 돌기 시작했는지. `false`면 바로 바꾸기만 했고 `finished`는 오지 않는다.
    @discardableResult
    static func ripple(
        from origin: CGPoint,
        in window: NSWindow? = NSApp.keyWindow,
        applying change: () -> Void,
        finished: ((Timing) -> Void)? = nil
    ) -> Bool {
        let pressed = CACurrentMediaTime()
        guard let window, let content = window.contentView, let host = content.superview,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            change()
            return false
        }
        // 앞선 파문이 아직 돌고 있으면 걷어낸다. 그 위에 또 덮으면 옛 화면이 두 겹이 된다.
        host.subviews.lazy.compactMap { $0 as? ThemeRippleView }.forEach { $0.removeFromSuperview() }

        guard let snapshot = snapshot(of: content) else {
            change()
            return false
        }
        let snapshotted = CACurrentMediaTime()
        let ripple = ThemeRippleView(frame: content.frame, snapshot: snapshot, scale: window.backingScaleFactor)
        ripple.autoresizingMask = [.width, .height]
        host.addSubview(ripple, positioned: .above, relativeTo: content)

        change()
        // 새 외형의 레이아웃을 지금 끝낸다. 그래야 파문의 시계가 그 뒤에서 출발한다.
        content.layoutSubtreeIfNeeded()
        let applied = CACurrentMediaTime()

        let isDark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var timing = Timing(snapshotMs: (snapshotted - pressed) * 1000, applyMs: (applied - snapshotted) * 1000)
        let point = ripple.convert(origin, from: content)
        ripple.run(from: point, ink: isDark ? .white : .black, started: { started in
            timing.startDelayMs = (started - pressed) * 1000
        }, completion: { [weak ripple] started, stopped in
            ripple?.removeFromSuperview()
            if let started { timing.ranMs = (stopped - started) * 1000 }
            finished?(timing)
        })
        return true
    }

    private static func snapshot(of view: NSView) -> CGImage? {
        guard view.bounds.width > 1, view.bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    /// 끝에서 급히 멈추면 파문이 벽에 부딪힌 것처럼 보인다. 감속해서 빠져나간다.
    nonisolated static func radius(progress: Double, reach: CGFloat) -> CGFloat {
        let eased = 1 - pow(1 - min(max(progress, 0), 1), 2.2)
        return eased * (reach + bandWidth)
    }

    nonisolated static func farthestCorner(from origin: CGPoint, in size: CGSize) -> CGFloat {
        [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
         CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
            .map { hypot($0.x - origin.x, $0.y - origin.y) }
            .max() ?? size.width
    }
}

/// 창 전체를 덮는 한 겹. 파문이 도는 동안만 붙어 있다.
///
/// 레이어를 직접 소유하는(layer-hosting) 뷰다. AppKit이 레이어 좌표를 뒤집거나
/// 하위 레이어를 정리하지 않으므로, 아래가 0인 Core Animation 좌표 그대로 쓴다.
final class ThemeRippleView: NSView {
    private let root = CALayer()
    private let snapshot: CGImage

    init(frame: NSRect, snapshot: CGImage, scale: CGFloat) {
        self.snapshot = snapshot
        super.init(frame: frame)
        root.contentsScale = scale
        layer = root
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// - Parameter origin: 이 뷰의 좌표.
    func run(
        from origin: CGPoint, ink: NSColor,
        started: @escaping (CFTimeInterval) -> Void,
        completion: @escaping (CFTimeInterval?, CFTimeInterval) -> Void
    ) {
        // 뷰 좌표를 레이어 좌표(아래가 0)로 옮긴다.
        let layerOrigin = isFlipped ? CGPoint(x: origin.x, y: bounds.height - origin.y) : origin
        let observer = ThemeRippleLayers.Observer(started: started)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [observer] in
            completion(observer.startedAt, CACurrentMediaTime())
        }
        ThemeRippleLayers.install(
            in: root, size: bounds.size, snapshot: snapshot, origin: layerOrigin,
            ink: ink.cgColor, scale: root.contentsScale, observer: observer
        )
        CATransaction.commit()
    }
}

/// 파문을 이루는 레이어들. 뷰와 떼어 두어 테스트가 렌더러로 직접 그려볼 수 있게 한다.
enum ThemeRippleLayers {
    /// 안쪽에서 바깥으로 갈수록 옅어지는 글자들. 굵은 블록은 쓰지 않는다 —
    /// 화면을 덮는 것이 아니라 스쳐 지나가는 파문이라야 한다.
    static let ramp: [String] = ["╬", "╫", "┼", "╋", "┿", "─", "·", "˙"]
    static let cell = CGSize(width: 11, height: 17)
    /// 키프레임 수. 사이는 반지름이 선형으로 이어지므로 이 정도면 감속 곡선이 매끈하다.
    static let samples = 48

    final class Observer: NSObject, CAAnimationDelegate {
        private let onStart: (CFTimeInterval) -> Void
        private(set) var startedAt: CFTimeInterval?
        init(started: @escaping (CFTimeInterval) -> Void) { onStart = started }
        func animationDidStart(_ anim: CAAnimation) {
            let now = CACurrentMediaTime()
            startedAt = now
            onStart(now)
        }
    }

    /// - Parameter origin: 레이어 좌표(아래가 0).
    static func install(
        in root: CALayer, size: CGSize, snapshot: CGImage?, origin: CGPoint,
        ink: CGColor, scale: CGFloat, observer: CAAnimationDelegate?
    ) {
        let bounds = CGRect(origin: .zero, size: size)
        let reach = ThemeTransition.farthestCorner(from: origin, in: size)
        let radii = (0...samples).map {
            ThemeTransition.radius(progress: Double($0) / Double(samples), reach: reach)
        }
        let keyTimes = (0...samples).map { NSNumber(value: Double($0) / Double(samples)) }

        // 1. 바뀌기 직전의 화면. 파문의 앞머리가 곧 구멍의 가장자리다 — 둘이 어긋나면
        //    색이 먼저 바뀌거나 늦게 따라와 두 사건으로 보인다.
        if let snapshot {
            let frozen = CALayer()
            frozen.frame = bounds
            frozen.contents = snapshot
            frozen.contentsGravity = .resize
            frozen.contentsScale = scale
            let hole = shapeMask(bounds: bounds)
            hole.path = holePath(bounds: bounds, origin: origin, radius: radii.last!)
            let animation = keyframes(radii.map { holePath(bounds: bounds, origin: origin, radius: $0) }, keyTimes)
            animation.delegate = observer
            hole.add(animation, forKey: "ripple")
            frozen.mask = hole
            root.addSublayer(frozen)
        }

        // 2. 앞머리 뒤를 따라가는 글자 띠. 칸마다 글자를 찍는 대신, 한 종류의 글자로 창 전체를
        //    바둑판처럼 채운 무늬 층을 두고 그 글자가 나올 고리 모양만 보이게 한다.
        let band = CALayer()
        band.frame = bounds
        band.opacity = 0
        let fades = (0...samples).map { index -> NSNumber in
            // 파문 자체도 지나가며 옅어진다.
            NSNumber(value: 1 - pow(Double(index) / Double(samples), 2.4))
        }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = fades
        fade.keyTimes = keyTimes
        fade.duration = ThemeTransition.duration
        fade.calculationMode = .linear
        band.add(fade, forKey: "fade")

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .light)
        let step = ThemeTransition.bandWidth / CGFloat(ramp.count)
        for (level, glyph) in ramp.enumerated() {
            guard let pattern = GlyphPattern.color(glyph: glyph, font: font, ink: ink, cell: cell, scale: scale) else { continue }
            let layer = CALayer()
            layer.frame = bounds
            layer.contentsScale = scale
            layer.backgroundColor = pattern
            // 앞머리가 가장 진하고 뒤로 갈수록 사라진다.
            let depth = (CGFloat(level) + 0.5) / CGFloat(ramp.count)
            layer.opacity = Float((1 - depth) * 0.58)
            let ring = shapeMask(bounds: bounds)
            let outer = { (radius: CGFloat) in radius - CGFloat(level) * step }
            let inner = { (radius: CGFloat) in radius - CGFloat(level + 1) * step }
            ring.path = ringPath(origin: origin, outer: outer(radii.last!), inner: inner(radii.last!))
            ring.add(keyframes(radii.map { ringPath(origin: origin, outer: outer($0), inner: inner($0)) }, keyTimes),
                     forKey: "ripple")
            layer.mask = ring
            band.addSublayer(layer)
        }
        root.addSublayer(band)
    }

    private static func shapeMask(bounds: CGRect) -> CAShapeLayer {
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.fillRule = .evenOdd
        mask.fillColor = CGColor(gray: 0, alpha: 1)
        return mask
    }

    private static func keyframes(_ paths: [CGPath], _ keyTimes: [NSNumber]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = paths
        animation.keyTimes = keyTimes
        animation.duration = ThemeTransition.duration
        animation.calculationMode = .linear
        return animation
    }

    /// 경로의 요소 수가 늘 같아야 키프레임 사이를 보간한다. 반지름 0도 원으로 남긴다.
    private static func circle(_ origin: CGPoint, _ radius: CGFloat) -> CGRect {
        let radius = max(radius, 0.01)
        return CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2)
    }

    static func holePath(bounds: CGRect, origin: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addEllipse(in: circle(origin, radius))
        return path
    }

    static func ringPath(origin: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: circle(origin, outer))
        path.addEllipse(in: circle(origin, min(max(inner, 0), max(outer, 0))))
        return path
    }
}

/// 글자 두 개를 대각선으로 놓은 한 칸짜리 무늬. 렌더 서버가 창 전체에 타일로 깐다.
/// 벡터로 그리므로 레티나에서도 번지지 않는다.
private enum GlyphPattern {
    final class Tile {
        let line: CTLine
        let cell: CGSize
        let offset: CGPoint

        init(glyph: String, font: NSFont, ink: CGColor, cell: CGSize) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
            ]
            line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: attributes))
            self.cell = cell
            let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            offset = CGPoint(x: (cell.width - glyphBounds.width) / 2 - glyphBounds.minX,
                             y: (cell.height - glyphBounds.height) / 2 - glyphBounds.minY)
        }

        /// 무늬 한 칸을 픽셀 단위로 그린다. 렌더 서버는 무늬를 정의된 크기 그대로 래스터로 굽고
        /// 행렬로 줄여 깐다 — 포인트 단위로 정의하면 1배로 구운 뒤 늘려서 레티나에서 번진다.
        var scale: CGFloat = 1

        func draw(in context: CGContext) {
            context.scaleBy(x: scale, y: scale)
            context.textMatrix = .identity
            for corner in [CGPoint.zero, CGPoint(x: cell.width, y: cell.height)] {
                context.textPosition = CGPoint(x: corner.x + offset.x, y: corner.y + offset.y)
                CTLineDraw(line, context)
            }
        }
    }

    static func color(glyph: String, font: NSFont, ink: CGColor, cell: CGSize, scale: CGFloat) -> CGColor? {
        let tile = Tile(glyph: glyph, font: font, ink: ink, cell: cell)
        tile.scale = scale
        var callbacks = CGPatternCallbacks(version: 0, drawPattern: { info, context in
            guard let info else { return }
            Unmanaged<Tile>.fromOpaque(info).takeUnretainedValue().draw(in: context)
        }, releaseInfo: { info in
            guard let info else { return }
            Unmanaged<Tile>.fromOpaque(info).release()
        })
        let size = CGSize(width: cell.width * 2 * scale, height: cell.height * 2 * scale)
        let info = Unmanaged.passRetained(tile).toOpaque()
        guard let pattern = CGPattern(
            info: info, bounds: CGRect(origin: .zero, size: size),
            matrix: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale),
            xStep: size.width, yStep: size.height, tiling: .constantSpacing,
            isColored: true, callbacks: &callbacks
        ), let space = CGColorSpace(patternBaseSpace: nil) else {
            Unmanaged<Tile>.fromOpaque(info).release()
            return nil
        }
        var alpha: CGFloat = 1
        return CGColor(patternSpace: space, pattern: pattern, components: &alpha)
    }
}
