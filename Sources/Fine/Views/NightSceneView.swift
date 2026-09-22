import SwiftUI

/// 다크 테마의 위쪽에 놓이는 한 장면.
///
/// 번들에 `HomeScene` 이미지가 있으면 그것을 쓰고, 없으면 같은 기조의 밤하늘을 그린다.
/// 그림 자체는 교체 대상이다 — 좋아하는 표지나 일러스트를 그 이름으로 넣으면 된다.
/// (저작권 있는 그림을 저장소에 넣지 않으려고 기본값은 절차적으로 그린다.)
///
/// 아래로 갈수록 사라진다: 장면이 화면을 꽉 채우면 글자와 싸운다. 위에서 시작해
/// 중간쯤에서 바탕으로 녹아들어야 컴포저가 그 위에 뜬 것처럼 읽힌다.
struct NightSceneView: View {
    var reduceMotion = false
    /// 파일을 갈아끼우면 다음에 홈 화면을 열 때 반영된다.
    @State private var userImage: NSImage? = NightSceneView.loadUserImage()

    /// 배경 그림을 찾는 순서:
    ///
    /// 1. `~/.fine/home-scene.{png,jpg,jpeg,heic,webp}` — 파일만 두면 된다.
    ///    빌드도, 저장소도 건드리지 않으므로 좋아하는 그림을 그냥 넣으면 된다.
    /// 2. 번들의 `HomeScene` 에셋 — 빌드에 넣고 싶을 때. 저장소에는 올리지 않는다.
    /// 3. 없으면 아래의 절차적 밤하늘.
    ///
    /// 저작권 있는 그림을 저장소에 넣지 않으려고 기본값을 절차적으로 둔다.
    static var userSceneURL: URL? {
        let directory = FinePaths.home
        for name in ["home-scene.png", "home-scene.jpg", "home-scene.jpeg",
                     "home-scene.heic", "home-scene.webp"] {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.isReadableFile(atPath: url.path) { return url }
        }
        return nil
    }

    private static var bundledArtwork: Bool {
        Bundle.module.image(forResource: "HomeScene") != nil
    }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            Group {
                if let image = userImage {
                    SceneArtwork(image: Image(nsImage: image), width: geometry.size.width)
                } else if Self.bundledArtwork {
                    SceneArtwork(image: Image("HomeScene", bundle: .module), width: geometry.size.width)
                } else {
                    ProceduralNightSky(reduceMotion: reduceMotion)
                }
            }
            .frame(width: geometry.size.width, height: max(height * 0.82, 340))
            .clipped()
            // 위는 그대로, 아래로 갈수록 투명해진다. 가장자리에서 잘린 티가 나면 안 된다.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.42),
                        .init(color: .black.opacity(0.72), location: 0.66),
                        .init(color: .black.opacity(0.28), location: 0.86),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear { userImage = Self.loadUserImage() }
    }

    static func loadUserImage() -> NSImage? {
        guard let url = userSceneURL else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// 넣는 그림은 대개 배너보다 작고 비율도 다르다. 늘려서 채우면 흐려지고,
/// 맞춰 넣으면 옆이 비어 잘린 티가 난다.
///
/// 그래서 두 겹으로 놓는다: 뒤에는 크게 키워 흐린 같은 그림을 깔아 가장자리를 메우고,
/// 앞에는 원본을 비율 그대로 올린다. 흐린 층이 옆을 채우므로 앞 그림을 억지로
/// 늘릴 필요가 없고, 해상도의 한계도 그 흐림 속에 묻힌다.
private struct SceneArtwork: View {
    let image: Image
    let width: CGFloat

    var body: some View {
        ZStack {
            image
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .blur(radius: 28, opaque: true)
                .saturation(1.08)
                .overlay(Color.black.opacity(0.28))

            image
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                // 원본보다 조금만 키운다. 두 배로 늘리면 흐린 층과 겹쳐 더 탁해진다.
                .frame(maxWidth: min(width, 1100))
                .frame(maxWidth: .infinity)
        }
    }
}

/// 절차적 기본 장면: 짙은 블루의 밤하늘, 지평선 근처의 빛무리, 성긴 별.
/// 그림을 흉내내지 않고 색과 빛만 맞춘다.
private struct ProceduralNightSky: View {
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? nil : 1 / 20)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.10, blue: 0.26),
                        Color(red: 0.07, green: 0.13, blue: 0.32),
                        Color(red: 0.04, green: 0.06, blue: 0.14),
                    ],
                    startPoint: .top, endPoint: .bottom
                )

                // 지평선 위로 번지는 빛. 아주 느리게 숨 쉰다 (0.2Hz 아래는 피한다).
                let breathe = reduceMotion ? 0.5 : 0.5 + 0.18 * sin(t / 6)
                RadialGradient(
                    colors: [
                        Color(red: 0.30, green: 0.52, blue: 0.96).opacity(0.42 * breathe + 0.16),
                        Color(red: 0.18, green: 0.28, blue: 0.70).opacity(0.10),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.5, y: 0.74),
                    startRadius: 10, endRadius: 520
                )

                Canvas { context, size in
                    for index in 0..<Stars.points.count {
                        let star = Stars.points[index]
                        let phase = reduceMotion ? 0 : sin(t * star.speed + star.phase)
                        let alpha = star.alpha * (0.62 + 0.38 * (phase * 0.5 + 0.5))
                        let radius = star.radius
                        let rect = CGRect(
                            x: star.x * size.width - radius,
                            y: star.y * size.height - radius,
                            width: radius * 2, height: radius * 2
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                    }
                }
                .blendMode(.plusLighter)
            }
        }
    }
}

/// 고정 난수: 프레임마다 별이 다시 뿌려지면 반짝임이 아니라 잡음이 된다.
private enum Stars {
    struct Point {
        let x: CGFloat, y: CGFloat, radius: CGFloat, alpha: Double, speed: Double, phase: Double
    }

    static let points: [Point] = {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 100_000) / 100_000
        }
        return (0..<90).map { _ in
            let y = next()
            return Point(
                x: next(),
                y: y * 0.82,
                radius: 0.5 + next() * 1.1,
                // 아래쪽 별은 어차피 마스크로 사라지므로 위쪽을 더 밝게 둔다.
                alpha: (0.25 + next() * 0.55) * (1 - y * 0.5),
                speed: 0.4 + next() * 1.1,
                phase: next() * 6.283
            )
        }
    }()
}
