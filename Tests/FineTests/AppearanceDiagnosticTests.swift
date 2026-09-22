import SwiftUI
import XCTest
@testable import Fine

/// 다크모드가 화면에 실제로 반영되는지, 토글이 실제로 그려지는지를 픽셀로 확인한다.
final class AppearanceDiagnosticTests: XCTestCase {
    @MainActor
    private func render(_ view: some View, size: CGSize, name: String) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        for _ in 0..<8 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/home-design-review")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: folder.appendingPathComponent("\(name).png"))
        }
        return bitmap
    }

    private func meanBrightness(_ bitmap: NSBitmapImageRep) -> Double {
        var total = 0.0, count = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += (c.redComponent + c.greenComponent + c.blueComponent) / 3
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }

    @MainActor
    func testPreferredColorSchemeActuallyDarkensTheHome() throws {
        let size = CGSize(width: 760, height: 560)
        let home = QuickHomePresentation {
            QuickHomeComposer(prompt: .constant(""), onSubmit: {}) {
                QuickHomeControls {
                    HarnessSegmentedControl(selection: .constant(.claude))
                } options: {
                    Text("Opus 5 · 높음").font(.system(size: 12))
                } send: {
                    Image(systemName: "arrow.up").frame(width: 34, height: 34)
                }
            }
        }
        let light = try render(home.preferredColorScheme(.light), size: size, name: "diag-light")
        let dark = try render(home.preferredColorScheme(.dark), size: size, name: "diag-dark")
        print("밝기 — light \(String(format: "%.3f", meanBrightness(light))) / dark \(String(format: "%.3f", meanBrightness(dark)))")
        XCTAssertGreaterThan(meanBrightness(light), 0.5, "밝은 테마는 밝아야 한다")
        XCTAssertLessThan(meanBrightness(dark), 0.35, "다크 테마가 실제로 어두워지지 않는다")
    }

    /// 컴포저 컨트롤 줄을 실제 구성 그대로 그려서 눈으로 본다.
    @MainActor
    func testComposerControlsRowRenders() throws {
        for (name, scheme) in [("controls-light", ColorScheme.light), ("controls-dark", .dark)] {
            let renderer = ImageRenderer(
                content: ComposerControlsProbe()
                    .environment(\.colorScheme, scheme)
                    .preferredColorScheme(scheme)
            )
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/home-design-review")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: folder.appendingPathComponent("\(name).png"))
            }
            print("\(name) 크기: \(image.size)")
        }
    }
}

/// 컴포저 컨트롤 줄 — QuickHomeView가 실제로 조립하는 것과 같은 구성.
private struct ComposerControlsProbe: View {
    var body: some View {
        HStack(spacing: 10) {
            HarnessSegmentedControl(selection: .constant(.claude))
            HStack(spacing: 6) {
                ModelPillProbe(title: "Opus 5 · 높음", icon: "sparkle")
                ProxyProbe()
            }
            Spacer(minLength: 8)
            SendProbe()
        }
        .padding(14)
        .frame(width: 620)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ModelPillProbe: View {
    let title: String
    let icon: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(title).font(.system(size: 12, weight: .medium)).fineTracking(12).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.65))
        }
        .foregroundStyle(.primary.opacity(0.75))
        .padding(.horizontal, 9)
        .frame(height: FineTheme.compactControlHeight)
        .background(RoundedRectangle(cornerRadius: FineTheme.compactControlRadius, style: .continuous)
            .fill(FineTheme.controlFill))
    }
}

private struct ProxyProbe: View {
    var body: some View {
        Image(systemName: "arrow.triangle.branch")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.72))
            .frame(width: FineTheme.compactControlHeight, height: FineTheme.compactControlHeight)
            .background(RoundedRectangle(cornerRadius: FineTheme.compactControlRadius, style: .continuous)
                .fill(FineTheme.controlFill))
    }
}

private struct SendProbe: View {
    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(red: 0.22, green: 0.27, blue: 0.23)))
    }
}

extension AppearanceDiagnosticTests {
    /// 배경 그림은 다른 저장소들과 같은 `~/.fine`에서 찾아야 한다.
    /// 홈 디렉터리 바로 아래를 보면 사용자가 파일을 제자리에 둬도 영영 안 보인다.
    func testSceneDirectoryIsTheAppDataFolder() {
        let expected = FinePaths.home.appendingPathComponent(".fine", isDirectory: true)
        XCTAssertEqual(NightSceneView.sceneDirectory.path, expected.path)
        XCTAssertNotEqual(NightSceneView.sceneDirectory.path, FinePaths.home.path)
        XCTAssertEqual(NightSceneView.sceneFilenames.first, "home-scene.png")
    }
}
