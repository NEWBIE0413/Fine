import CoreGraphics
import XCTest
@testable import Fine

final class ThemeTransitionTests: XCTestCase {
    func testHomeContentIsRevealedPromptlyAndTheWaveClearsTheWindow() {
        let size = CGSize(width: 980, height: 700)
        let toggle = CGPoint(x: 218, y: 72)
        let prompt = CGPoint(x: 610, y: 345)
        let corners = [
            CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height),
        ]
        let reach = corners.map { hypot($0.x - toggle.x, $0.y - toggle.y) }.max()!
        let firstMoment = ThemeTransitionOverlay.radius(
            progress: 0.11 / ThemeTransition.duration, reach: reach
        )
        XCTAssertGreaterThan(
            firstMoment - 14, hypot(prompt.x - toggle.x, prompt.y - toggle.y),
            "The new-conversation composer should emerge within 110 ms of the wave starting"
        )
        XCTAssertGreaterThan(
            ThemeTransitionOverlay.radius(progress: 1, reach: reach), reach,
            "The old frame must be gone when the animation ends"
        )
    }
}
