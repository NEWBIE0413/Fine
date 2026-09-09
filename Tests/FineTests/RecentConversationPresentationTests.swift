import AppKit
import SwiftUI
import XCTest
@testable import Fine

final class RecentConversationPresentationTests: XCTestCase {
    @MainActor
    func testEveryHarnessHasAVisibleVectorAssetAndFitsTheSidebar() throws {
        for harness in QuickHarness.allCases {
            let image = try XCTUnwrap(Bundle.module.image(forResource: NSImage.Name(harness.rawValue)))
            XCTAssertGreaterThan(image.size.width, 0)
            let renderer = ImageRenderer(content: HarnessLogo(harness: harness).padding(8))
            renderer.scale = 2
            let cgImage = try XCTUnwrap(renderer.cgImage)
            let pixels = NSBitmapImageRep(cgImage: cgImage)
            var inkPixels = 0
            for y in 0..<pixels.pixelsHigh {
                for x in 0..<pixels.pixelsWide {
                    if let color = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.1 {
                        inkPixels += 1
                        XCTAssertEqual(color.redComponent, color.greenComponent, accuracy: 0.02)
                        XCTAssertEqual(color.greenComponent, color.blueComponent, accuracy: 0.02)
                    }
                }
            }
            XCTAssertGreaterThan(inkPixels, 40, "\(harness) logo must contain visible ink")
        }

        let rows = QuickHarness.allCases.map { harness in
            QuickConversation(
                id: harness == .opencode ? "ses_example" : UUID().uuidString,
                title: "Fine 디자인과 최근 대화 목록 개선하기", aiTitle: nil,
                modifiedAt: Date().addingTimeInterval(-3600), transcriptURL: nil, harness: harness
            )
        }
        let root = VStack(alignment: .leading, spacing: 3) {
            Text("최근 항목").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.bottom, 6)
            ForEach(rows, id: \.listID) { conversation in
                QuickRecentConversationRow(conversation: conversation, onResume: {})
            }
        }
        .padding(12)
        .frame(width: 248)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.light)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 248, height: 170)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(hosting.fittingSize.width, 248)
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/recent-design-review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("sidebar.png"))
    }
}
