import AppKit
import QuartzCore
import XCTest
@testable import Fine

final class AmbientBackdropTests: XCTestCase {
    func testRidgesMeetAtLoopBoundaryWithMatchingSlope() {
        for depth in 0...2 {
            XCTAssertEqual(AmbientLandscape.ridge(depth, at: 0), AmbientLandscape.ridge(depth, at: 1), accuracy: 1e-12)
            let epsilon = 1e-5
            let startSlope = (AmbientLandscape.ridge(depth, at: epsilon) - AmbientLandscape.ridge(depth, at: -epsilon)) / (2 * epsilon)
            let endSlope = (AmbientLandscape.ridge(depth, at: 1 + epsilon) - AmbientLandscape.ridge(depth, at: 1 - epsilon)) / (2 * epsilon)
            XCTAssertEqual(startSlope, endSlope, accuracy: 1e-8)
        }
    }

    @MainActor
    func testCharacterGridStaysFixedWhileGlyphsChangeAndLoopExactly() throws {
        let initial = AmbientLandscape.frame(at: 0)
        let next = AmbientLandscape.frame(at: AmbientLandscape.frameInterval)
        XCTAssertEqual(initial.count, 160 * 72)
        XCTAssertEqual(next.count, initial.count)
        let changed = zip(initial, next).filter { $0 != $1 }.count
        XCTAssertGreaterThan(changed, 0)
        XCTAssertLessThan(changed, initial.count / 20, "Only a small fraction of cells should change per frame")
        XCTAssertEqual(initial, AmbientLandscape.frame(at: AmbientLandscape.loopDuration))
        XCTAssertEqual(next, AmbientLandscape.frame(at: AmbientLandscape.loopDuration + AmbientLandscape.frameInterval))
        let renderer = AmbientLandscapeRenderer()
        let image = try XCTUnwrap(renderer.render(at: 0))
        XCTAssertLessThanOrEqual(image.bytesPerRow * image.height, 3 * 1024 * 1024)
        _ = renderer.render(at: 0)
        XCTAssertEqual(renderer.changedCellCount, 0)
        _ = renderer.render(at: AmbientLandscape.frameInterval)
        XCTAssertEqual(renderer.changedCellCount, changed)
        let view = AmbientLandscapeNSView(frame: NSRect(x: 0, y: 0, width: 1400, height: 800))
        view.layout()
        XCTAssertFalse(view.isPlaying)
        XCTAssertNil(view.layer?.sublayers?.first?.animationKeys())
        XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(view.layer?.sublayers?.first?.transform)))
        print("ASCII grid: \(changed) of \(initial.count) cells change per frame; frame buffer \(image.bytesPerRow * image.height) bytes")
    }

    @MainActor
    func testRenderBudgetAndReviewFrames() throws {
        let renderer = AmbientLandscapeRenderer()
        _ = renderer.render(at: 0) // Warm the shared glyph atlas.
        let start = CFAbsoluteTimeGetCurrent()
        for frame in 0..<80 { _ = renderer.render(at: Double(frame) * AmbientLandscape.frameInterval) }
        print("ASCII render average: \((CFAbsoluteTimeGetCurrent() - start) * 1000 / 80) ms/frame")
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/home-design-review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for time in [0.0, 3.0] {
            let image = try XCTUnwrap(renderer.render(at: time))
            let bitmap = NSBitmapImageRep(cgImage: image)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("ascii-\(Int(time)).png"))
        }
    }

    func testReducedMotionLowPowerAndOcclusionPausePlayback() {
        for visible in [false, true] {
            for reduceMotion in [false, true] {
                for lowPower in [false, true] {
                    XCTAssertEqual(AmbientLandscape.shouldAnimate(visible: visible, reduceMotion: reduceMotion, lowPower: lowPower), visible && !reduceMotion && !lowPower)
                }
            }
        }
    }
}
