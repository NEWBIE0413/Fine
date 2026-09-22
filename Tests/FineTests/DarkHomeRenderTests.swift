import SwiftUI
import XCTest
@testable import Fine

/// 다크 테마를 눈으로 확인하기 위한 렌더. `.build/home-design-review/dark-*.png`로 저장된다.
final class DarkHomeRenderTests: XCTestCase {
    @MainActor
    func testDarkHomeRenders() throws {
        for (name, size) in [
            ("dark-standard", CGSize(width: 980, height: 700)),
            ("dark-minimum", CGSize(width: 520, height: 560)),
        ] {
            let root = QuickHomePresentation {
                VStack(spacing: 14) {
                    QuickHomeComposer(prompt: .constant(""), onSubmit: {}) {
                        QuickHomeControls {
                            HarnessSegmentedControl(selection: .constant(.claude))
                        } options: {
                            HStack(spacing: 6) {
                                Label("Opus 5 · 높음", systemImage: "sparkle")
                                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                            }
                            .padding(9)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        } send: {
                            Image(systemName: "arrow.up")
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                    Text("질문 난이도를 보고 모델과 깊이를 골라 시작합니다")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .preferredColorScheme(.dark)

            let hosting = NSHostingView(rootView: root)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.contentView = hosting
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.appearance = NSAppearance(named: .darkAqua)
            for _ in 0..<8 {
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/home-design-review")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }
}
