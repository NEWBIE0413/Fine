import AppKit
import Metal
import QuartzCore
import XCTest
@testable import Fine

final class ThemeTransitionTests: XCTestCase {
    func testTheWaveClearsTheWholeWindowByTheEnd() {
        let size = CGSize(width: 980, height: 700)
        let origin = CGPoint(x: 218, y: 72)
        let reach = ThemeTransition.farthestCorner(from: origin, in: size)
        XCTAssertEqual(ThemeTransition.radius(progress: 0, reach: reach), 0)
        // 띠의 맨 뒤까지 창 밖으로 나가야 끝에 글자가 남지 않는다.
        XCTAssertGreaterThanOrEqual(
            ThemeTransition.radius(progress: 1, reach: reach) - ThemeTransition.bandWidth, reach
        )
    }

    /// 파문은 벽시계가 아니라 레이어 애니메이션이다. 렌더 서버와 같은 렌더러로 그려서
    /// 구멍이 누른 자리에서 열리고, 앞머리 뒤로 글자가 따라오고, 끝나면 아무것도 남지 않는지 본다.
    ///
    /// CARenderer는 첫 프레임 뒤로는 경로 애니메이션을 다시 그리지 않는다. 그래서 시점마다
    /// 레이어를 새로 깔고 그 시점의 첫 프레임을 찍는다.
    @MainActor
    func testLayersOpenFromTheOriginAndLeaveNothingBehind() throws {
        let size = CGSize(width: 480, height: 320)
        // 누른 자리: 레이어 좌표(아래가 0)로 왼쪽 위 근처.
        let origin = CGPoint(x: 80, y: 260)
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/ripple-review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        func frame(at elapsed: CFTimeInterval) throws -> Frame {
            let renderer = try Renderer(size: size, scale: 2)
            ThemeRippleLayers.install(
                in: renderer.content, size: size,
                snapshot: try XCTUnwrap(Self.solidImage(width: 960, height: 640)), origin: origin,
                ink: CGColor(gray: 1, alpha: 1), scale: 2, observer: nil
            )
            CATransaction.flush()
            let result = try renderer.render(at: CACurrentMediaTime() + elapsed)
            try result.write(folder.appendingPathComponent("t\(Int(elapsed * 1000)).png"))
            return result
        }

        // 시작 직후: 옛 화면이 거의 그대로다.
        let early = try frame(at: 0.02)
        XCTAssertTrue(early.isSnapshot(atPoint: CGPoint(x: size.width - 10, y: 10)))
        XCTAssertFalse(early.isSnapshot(atPoint: origin), "the hole must open where the toggle was pressed")

        // 한가운데: 누른 자리는 새 화면(투명), 먼 모서리는 아직 옛 화면이다.
        let middle = try frame(at: ThemeTransition.duration * 0.35)
        XCTAssertFalse(middle.isSnapshot(atPoint: CGPoint(x: origin.x + 150, y: origin.y - 60)))
        XCTAssertTrue(middle.isSnapshot(atPoint: CGPoint(x: size.width - 4, y: 4)), "far corner still shows the old frame")
        XCTAssertGreaterThan(middle.inkPixels, 200, "glyphs must trail the wave front")

        // 끝난 뒤: 옛 화면도 글자도 남지 않는다.
        let after = try frame(at: ThemeTransition.duration + 0.05)
        XCTAssertEqual(after.redPixels, 0)
        XCTAssertEqual(after.inkPixels, 0)
    }

    /// 실제 창에서: 파문 뷰가 붙었다가 끝나면 떨어지고, 계측값이 돌아온다.
    @MainActor
    func testRippleRunsInAWindowAndCleansUp() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        let content = NSView(frame: window.contentLayoutRect)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.systemTeal.cgColor
        window.contentView = content
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        var applied = false
        var timing: ThemeTransition.Timing?
        ThemeTransition.ripple(from: CGPoint(x: 40, y: 40), in: window, applying: { applied = true }) {
            timing = $0
        }
        XCTAssertTrue(applied)
        let host = try XCTUnwrap(content.superview)
        XCTAssertTrue(host.subviews.contains { $0 is ThemeRippleView })

