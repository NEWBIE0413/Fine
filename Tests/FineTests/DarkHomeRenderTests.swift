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

extension DarkHomeRenderTests {
    /// 외형 설정이 실제로 NSApp까지 도달하는지 — 화면을 보지 않고 확인한다.
    @MainActor
    func testAppearanceReachesTheApplication() {
        let original = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = original }

        FineAppearance.apply(.dark)
        XCTAssertEqual(NSApplication.shared.appearance?.name, .darkAqua)

        FineAppearance.apply(.light)
        XCTAssertEqual(NSApplication.shared.appearance?.name, .aqua)

        FineAppearance.apply(.system)
        XCTAssertNil(NSApplication.shared.appearance, "시스템은 앱 외형을 비워 OS를 따라야 한다")
    }

    /// 저장된 값 읽기가 기동 경로와 같은 키를 쓰는지.
    @MainActor
    func testStoredAppearanceRoundtrips() {
        let defaults = UserDefaults.standard
        let original = defaults.string(forKey: FineAppearance.storageKey)
        defer {
            if let original { defaults.set(original, forKey: FineAppearance.storageKey) }
            else { defaults.removeObject(forKey: FineAppearance.storageKey) }
        }
        defaults.set(FineAppearance.dark.rawValue, forKey: FineAppearance.storageKey)
        XCTAssertEqual(FineAppearance.stored, .dark)
    }
}
