import SwiftUI

/// 밝은 쪽은 ASCII 풍경 위에 젖빛 유리를, 어두운 쪽은 짙은 밤 위에 한 장면을 올린다.
struct QuickHomeBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    static let paper = Color(red: 0.965, green: 0.962, blue: 0.948)

    var body: some View {
        let palette = FinePalette.resolve(colorScheme)
        ZStack {
            if palette.isDark { darkBody(palette) } else { lightBody }
        }
        // 배경이 그림이면 움직이는 것이 없다. 여섯 겹을 GPU에서 한 겹으로 합쳐
        // 매 프레임 다시 합성하지 않게 한다. 절차적 하늘일 때는 매 프레임 달라지므로
        // 평탄화가 오히려 비용이 된다.
        .flattenedWhenStatic(NightSceneView.isStatic)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func darkBody(_ palette: FinePalette) -> some View {
        palette.base

        if !reduceTransparency {
            NightSceneView(reduceMotion: reduceMotion)

            // 그림이 밝으면 제목과 컴포저가 묻힌다. 장면만 한 단 가라앉힌다.
            palette.sceneScrim

            // 컴포저가 앉는 자리 뒤에서 올라오는 빛. 유리에 두께가 생긴다.
            // blendMode는 화면 전체를 오프스크린으로 한 번 더 그리게 만든다.
            // 빛무리는 어두운 바탕 위라 더하기 합성이 아니어도 같은 인상이 난다.
            RadialGradient(
                colors: [palette.bloom.opacity(0.42), palette.bloom.opacity(0.12), .clear],
                center: UnitPoint(x: 0.5, y: 0.56),
                startRadius: 30, endRadius: 480
            )

            // 아래쪽을 바탕으로 눌러 장면이 끝나는 자리를 감춘다.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.54),
                    .init(color: palette.base.opacity(0.22), location: 0.68),
                    .init(color: palette.base.opacity(0.58), location: 0.80),
                    .init(color: palette.base.opacity(0.86), location: 0.90),
                    .init(color: palette.base, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            // 네 모서리를 살짝 떨어뜨려 가운데로 시선을 모은다.
            RadialGradient(
                colors: [.clear, .black.opacity(0.26)],
                center: .center, startRadius: 340, endRadius: 820
            )
        }
    }

    @ViewBuilder
    private var lightBody: some View {
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
    }
}

/// Home-only composition: the terminal and navigation keep their own surfaces.
struct QuickHomePresentation<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var greetings = HomeGreetingPicker.shared
    @ObservedObject private var scanner = QuickConversationScanner.shared
    @ViewBuilder var content: Content

    var body: some View {
        let palette = FinePalette.resolve(colorScheme)
        GeometryReader { geometry in
            let inset: CGFloat = geometry.size.width < 620 ? 24 : 48
            ScrollView(.vertical) {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        // 큰 글자는 자간을 조이고 행간을 좁혀야 한 덩어리로 읽힌다.
                        // 세리프는 문장에 무게를 주므로 인용에 맞고, 아래 출처는 산세리프로
                        // 낮춰 둘의 역할을 갈라놓는다.
                        Text(greetings.line)
                            .font(FineDisplayFont.greeting(
                                size: geometry.size.width < 620 ? 27 : 33,
                                isDark: palette.isDark
                            ))
                            .tracking(FineDisplayFont.greetingTracking(isDark: palette.isDark))
                            .lineSpacing(4)
                            .foregroundStyle(palette.ink)
                            .frame(maxWidth: 560)
                            .animation(.easeInOut(duration: 0.35), value: greetings.line)
                        Text(greetings.note)
                            .font(.system(size: 12, weight: .medium))
                            .tracking(0.2)
                            // 어두운 배경 위에서 회색 글자는 가라앉는다. 대비를 올린다.
                            .foregroundStyle(palette.isDark ? palette.ink.opacity(0.52) : .secondary)
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
        .onAppear { greetings.refreshIfNeeded(conversations: scanner.conversations) }
        .onChange(of: scanner.conversations) { _, list in
            greetings.refreshIfNeeded(conversations: list)
        }
    }
}

struct QuickHomeComposer<Controls: View>: View {
    @Binding var prompt: String
    @FocusState private var isPromptFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let onSubmit: () -> Void
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(spacing: 0) {
            TextField("무엇이든 물어보세요", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .fineTracking(16)
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
        .background { glass }
        .shadow(color: palette.shadow, radius: palette.isDark ? 34 : 24, y: palette.isDark ? 16 : 10)
        .onAppear { isPromptFocused = true }
        .environment(\.finePalette, palette)
    }

    private var palette: FinePalette { .resolve(colorScheme) }

    /// 큰 표면일수록 두꺼워 보여야 한다 — 어두운 쪽은 실제 블러를 쓰고,
    /// 위쪽 모서리만 밝게 해서 빛을 받는 유리로 읽히게 한다.
    @ViewBuilder
    private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if reduceTransparency {
            shape.fill(palette.isDark ? palette.base : .white)
                .overlay(shape.strokeBorder(palette.divider, lineWidth: 1))
        } else {
            ZStack {
                if palette.isDark {
                    shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                }
                if palette.isDark {
                    shape.fill(
                        LinearGradient(
                            colors: [palette.glassFill.opacity(0.72), palette.glassFill],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                } else {
                    shape.fill(palette.glassFill)
                }
                if palette.isDark {
                    // 위에서 빛이 들어오는 면. 유리에 두께가 생긴다.
                    shape.fill(
                        LinearGradient(
                            colors: [.white.opacity(0.07), .clear],
                            startPoint: .top, endPoint: .center
                        )
                    )
                }
                shape.strokeBorder(
                    LinearGradient(
                        colors: [palette.glassEdgeTop, palette.glassEdgeBottom],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
        }
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


private extension View {
    /// 조건부로 한 겹으로 합친다. `.disabled`는 상호작용만 막을 뿐 그리기에는 영향이 없다.
    @ViewBuilder
    func flattenedWhenStatic(_ flatten: Bool) -> some View {
        if flatten {
            drawingGroup(opaque: false, colorMode: .nonLinear)
        } else {
            self
        }
    }
}
