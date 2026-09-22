import AppKit
import Foundation

/// 홈 화면 배경 그림을 고르고 치운다.
///
/// 파일은 `~/.fine`에 둔다 — 앱 번들이 아니라서 다시 빌드할 필요가 없고,
/// 저장소 밖이라 남의 그림이 커밋에 딸려 들어갈 일도 없다.
enum HomeSceneLibrary {
    static let didChange = Notification.Name("FineHomeSceneDidChange")

    static var directory: URL {
        FinePaths.home.appendingPathComponent(".fine", isDirectory: true)
    }

    /// 고른 그림은 확장자만 바꿔 같은 이름으로 둔다. 여러 개가 남으면
    /// 어느 것이 쓰이는지 알 수 없으므로 넣기 전에 기존 것을 치운다.
    static func install(from source: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try removeExisting()
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let destination = directory.appendingPathComponent("home-scene.\(ext)")
        try fileManager.copyItem(at: source, to: destination)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func clear() throws {
        try removeExisting()
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static var hasScene: Bool {
        NightSceneView.userSceneURL != nil
    }

    private static func removeExisting() throws {
        let fileManager = FileManager.default
        for name in NightSceneView.sceneFilenames {
            let url = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    /// 파일 선택창. 받아들이는 형식은 로더가 찾는 것과 같아야 한다.
    @MainActor
    static func chooseAndInstall() {
        let panel = NSOpenPanel()
        panel.title = "홈 배경 고르기"
        panel.prompt = "배경으로 쓰기"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try install(from: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
