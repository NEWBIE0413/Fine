import SwiftUI

/// SwiftUI의 `openWindow`는 뷰 환경 밖에서 부를 수 없다. 창이 하나라도 떠 있으면 그 창의
/// ContentView가 자기 openWindow 액션을 여기에 걸어두고, CLI는 이걸로 새 창을 연다.
///
/// 한계: 창이 모두 닫힌 채 앱만 살아 있으면 마지막으로 등록된 액션이 남아 있어 그대로
/// 동작하지만, 앱 기동 직후 첫 ContentView가 나타나기 전에는 nil이다 — CLI는 소켓이
/// 열린 뒤 잠깐 기다리므로 실제로는 거의 겹치지 않는다.
@MainActor
enum WindowOpener {
    static var open: ((_ id: UUID) -> Void)?

    static func register(_ action: OpenWindowAction) {
        open = { id in action(id: "main", value: id) }
    }
}
