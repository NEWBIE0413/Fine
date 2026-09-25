import SwiftUI

/// 찾기 모드에서 한 번의 찾기가 어디까지 왔는지.
enum QuickFindStatus: Equatable {
    case idle
    /// 최근 대화의 내용을 읽는 중. `fraction`은 실제로 읽은 대화의 몫이다.
    case gathering(query: String, fraction: Double)
    /// Haiku가 고르는 중. 얼마나 남았는지는 알 수 없으므로 보통 걸리는 시간으로 가늠한다.
    case asking(query: String, count: Int, since: Date)
    /// 찾았고, 막대를 거둔 뒤 열 참이다.
    case found(title: String, wasOpen: Bool)
    case notFound(query: String, reason: String)
    case failed(query: String, message: String)

    /// 새 찾기를 받지 않는 동안. 찾은 뒤 여는 사이도 포함한다.
    var isBusy: Bool {
        switch self {
        case .gathering, .asking, .found: true
        case .idle, .notFound, .failed: false
        }
    }

    /// 결과만 남은 상태. 잠시 보여 주고 저절로 접힌다.
    var isSettled: Bool {
        switch self {
        case .notFound, .failed: true
        default: false
        }
    }
}

/// 입력창 아래에서 안내 문구 자리를 잠시 빌려 쓰는 작업 막대.
///
/// 몇 초 걸리는 일을 글자 한 줄로만 알리면 멈춘 것처럼 보인다. 진행은 퍼센트 링 하나로
/// 모은다 — 초와 막대를 함께 두면 같은 사실을 두 번 말해서 눈이 갈 곳이 흩어진다.
struct FindTaskBar: View {
    let status: QuickFindStatus
    var onDismiss: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Haiku가 80개 대화의 요약(약 3만 3천 자)을 읽고 답하는 데 걸린 시간(실측 8.6초, CLI 기동 포함).
    static let expectedAnswer: TimeInterval = 8.5

    var body: some View {
        let palette = FinePalette.resolve(colorScheme)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isAsking || reduceMotion)) { timeline in
            let percent = Self.percent(for: status, at: timeline.date)
            HStack(spacing: 11) {
                indicator(percent: percent)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .fineTracking(12.5)
                        .foregroundStyle(palette.isDark ? palette.ink : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.system(size: 11))
                        .fineTracking(11)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if status.isSettled {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.finePress)
                    .accessibilityLabel("닫기")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.isDark ? palette.glassFill : Color.white.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(palette.isDark ? palette.glassEdgeTop.opacity(0.5) : FineTheme.divider, lineWidth: 1)
                    )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(detail)")
            .accessibilityValue(status.isBusy ? "\(percent)퍼센트" : "")
        }
    }

    private var isAsking: Bool {
        if case .asking = status { return true }
        return false
    }

    /// 읽기는 실제 몫(0~40%), 고르기는 보통 걸리는 시간에 맞춰 95%까지 다가간다.
    /// 더 오래 걸리면 끝 근처에서 천천히 기어간다 — 멈추지도, 다 됐다고 말하지도 않는다.
    static func percent(for status: QuickFindStatus, at now: Date) -> Int {
        switch status {
        case .idle, .notFound, .failed: return 0
        case .gathering(_, let fraction): return Int((3 + 37 * min(max(fraction, 0), 1)).rounded())
        case .asking(_, _, let since):
            let elapsed = max(0, now.timeIntervalSince(since))
            return Int((40 + 55 * (1 - exp(-elapsed / (expectedAnswer / 2.4)))).rounded(.down))
        case .found: return 100
        }
    }

    @ViewBuilder
    private func indicator(percent: Int) -> some View {
        switch status {
        case .gathering, .asking, .idle:
            ZStack {
                Circle().stroke(FineTheme.divider, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(percent) / 100)
                    .stroke(FineTheme.findAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: percent)
                Text("\(percent)%")
                    .font(.system(size: 8, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(1)
        case .found:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(FineTheme.findAccent)
        case .notFound:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    private var title: String {
        switch status {
        case .idle: ""
        case .gathering(let query, _), .asking(let query, _, _): "‘\(query)’ 찾는 중"
        case .found(let title, _): "찾았습니다 · \(title)"
        case .notFound(let query, _): "‘\(query)’에 맞는 대화를 찾지 못했습니다"
        case .failed: "찾지 못했습니다"
        }
    }

    private var detail: String {
        switch status {
        case .idle: ""
        case .gathering: "최근 대화의 내용을 읽는 중"
        case .asking(_, let count, _): "Haiku가 대화 \(count)개의 내용을 훑는 중"
        case .found(_, let wasOpen): wasOpen ? "열려 있는 탭으로 갑니다" : "이어서 엽니다"
        case .notFound(_, let reason): reason.isEmpty ? "설명을 바꿔 다시 찾아보세요" : reason
        case .failed(_, let message): message
        }
    }
}
