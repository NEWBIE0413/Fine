import AppKit
import SwiftUI
import XCTest
@testable import Fine

/// 찾기 모드를 눈으로 확인하기 위한 렌더. `.build/home-design-review/find-*.png`로 저장된다.
final class FindModeRenderTests: XCTestCase {
    @MainActor
    func testHomeRendersInBothModesAndThemes() throws {
        let stateFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("fine-find-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateFile) }
        let state = AppState(storage: WindowStateStorage(stateFile: stateFile))
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/home-design-review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for (name, finding, dark) in [("find-off-light", false, false), ("find-on-light", true, false),
                                      ("find-off-dark", false, true), ("find-on-dark", true, true)] {
            let hosting = NSHostingView(rootView: QuickHomeView(finding: finding).environmentObject(state))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for _ in 0..<8 {
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: folder.appendingPathComponent("\(name).png"))
        }
    }

    /// 입력창 아래에서 바뀌어 드는 작업 막대의 상태들.
    @MainActor
    func testTaskBarRendersEveryState() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/home-design-review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let states: [QuickFindStatus] = [
            .gathering(query: "zeb 브라우저 만든 세션", fraction: 0.5),
            .asking(query: "zeb 브라우저 만든 세션", count: 80, since: Date(timeIntervalSinceNow: -3)),
            .found(title: "이미지 분석", wasOpen: true),
            .notFound(query: "zeb", reason: "zeb 브라우저를 만든 대화는 최근 목록에 없습니다."),
            .failed(query: "zeb", message: "Invalid API key · Please run /login"),
        ]
        for dark in [false, true] {
            let stack = VStack(spacing: 12) {
                ForEach(Array(states.enumerated()), id: \.offset) { _, status in
                    FindTaskBar(status: status)
                }
            }
            .padding(24)
            .frame(width: 620)
            .background(dark ? FinePalette.dark.base : FinePalette.light.base)
            let hosting = NSHostingView(rootView: stack)
            hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            for _ in 0..<4 {
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            XCTAssertGreaterThan(hosting.fittingSize.height, 200)
            XCTAssertEqual(FindTaskBar.percent(for: states[0], at: Date()), 22)
            XCTAssertEqual(FindTaskBar.percent(for: states[2], at: Date()), 100)
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: folder.appendingPathComponent("taskbar-\(dark ? "dark" : "light").png"))
        }
    }
}