        // 창에서는 렌더 서버가 돌린다. 앞머리 고리의 반지름이 시간에 따라 곡선대로 자라는지 본다.
        let ripple = try XCTUnwrap(host.subviews.lazy.compactMap { $0 as? ThemeRippleView }.first)
        var radii: [CGFloat] = []
        let deadline = Date().addingTimeInterval(3)
        while timing == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let front = ripple.layer?.sublayers?.last?.sublayers?.first?.mask as? CAShapeLayer
            if timing == nil, let path = front?.presentation()?.path {
                radii.append(path.boundingBoxOfPath.width / 2)
            }
        }
        XCTAssertGreaterThanOrEqual(radii.count, 4)
        XCTAssertEqual(radii, radii.sorted(), "the wave must only grow")
        XCTAssertLessThan(radii.first ?? .infinity, radii.last ?? 0)
        let result = try XCTUnwrap(timing, "the ripple never finished")
        XCTAssertFalse(host.subviews.contains { $0 is ThemeRippleView }, "the overlay must leave when done")
        let ran = try XCTUnwrap(result.ranMs)
        XCTAssertEqual(ran, ThemeTransition.duration * 1000, accuracy: 120)
        XCTAssertNotNil(result.startDelayMs)
    }

    // MARK: - 렌더러

    static func solidImage(width: Int, height: Int) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }

    /// 렌더 서버와 같은 경로(CARenderer)로 레이어 트리를 한 장 그린다.
    final class Renderer {
        let content = CALayer()
        private let root = CALayer()
        private let renderer: CARenderer
        private let texture: MTLTexture
        private let queue: MTLCommandQueue
        private let scale: CGFloat

        init(size: CGSize, scale: CGFloat) throws {
            self.scale = scale
            let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: Int(size.width * scale), height: Int(size.height * scale),
                mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            queue = try XCTUnwrap(device.makeCommandQueue())
            renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
            root.frame = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
            content.anchorPoint = .zero
            content.bounds = CGRect(origin: .zero, size: size)
            content.position = .zero
            content.transform = CATransform3DMakeScale(scale, scale, 1)
            root.addSublayer(content)
            renderer.layer = root
            renderer.bounds = root.frame
        }

        func render(at time: CFTimeInterval) throws -> Frame {
            renderer.beginFrame(atTime: time, timeStamp: nil)
            renderer.addUpdate(renderer.bounds)
            renderer.render()
            renderer.endFrame()
            // 렌더러가 같은 큐에 넣은 작업이 끝날 때까지 기다린다.
            let buffer = try XCTUnwrap(queue.makeCommandBuffer())
            buffer.commit()
            buffer.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
            texture.getBytes(&bytes, bytesPerRow: texture.width * 4,
                             from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            return Frame(bytes: bytes, width: texture.width, height: texture.height, scale: scale)
        }
    }

    struct Frame {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        let scale: CGFloat

        /// BGRA. 렌더러는 레이어 좌표처럼 아래 행부터 담는다.
        private func pixel(_ point: CGPoint) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8) {
            let x = min(width - 1, max(0, Int(point.x * scale)))
            let y = min(height - 1, max(0, Int(point.y * scale)))
            let index = (y * width + x) * 4
            return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
        }

        func isSnapshot(atPoint point: CGPoint) -> Bool {
            let p = pixel(point)
            return p.r > 200 && p.g < 60 && p.b < 60 && p.a > 200
        }

        var redPixels: Int {
            stride(from: 0, to: bytes.count, by: 4).reduce(0) { count, index in
                count + (bytes[index + 2] > 200 && bytes[index + 1] < 60 ? 1 : 0)
            }
        }

        /// 옛 화면(빨강)이 아닌 밝은 픽셀 — 글자 띠.
        var inkPixels: Int {
            stride(from: 0, to: bytes.count, by: 4).reduce(0) { count, index in
                let b = bytes[index], g = bytes[index + 1], r = bytes[index + 2]
                return count + (g > 40 && b > 40 && abs(Int(r) - Int(g)) < 40 ? 1 : 0)
            }
        }

        func write(_ url: URL) throws {
            let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
            let image = try XCTUnwrap(CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ))
            let rep = NSBitmapImageRep(cgImage: image)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        }
    }
}
