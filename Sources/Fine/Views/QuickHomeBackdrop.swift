import SwiftUI

/// A fixed-grid ASCII landscape behind a light, unblurred glass veil.
struct QuickHomeBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let paper = Color(red: 0.965, green: 0.962, blue: 0.948)

    var body: some View {
        ZStack {
            Self.paper
            if !reduceTransparency {
                AmbientLandscapeView(reduceMotion: reduceMotion)
                // A milk-glass veil preserves the character edges without a costly blur.
                LinearGradient(
                    stops: [
                        .init(color: Self.paper.opacity(0.95), location: 0),
                        .init(color: Self.paper.opacity(0.72), location: 0.35),
                        .init(color: Self.paper.opacity(0.20), location: 0.75),
                        .init(color: Self.paper.opacity(0.44), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(
                    colors: [Self.paper.opacity(0.78), Self.paper.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.42),
                    startRadius: 60, endRadius: 440
                )
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Home-only composition: the terminal and navigation keep their own surfaces.
struct QuickHomePresentation<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = geometry.size.width < 620 ? 24 : 48
            ScrollView(.vertical) {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Text("생각을 펼칠 시간")
                            .font(.system(size: geometry.size.width < 620 ? 28 : 34, weight: .medium))
                            .tracking(-1.1)
                            .foregroundStyle(Color(red: 0.19, green: 0.21, blue: 0.19))
                        Text("질문도, 아이디어도. 여기서 시작하세요.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .accessibilityElement(children: .combine)

                    content
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, inset)
                .padding(.top, 64)
                .padding(.bottom, geometry.size.height > 620 ? 112 : 48)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .background(QuickHomeBackdrop())
    }
}

struct QuickHomeComposer<Controls: View>: View {
    @Binding var prompt: String
    @FocusState private var isPromptFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let onSubmit: () -> Void
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(spacing: 0) {
            TextField("무엇이든 물어보세요", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineSpacing(5)
                .lineLimit(3...8)
                .focused($isPromptFocused)
                .onSubmit(onSubmit)
                .accessibilityLabel("새 대화 메시지")
                .frame(minHeight: 88, alignment: .topLeading)
                .padding(22)

            controls
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(reduceTransparency ? 1 : 0.82))
        }
        .shadow(color: Color(red: 0.27, green: 0.30, blue: 0.26).opacity(0.07), radius: 24, y: 10)
        .onAppear { isPromptFocused = true }
    }
}

/// Prefer a single row, then move harness selection above model controls.
/// Measuring ideal widths also handles long model names without device guesses.
struct QuickHomeControls<Harness: View, Options: View, Send: View>: View {
    @ViewBuilder var harness: Harness
    @ViewBuilder var options: Options
    @ViewBuilder var send: Send

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                harness
                options
                Spacer(minLength: 8)
                send
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    harness
                    Spacer(minLength: 8)
                }
                HStack(spacing: 8) {
                    options
                    Spacer(minLength: 8)
                    send
                }
            }
        }
    }
}
