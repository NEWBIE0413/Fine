import SwiftUI
import AppKit

/// 하네스가 넷이 되면 세그먼트는 컴포저 줄의 절반을 먹는다. 드롭다운 하나로 접는다.
///
/// SwiftUI의 `Menu`는 `.borderlessButton` 스타일에서 라벨을 자기 방식으로 다시 그려
/// 배경과 chevron이 사라진다. 옆의 모델 버튼과 생김새가 달라지므로, 메뉴는 AppKit으로
/// 직접 띄우고 라벨은 우리가 그린 알약을 그대로 쓴다.
struct HarnessSegmentedControl: View {
    @Binding var selection: QuickHarness
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            present()
        } label: {
            FineControlPill(title: selection.title) {
                Image(selection.rawValue, bundle: .module)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            }
        }
        .buttonStyle(.finePress)
        .fixedSize()
        .accessibilityLabel("하네스")
        .accessibilityValue(selection.title)
        .help("대화를 실행할 하네스")
    }

    private func present() {
        let menu = NSMenu()
        for harness in QuickHarness.allCases {
            let item = NSMenuItem(
                title: harness.title,
                action: #selector(MenuTarget.pick(_:)),
                keyEquivalent: ""
            )
            item.target = MenuTarget.shared
            item.representedObject = harness.rawValue
            item.state = harness == selection ? .on : .off
            MenuTarget.shared.onPick = { selection = $0 }
            menu.addItem(item)
        }
        if let view = NSApp.keyWindow?.contentView,
           let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }
    }

    /// NSMenu는 Objective-C 타깃을 요구한다. 선택을 SwiftUI 바인딩으로 되돌린다.
    private final class MenuTarget: NSObject {
        static let shared = MenuTarget()
        var onPick: ((QuickHarness) -> Void)?

        @objc func pick(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String,
                  let harness = QuickHarness(rawValue: raw) else { return }
            onPick?(harness)
        }
    }
}

/// 컴포저 줄의 컨트롤은 전부 같은 알약이어야 한다 — 모델 버튼, 하네스 버튼, 프록시 버튼.
/// 한 곳에서 그려야 셋이 어긋나지 않는다.
struct FineControlPill<Leading: View>: View {
    let title: String
    /// 메뉴를 여는 알약은 chevron, 모드를 끄는 알약은 xmark.
    var trailingSymbol = "chevron.down"
    @ViewBuilder var leading: Leading
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            leading
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .fineTracking(12)
                .lineLimit(1)
            Image(systemName: trailingSymbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.65))
        }
        .foregroundStyle(.primary.opacity(0.75))
        .padding(.horizontal, 9)
        .frame(height: FineTheme.compactControlHeight)
        .background(
            FinePalette.resolve(colorScheme).controlFill,
            in: RoundedRectangle(cornerRadius: FineTheme.compactControlRadius, style: .continuous)
        )
        .contentShape(Rectangle())
    }
}
