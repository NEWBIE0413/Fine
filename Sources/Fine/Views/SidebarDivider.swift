import AppKit
import SwiftUI

/// 사이드바와 작업부 사이의 손잡이.
///
/// 드래그 중에는 애니메이션을 걸지 않는다 — 손과 화면이 1:1로 붙어 있어야 하고,
/// 중간에 스프링이 끼면 끌고 있는 것이 손가락이 아니라 다른 것처럼 느껴진다.
struct SidebarDivider: View {
    @Binding var width: Double
    @State private var startWidth: Double?
    @State private var isHovering = false

    static let range: ClosedRange<Double> = 190...460

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            // 실제로 보이는 선은 1pt다. 잡는 자리는 그보다 넓어야 손이 찾는다.
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(Color.primary.opacity(isHovering ? 0.16 : 0))
                    .frame(width: 1)
                    .animation(.easeOut(duration: 0.12), value: isHovering)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                // 커서가 먼저 말해줘야 끌 수 있는 자리인 줄 안다.
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // 잡은 순간의 폭을 기준으로 삼는다. 매 프레임 누적하면 끌수록 어긋난다.
                        let base = startWidth ?? width
                        if startWidth == nil { startWidth = base }
                        width = min(max(base + value.translation.width, Self.range.lowerBound),
                                    Self.range.upperBound)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .accessibilityLabel("사이드바 너비")
            .accessibilityValue("\(Int(width))포인트")
            .accessibilityAdjustableAction { direction in
                let step: Double = direction == .increment ? 16 : -16
                width = min(max(width + step, Self.range.lowerBound), Self.range.upperBound)
            }
    }
}
